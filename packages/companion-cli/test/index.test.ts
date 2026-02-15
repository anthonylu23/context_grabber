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

    expect(companionUsage().includes("context-grabber doctor")).toBe(true);
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
