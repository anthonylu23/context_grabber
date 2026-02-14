import { describe, expect, it } from "bun:test";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";

const packageDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const cliPath = join(packageDir, "src", "native-messaging-cli.ts");
const fixturePath = join(packageDir, "fixtures", "active-tab.json");

const runCli = (args: string[] = [], stdinText = "", extraEnv: Record<string, string> = {}) => {
  return spawnSync("bun", [cliPath, ...args], {
    cwd: packageDir,
    input: stdinText,
    encoding: "utf8",
    env: {
      ...process.env,
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

describe("native messaging cli", () => {
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
      CONTEXT_GRABBER_SAFARI_FIXTURE_PATH: fixturePath,
    });
    expect(result.status).toBe(0);

    const parsed = parseLastJsonLine(result.stdout);
    if (typeof parsed !== "object" || parsed === null) {
      throw new Error("Invalid capture response.");
    }

    expect((parsed as { type?: string }).type).toBe("extension.capture.result");
  });

  it("returns protocol mismatch error for invalid request version", () => {
    const invalidRequest = {
      id: "req-cli-2",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: "2",
        requestId: "req-cli-2",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 1200,
        includeSelectionText: false,
      },
    };

    const result = runCli([], JSON.stringify(invalidRequest), {
      CONTEXT_GRABBER_SAFARI_FIXTURE_PATH: fixturePath,
    });
    expect(result.status).toBe(0);

    const parsed = parseLastJsonLine(result.stdout);
    if (typeof parsed !== "object" || parsed === null) {
      throw new Error("Invalid error response.");
    }

    expect((parsed as { type?: string }).type).toBe("extension.error");
    expect((parsed as { payload?: { code?: string } }).payload?.code).toBe("ERR_PROTOCOL_VERSION");
  });
});
