import { describe, expect, it } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";

const packageDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const cliPath = join(packageDir, "src", "native-messaging-cli.ts");
const fixturePath = join(packageDir, "fixtures", "active-tab.json");

const createFakeOsaScriptBinary = async (stdoutFilePath: string): Promise<string> => {
  const dir = await mkdtemp(join(tmpdir(), "context-grabber-chrome-osa-"));
  const binaryPath = join(dir, "fake-osascript.sh");

  await writeFile(
    binaryPath,
    ["#!/bin/sh", `cat "${stdoutFilePath}"`, "exit 0", ""].join("\n"),
    "utf8",
  );
  await chmod(binaryPath, 0o755);
  return binaryPath;
};

const createSlowFakeOsaScriptBinary = async (stdoutFilePath: string): Promise<string> => {
  const dir = await mkdtemp(join(tmpdir(), "context-grabber-chrome-osa-slow-"));
  const binaryPath = join(dir, "slow-fake-osascript.sh");

  await writeFile(
    binaryPath,
    ["#!/bin/sh", "sleep 1", `cat "${stdoutFilePath}"`, "exit 0", ""].join("\n"),
    "utf8",
  );
  await chmod(binaryPath, 0o755);
  return binaryPath;
};

const runCli = (args: string[] = [], stdinText = "", extraEnv: Record<string, string> = {}) => {
  return spawnSync("bun", [cliPath, ...args], {
    cwd: packageDir,
    input: stdinText,
    encoding: "utf8",
    env: {
      ...process.env,
      CONTEXT_GRABBER_CHROME_SOURCE: "",
      CONTEXT_GRABBER_CHROME_FIXTURE_PATH: "",
      CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD: "",
      CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD_PATH: "",
      CONTEXT_GRABBER_CHROME_OSASCRIPT_BIN: "",
      ...extraEnv,
    },
  });
};

const parseLastJsonLine = (stdout: string): unknown => {
  const lines = stdout
    .split(/\r?\n/g)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  return JSON.parse(lines[lines.length - 1] ?? "{}");
};

describe("chrome native messaging cli", () => {
  it("returns ping response", () => {
    const result = runCli(["--ping"]);
    expect(result.status).toBe(0);

    const parsed = parseLastJsonLine(result.stdout);
    if (typeof parsed !== "object" || parsed === null) {
      throw new Error("Invalid ping response.");
    }

    expect((parsed as { ok?: boolean }).ok).toBe(true);
    expect((parsed as { protocolVersion?: string }).protocolVersion).toBe(PROTOCOL_VERSION);
  });

  it("handles host capture request via stdin", () => {
    const request: HostRequestMessage = {
      id: "req-cli-1",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-cli-1",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 1200,
        includeSelectionText: true,
      },
    };

    const result = runCli([], JSON.stringify(request), {
      CONTEXT_GRABBER_CHROME_FIXTURE_PATH: fixturePath,
      CONTEXT_GRABBER_CHROME_SOURCE: "fixture",
    });
    expect(result.status).toBe(0);

    const parsed = parseLastJsonLine(result.stdout);
    if (typeof parsed !== "object" || parsed === null) {
      throw new Error("Invalid capture response.");
    }

    expect((parsed as { type?: string }).type).toBe("extension.capture.result");
  });

  it("returns extension.error in auto mode when live and runtime sources are unavailable", () => {
    const request: HostRequestMessage = {
      id: "req-cli-2",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-cli-2",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 1200,
        includeSelectionText: true,
      },
    };

    const result = runCli([], JSON.stringify(request), {
      CONTEXT_GRABBER_CHROME_SOURCE: "auto",
      CONTEXT_GRABBER_CHROME_FIXTURE_PATH: fixturePath,
      CONTEXT_GRABBER_CHROME_OSASCRIPT_BIN: "/path/that/does/not/exist/osascript",
    });
    expect(result.status).toBe(0);

    const parsed = parseLastJsonLine(result.stdout);
    if (typeof parsed !== "object" || parsed === null) {
      throw new Error("Invalid auto-mode response.");
    }

    expect((parsed as { type?: string }).type).toBe("extension.error");
    expect((parsed as { payload?: { code?: string } }).payload?.code).toBe(
      "ERR_EXTENSION_UNAVAILABLE",
    );
  });

  it("strips selectionText for runtime payload when includeSelectionText is false", () => {
    const request: HostRequestMessage = {
      id: "req-cli-4",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-cli-4",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 1200,
        includeSelectionText: false,
      },
    };

    const runtimePayload = JSON.stringify({
      url: "https://example.com/runtime",
      title: "Runtime Capture",
      fullText: "Runtime text.",
      headings: [],
      links: [],
      selectionText: "Should be dropped",
    });

    const result = runCli([], JSON.stringify(request), {
      CONTEXT_GRABBER_CHROME_SOURCE: "runtime",
      CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD: runtimePayload,
    });
    expect(result.status).toBe(0);

    const parsed = parseLastJsonLine(result.stdout);
    if (typeof parsed !== "object" || parsed === null) {
      throw new Error("Invalid runtime response.");
    }

    expect((parsed as { type?: string }).type).toBe("extension.capture.result");
    expect(
      (
        parsed as {
          payload?: { capture?: { selectionText?: string } };
        }
      ).payload?.capture?.selectionText,
    ).toBe(undefined);
  });

  it("handles host capture request via live source mode with configured osascript binary", async () => {
    const request: HostRequestMessage = {
      id: "req-cli-3",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-cli-3",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 1200,
        includeSelectionText: true,
      },
    };

    const fixtureOutputPath = join(tmpdir(), `context-grabber-chrome-cli-live-${Date.now()}.json`);
    let fakeOsaBinary: string | undefined;
    try {
      await writeFile(
        fixtureOutputPath,
        JSON.stringify({
          url: "https://example.com/live",
          title: "Live Mode",
          fullText: "Live capture text.",
          headings: [],
          links: [],
        }),
        "utf8",
      );
      fakeOsaBinary = await createFakeOsaScriptBinary(fixtureOutputPath);

      const result = runCli([], JSON.stringify(request), {
        CONTEXT_GRABBER_CHROME_SOURCE: "live",
        CONTEXT_GRABBER_CHROME_OSASCRIPT_BIN: fakeOsaBinary,
      });
      expect(result.status).toBe(0);

      const parsed = parseLastJsonLine(result.stdout);
      if (typeof parsed !== "object" || parsed === null) {
        throw new Error("Invalid live-mode response.");
      }

      expect((parsed as { type?: string }).type).toBe("extension.capture.result");
    } finally {
      await rm(fixtureOutputPath, { force: true });
      if (fakeOsaBinary) {
        await rm(dirname(fakeOsaBinary), { recursive: true, force: true });
      }
    }
  });

  it("uses host timeoutMs for live extraction", async () => {
    const request: HostRequestMessage = {
      id: "req-cli-5",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-cli-5",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 25,
        includeSelectionText: false,
      },
    };

    const fixtureOutputPath = join(
      tmpdir(),
      `context-grabber-chrome-cli-timeout-${Date.now()}.json`,
    );
    let fakeOsaBinary: string | undefined;
    try {
      await writeFile(
        fixtureOutputPath,
        JSON.stringify({
          url: "https://example.com/live-timeout",
          title: "Live Timeout",
          fullText: "This should not be returned due to timeout.",
          headings: [],
          links: [],
        }),
        "utf8",
      );
      fakeOsaBinary = await createSlowFakeOsaScriptBinary(fixtureOutputPath);

      const result = runCli([], JSON.stringify(request), {
        CONTEXT_GRABBER_CHROME_SOURCE: "live",
        CONTEXT_GRABBER_CHROME_OSASCRIPT_BIN: fakeOsaBinary,
      });
      expect(result.status).toBe(0);

      const parsed = parseLastJsonLine(result.stdout);
      if (typeof parsed !== "object" || parsed === null) {
        throw new Error("Invalid live-timeout response.");
      }

      expect((parsed as { type?: string }).type).toBe("extension.error");
      expect((parsed as { payload?: { code?: string } }).payload?.code).toBe(
        "ERR_EXTENSION_UNAVAILABLE",
      );
    } finally {
      await rm(fixtureOutputPath, { force: true });
      if (fakeOsaBinary) {
        await rm(dirname(fakeOsaBinary), { recursive: true, force: true });
      }
    }
  });
});
