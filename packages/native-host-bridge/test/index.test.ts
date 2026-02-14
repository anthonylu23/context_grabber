import { describe, expect, it } from "bun:test";
import {
  normalizeBrowserContext,
  parseExtensionResponseMessage,
  parseNativeMessage,
  renderNormalizedContextMarkdown,
  requestBrowserCapture,
} from "../src/index.js";

describe("native host bridge", () => {
  it("returns valid typed extension envelopes", () => {
    const message = parseNativeMessage({
      id: "msg-3",
      type: "extension.capture.result",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: "1",
        capture: {
          source: "browser",
          browser: "chrome",
          url: "https://example.com",
          title: "Example",
          fullText: "Captured content",
          headings: [],
          links: [],
        },
      },
    });

    expect(message.id).toBe("msg-3");
    expect(message.type).toBe("extension.capture.result");
  });

  it("throws on malformed extension responses", () => {
    expect(() =>
      parseExtensionResponseMessage({
        id: "bad-1",
        type: "extension.capture.result",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {
          protocolVersion: "2",
          capture: {},
        },
      }),
    ).toThrow();
  });

  it("falls back to metadata-only capture when response times out", async () => {
    const attempt = await requestBrowserCapture({
      requestId: "req-timeout",
      mode: "manual_menu",
      metadata: {
        browser: "safari",
        url: "https://example.com",
        title: "Example",
      },
      send: async () => {
        return await new Promise((resolve) => {
          setTimeout(() => resolve(undefined), 200);
        });
      },
      timeoutMs: 10,
      now: () => "2026-02-14T00:00:00.000Z",
    });

    expect(attempt.extractionMethod).toBe("metadata_only");
    expect(attempt.errorCode).toBe("ERR_TIMEOUT");
    expect(attempt.payload.title).toBe("Example");
  });

  it("renders deterministic markdown for the same payload", () => {
    const payload = {
      source: "browser" as const,
      browser: "safari" as const,
      url: "https://example.com/docs",
      title: "Docs",
      fullText: "Intro paragraph. Important setup guidance. Important setup guidance.",
      headings: [{ level: 1, text: "Setup" }],
      links: [{ text: "Docs", href: "https://example.com/docs" }],
    };

    const normalizedA = normalizeBrowserContext(payload, {
      id: "ctx-1",
      capturedAt: "2026-02-14T00:00:00.000Z",
      extractionMethod: "browser_extension",
    });
    const normalizedB = normalizeBrowserContext(payload, {
      id: "ctx-1",
      capturedAt: "2026-02-14T00:00:00.000Z",
      extractionMethod: "browser_extension",
    });

    const markdownA = renderNormalizedContextMarkdown(normalizedA, payload);
    const markdownB = renderNormalizedContextMarkdown(normalizedB, payload);

    expect(markdownA).toBe(markdownB);
  });
});
