import { describe, expect, it } from "bun:test";
import { PROTOCOL_VERSION } from "@context-grabber/shared-types";
import {
  createBrowserPayload,
  createCaptureResponseMessage,
  createErrorMessage,
  supportsHostCaptureRequest,
} from "../src/payload.js";

describe("shared payload factories", () => {
  const minimalInput = {
    url: "https://example.com",
    title: "Example",
    fullText: "Captured content",
    headings: [] as Array<{ level: number; text: string }>,
    links: [] as Array<{ text: string; href: string }>,
  };

  it("creates a browser payload with the correct browser tag", () => {
    const chrome = createBrowserPayload(minimalInput, "chrome");
    expect(chrome.browser).toBe("chrome");
    expect(chrome.source).toBe("browser");
    expect(chrome.url).toBe("https://example.com");

    const safari = createBrowserPayload(minimalInput, "safari");
    expect(safari.browser).toBe("safari");
  });

  it("includes optional fields when provided", () => {
    const payload = createBrowserPayload(
      {
        ...minimalInput,
        metaDescription: "desc",
        siteName: "Example Site",
        language: "en",
        author: "Alice",
        publishedTime: "2026-01-01",
        selectionText: "selected",
        extractionWarnings: ["warning"],
      },
      "chrome",
    );

    expect(payload.metaDescription).toBe("desc");
    expect(payload.siteName).toBe("Example Site");
    expect(payload.language).toBe("en");
    expect(payload.author).toBe("Alice");
    expect(payload.publishedTime).toBe("2026-01-01");
    expect(payload.selectionText).toBe("selected");
    expect(payload.extractionWarnings).toEqual(["warning"]);
  });

  it("omits optional fields when undefined", () => {
    const payload = createBrowserPayload(minimalInput, "safari");

    expect(payload.metaDescription).toBeUndefined();
    expect(payload.siteName).toBeUndefined();
    expect(payload.language).toBeUndefined();
    expect(payload.author).toBeUndefined();
    expect(payload.publishedTime).toBeUndefined();
    expect(payload.selectionText).toBeUndefined();
    expect(payload.extractionWarnings).toBeUndefined();
  });

  it("creates capture response messages with protocol version", () => {
    const payload = createBrowserPayload(minimalInput, "chrome");
    const message = createCaptureResponseMessage(payload, "msg-1", "2026-02-15T00:00:00.000Z");

    expect(message.type).toBe("extension.capture.result");
    expect(message.payload.protocolVersion).toBe(PROTOCOL_VERSION);
    expect(message.payload.capture.browser).toBe("chrome");
  });

  it("creates error messages with protocol version", () => {
    const message = createErrorMessage(
      "ERR_TIMEOUT",
      "Timed out.",
      "err-1",
      "2026-02-15T00:00:00.000Z",
    );

    expect(message.type).toBe("extension.error");
    expect(message.payload.code).toBe("ERR_TIMEOUT");
    expect(message.payload.protocolVersion).toBe(PROTOCOL_VERSION);
    expect(message.payload.recoverable).toBe(true);
  });

  it("creates non-recoverable error messages", () => {
    const message = createErrorMessage(
      "ERR_PROTOCOL_VERSION",
      "Version mismatch.",
      "err-2",
      "2026-02-15T00:00:00.000Z",
      false,
    );

    expect(message.payload.recoverable).toBe(false);
  });

  it("validates host capture request shapes", () => {
    expect(
      supportsHostCaptureRequest({
        id: "req-1",
        type: "host.capture.request",
        timestamp: "2026-02-15T00:00:00.000Z",
        payload: {
          protocolVersion: "1",
          requestId: "req-1",
          mode: "manual_menu",
          requestedAt: "2026-02-15T00:00:00.000Z",
          timeoutMs: 1200,
          includeSelectionText: true,
        },
      }),
    ).toBe(true);

    expect(supportsHostCaptureRequest({ type: "invalid" })).toBe(false);
  });
});
