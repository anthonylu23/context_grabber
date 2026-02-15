import { describe, expect, it } from "bun:test";
import { PROTOCOL_VERSION } from "@context-grabber/shared-types";
import type { ExtractionInput } from "../src/payload.js";
import { handleHostCaptureRequest } from "../src/transport.js";

describe("shared transport handler", () => {
  const buildRequest = () => ({
    id: "req-1",
    type: "host.capture.request" as const,
    timestamp: "2026-02-15T00:00:00.000Z",
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      requestId: "req-1",
      mode: "manual_menu" as const,
      requestedAt: "2026-02-15T00:00:00.000Z",
      timeoutMs: 1200,
      includeSelectionText: true,
    },
  });

  const stubExtraction: ExtractionInput = {
    url: "https://example.com",
    title: "Example",
    fullText: "Captured text",
    headings: [],
    links: [],
  };

  it("returns capture result for valid chrome requests", async () => {
    const response = await handleHostCaptureRequest(
      buildRequest(),
      async () => stubExtraction,
      "chrome",
      { now: () => "2026-02-15T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.capture.result");
    if (response.type === "extension.capture.result") {
      expect(response.payload.capture.browser).toBe("chrome");
      expect(response.payload.protocolVersion).toBe(PROTOCOL_VERSION);
    }
  });

  it("returns capture result for valid safari requests", async () => {
    const response = await handleHostCaptureRequest(
      buildRequest(),
      async () => stubExtraction,
      "safari",
      { now: () => "2026-02-15T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.capture.result");
    if (response.type === "extension.capture.result") {
      expect(response.payload.capture.browser).toBe("safari");
    }
  });

  it("returns ERR_PROTOCOL_VERSION for mismatched protocol", async () => {
    const response = await handleHostCaptureRequest(
      {
        ...buildRequest(),
        payload: { ...buildRequest().payload, protocolVersion: "99" },
      },
      async () => stubExtraction,
      "chrome",
      { now: () => "2026-02-15T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.error");
    if (response.type === "extension.error") {
      expect(response.payload.code).toBe("ERR_PROTOCOL_VERSION");
    }
  });

  it("returns ERR_PAYLOAD_INVALID for garbage input", async () => {
    const response = await handleHostCaptureRequest(
      { id: "bad", type: "wrong" },
      async () => stubExtraction,
      "safari",
      { now: () => "2026-02-15T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.error");
    if (response.type === "extension.error") {
      expect(response.payload.code).toBe("ERR_PAYLOAD_INVALID");
    }
  });

  it("returns ERR_EXTENSION_UNAVAILABLE when extraction throws", async () => {
    const response = await handleHostCaptureRequest(
      buildRequest(),
      async () => {
        throw new Error("tab unavailable");
      },
      "chrome",
      { now: () => "2026-02-15T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.error");
    if (response.type === "extension.error") {
      expect(response.payload.code).toBe("ERR_EXTENSION_UNAVAILABLE");
      expect(response.payload.message).toContain("tab unavailable");
    }
  });

  it("returns ERR_PAYLOAD_TOO_LARGE for oversized fullText", async () => {
    const response = await handleHostCaptureRequest(
      buildRequest(),
      async () => ({ ...stubExtraction, fullText: "x".repeat(220_000) }),
      "safari",
      { now: () => "2026-02-15T00:00:00.000Z" },
    );

    expect(response.type).toBe("extension.error");
    if (response.type === "extension.error") {
      expect(response.payload.code).toBe("ERR_PAYLOAD_TOO_LARGE");
    }
  });
});
