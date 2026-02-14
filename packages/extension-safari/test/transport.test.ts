import { describe, expect, it } from "bun:test";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";
import { handleHostCaptureRequest } from "../src/transport.js";

describe("safari host request transport", () => {
  const buildRequest = (): HostRequestMessage => {
    return {
      id: "req-transport-1",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-transport-1",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 1200,
        includeSelectionText: true,
      },
    };
  };

  it("returns extension.capture.result for valid requests", async () => {
    const response = await handleHostCaptureRequest(
      buildRequest(),
      async () => ({
        url: "https://example.com",
        title: "Example",
        fullText: "Captured text",
        headings: [],
        links: [],
      }),
      { now: () => "2026-02-14T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.capture.result");
    if (response.type === "extension.capture.result") {
      expect(response.payload.protocolVersion).toBe("1");
      expect(response.payload.capture.browser).toBe("safari");
    }
  });

  it("returns ERR_PROTOCOL_VERSION when host request has mismatched protocol", async () => {
    const response = await handleHostCaptureRequest(
      {
        id: "req-transport-2",
        type: "host.capture.request",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {
          protocolVersion: "2",
          requestId: "req-transport-2",
          mode: "manual_menu",
          requestedAt: "2026-02-14T00:00:00.000Z",
          timeoutMs: 1200,
          includeSelectionText: true,
        },
      },
      async () => ({
        url: "https://example.com",
        title: "Example",
        fullText: "Captured text",
        headings: [],
        links: [],
      }),
      { now: () => "2026-02-14T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.error");
    if (response.type === "extension.error") {
      expect(response.payload.code).toBe("ERR_PROTOCOL_VERSION");
    }
  });

  it("returns ERR_PAYLOAD_TOO_LARGE for oversized fullText", async () => {
    const response = await handleHostCaptureRequest(
      buildRequest(),
      async () => ({
        url: "https://example.com",
        title: "Example",
        fullText: "x".repeat(220_000),
        headings: [],
        links: [],
      }),
      { now: () => "2026-02-14T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.error");
    if (response.type === "extension.error") {
      expect(response.payload.code).toBe("ERR_PAYLOAD_TOO_LARGE");
    }
  });

  it("returns ERR_EXTENSION_UNAVAILABLE when extraction source throws", async () => {
    const response = await handleHostCaptureRequest(
      buildRequest(),
      async () => {
        throw new Error("safari transport unavailable");
      },
      { now: () => "2026-02-14T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.error");
    if (response.type === "extension.error") {
      expect(response.payload.code).toBe("ERR_EXTENSION_UNAVAILABLE");
    }
  });
});
