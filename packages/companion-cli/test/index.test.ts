import { describe, expect, it } from "bun:test";
import type { SpawnSyncReturns } from "node:child_process";
import {
  type HostRequestMessage,
  PROTOCOL_VERSION,
  createNativeMessageEnvelope,
} from "@context-grabber/shared-types";
import { runCaptureFocused } from "../src/capture-focused.js";
import { companionUsage, parseCompanionCommand } from "../src/commands.js";
import { runDoctor } from "../src/doctor.js";
import { runListApps, runListTabs } from "../src/list.js";
import { type BridgeClient, type BrowserTarget, createBridgeClient } from "../src/native-bridge.js";

const captureResponse = (target: BrowserTarget) => {
  return {
    id: `capture-${target}`,
    type: "extension.capture.result",
    timestamp: "2026-02-15T00:00:00.000Z",
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      capture: {
        source: "browser",
        browser: target,
        url: `https://${target}.example.com`,
        title: `${target} docs`,
        fullText: `${target} captured text`,
        headings: [],
        links: [],
      },
    },
  };
};

describe("companion CLI command parser", () => {
  it("parses help, doctor, and capture focused commands", () => {
    const help = parseCompanionCommand([]);
    const doctor = parseCompanionCommand(["doctor"]);
    const capture = parseCompanionCommand(["capture", "--focused"]);
    const listTabs = parseCompanionCommand(["list", "tabs"]);
    const listTabsFiltered = parseCompanionCommand(["list", "tabs", "--browser", "chrome"]);
    const listApps = parseCompanionCommand(["list", "apps"]);

    expect(help.ok).toBe(true);
    if (help.ok) {
      expect(help.command.kind).toBe("help");
    }

    expect(doctor.ok).toBe(true);
    if (doctor.ok) {
      expect(doctor.command.kind).toBe("doctor");
    }

    expect(capture.ok).toBe(true);
    if (capture.ok) {
      expect(capture.command.kind).toBe("capture-focused");
    }

    expect(listTabs.ok).toBe(true);
    if (listTabs.ok) {
      expect(listTabs.command.kind).toBe("list-tabs");
    }

    expect(listTabsFiltered.ok).toBe(true);
    if (listTabsFiltered.ok && listTabsFiltered.command.kind === "list-tabs") {
      expect(listTabsFiltered.command.browser).toBe("chrome");
    }

    expect(listApps.ok).toBe(true);
    if (listApps.ok) {
      expect(listApps.command.kind).toBe("list-apps");
    }
  });

  it("returns parse errors for unsupported command shapes", () => {
    const invalidCapture = parseCompanionCommand(["capture"]);
    expect(invalidCapture.ok).toBe(false);
    if (!invalidCapture.ok) {
      expect(invalidCapture.error.includes("capture currently supports only")).toBe(true);
    }

    const unknown = parseCompanionCommand(["wat"]);
    expect(unknown.ok).toBe(false);
    if (!unknown.ok) {
      expect(unknown.error.includes("Unknown command")).toBe(true);
    }

    const invalidList = parseCompanionCommand(["list", "tabs", "--browser", "firefox"]);
    expect(invalidList.ok).toBe(false);
    if (!invalidList.ok) {
      expect(invalidList.error.includes("list tabs supports optional")).toBe(true);
    }

    expect(companionUsage().includes("context-grabber doctor")).toBe(true);
    expect(companionUsage().includes("context-grabber list tabs")).toBe(true);
  });
});

describe("doctor", () => {
  it("reports ready when at least one browser bridge is healthy", async () => {
    const bridge: BridgeClient = {
      async ping(target) {
        if (target === "safari") {
          return { state: "ready", label: "ready/protocol 1" };
        }
        return { state: "unreachable", label: "unreachable" };
      },
      async sendCaptureRequest() {
        throw new Error("unused");
      },
    };

    const result = await runDoctor(bridge);
    expect(result.exitCode).toBe(0);
    expect(result.output.includes("safari: ready/protocol 1")).toBe(true);
    expect(result.output.includes("overall: ready")).toBe(true);
  });

  it("returns non-zero when both bridges are unreachable", async () => {
    const bridge: BridgeClient = {
      async ping() {
        return { state: "unreachable", label: "unreachable" };
      },
      async sendCaptureRequest() {
        throw new Error("unused");
      },
    };

    const result = await runDoctor(bridge);
    expect(result.exitCode).toBe(1);
    expect(result.output.includes("overall: unreachable")).toBe(true);
  });
});

describe("capture --focused", () => {
  it("respects explicit browser target override", async () => {
    const requestedTargets: BrowserTarget[] = [];
    const bridge: BridgeClient = {
      async ping() {
        return { state: "unreachable", label: "unreachable" };
      },
      async sendCaptureRequest(target: BrowserTarget, _request: HostRequestMessage) {
        requestedTargets.push(target);
        return captureResponse(target);
      },
    };

    const result = await runCaptureFocused({
      bridge,
      env: { CONTEXT_GRABBER_BROWSER_TARGET: "chrome" },
      now: () => "2026-02-15T00:00:00.000Z",
      randomUUID: () => "req-cli-override",
    });

    expect(result.exitCode).toBe(0);
    expect(requestedTargets.join(",")).toBe("chrome");
    expect(result.stdout.includes('source_type: "webpage"')).toBe(true);
  });

  it("falls back from safari to chrome in auto mode", async () => {
    const requestedTargets: BrowserTarget[] = [];
    const bridge: BridgeClient = {
      async ping() {
        return { state: "unreachable", label: "unreachable" };
      },
      async sendCaptureRequest(target: BrowserTarget) {
        requestedTargets.push(target);
        if (target === "safari") {
          throw new Error("safari unavailable");
        }
        return captureResponse(target);
      },
    };

    const result = await runCaptureFocused({
      bridge,
      env: {},
      now: () => "2026-02-15T00:00:00.000Z",
      randomUUID: () => "req-cli-fallback",
    });

    expect(result.exitCode).toBe(0);
    expect(requestedTargets.join(",")).toBe("safari,chrome");
    expect(result.stdout.includes("chrome docs")).toBe(true);
  });

  it("returns non-zero when both bridges are unavailable", async () => {
    const bridge: BridgeClient = {
      async ping() {
        return { state: "unreachable", label: "unreachable" };
      },
      async sendCaptureRequest() {
        throw new Error("bridge unavailable");
      },
    };

    const result = await runCaptureFocused({
      bridge,
      env: {},
      now: () => "2026-02-15T00:00:00.000Z",
      randomUUID: () => "req-cli-fail",
    });

    expect(result.exitCode).toBe(1);
    expect(result.stderr.includes("Neither Safari nor Chrome bridge is currently reachable.")).toBe(
      true,
    );
  });
});

describe("native bridge", () => {
  it("maps native bridge spawn timeouts to ERR_TIMEOUT", async () => {
    const timeoutSpawnResult: SpawnSyncReturns<string> = {
      output: [null, "", ""],
      pid: 123,
      signal: "SIGTERM",
      status: null,
      stdout: "",
      stderr: "",
      error: Object.assign(new Error("spawnSync ETIMEDOUT"), { code: "ETIMEDOUT" }),
    };

    const bridge = createBridgeClient({
      cwd: process.cwd(),
      spawnSyncImpl: () => timeoutSpawnResult,
    });

    const request = createNativeMessageEnvelope({
      id: "req-timeout",
      type: "host.capture.request",
      timestamp: "2026-02-15T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-timeout",
        mode: "manual_menu",
        requestedAt: "2026-02-15T00:00:00.000Z",
        timeoutMs: 1_200,
        includeSelectionText: true,
      },
    }) as HostRequestMessage;

    let thrown: unknown;
    try {
      await bridge.sendCaptureRequest("safari", request);
    } catch (error) {
      thrown = error;
    }

    if (!(thrown instanceof Error)) {
      throw new Error("Expected sendCaptureRequest to throw an Error.");
    }
    expect(thrown.message).toBe("ERR_TIMEOUT");
  });
});

describe("list inventory", () => {
  const field = String.fromCharCode(30);
  const line = String.fromCharCode(31);

  const spawnOk = (stdout: string): SpawnSyncReturns<string> => {
    return {
      output: [null, stdout, ""],
      pid: 123,
      signal: null,
      status: 0,
      stdout,
      stderr: "",
    };
  };

  const spawnErr = (stderr: string): SpawnSyncReturns<string> => {
    return {
      output: [null, "", stderr],
      pid: 123,
      signal: null,
      status: 1,
      stdout: "",
      stderr,
    };
  };

  it("lists tabs from both browsers", async () => {
    const result = await runListTabs({
      env: {},
      spawnSyncImpl: (_command, _args, options) => {
        const script = String(options.input ?? "");
        if (script.includes('tell application "Safari"')) {
          return spawnOk(`1${field}1${field}true${field}Safari Tab${field}https://apple.com`);
        }
        if (script.includes('tell application "Google Chrome"')) {
          return spawnOk(`1${field}2${field}false${field}Chrome Tab${field}https://google.com`);
        }
        return spawnErr("unexpected script");
      },
    });

    expect(result.exitCode).toBe(0);
    expect(result.stderr.length).toBe(0);
    expect(result.stdout.includes('"browser": "chrome"')).toBe(true);
    expect(result.stdout.includes('"browser": "safari"')).toBe(true);
  });

  it("returns success when one browser fails but the other succeeds", async () => {
    const result = await runListTabs({
      env: {},
      spawnSyncImpl: (_command, _args, options) => {
        const script = String(options.input ?? "");
        if (script.includes('tell application "Safari"')) {
          return spawnErr("Safari not authorized");
        }
        return spawnOk(`1${field}1${field}true${field}Chrome Tab${field}https://example.com`);
      },
    });

    expect(result.exitCode).toBe(0);
    expect(result.stderr.includes("safari: Safari not authorized")).toBe(true);
    expect(result.stdout.includes('"browser": "chrome"')).toBe(true);
  });

  it("returns non-zero when all selected browsers fail", async () => {
    const result = await runListTabs({
      env: {},
      spawnSyncImpl: () => spawnErr("not allowed"),
    });

    expect(result.exitCode).toBe(1);
    expect(result.stderr.includes("safari: not allowed")).toBe(true);
    expect(result.stderr.includes("chrome: not allowed")).toBe(true);
  });

  it("lists desktop apps with windows", async () => {
    const appLines = [
      `Finder${field}com.apple.finder${field}2`,
      `Safari${field}com.apple.Safari${field}4`,
    ].join(line);

    const result = await runListApps({
      spawnSyncImpl: () => spawnOk(appLines),
    });

    expect(result.exitCode).toBe(0);
    expect(result.stdout.includes('"appName": "Finder"')).toBe(true);
    expect(result.stdout.includes('"windowCount": 4')).toBe(true);
  });

  it("returns non-zero when app listing fails", async () => {
    const result = await runListApps({
      spawnSyncImpl: () => spawnErr("System Events denied"),
    });

    expect(result.exitCode).toBe(1);
    expect(result.stderr.includes("list apps failed: System Events denied")).toBe(true);
  });
});
