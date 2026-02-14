import { describe, expect, it } from "bun:test";
import {
  createSafariBrowserPayload,
  createSafariCaptureResponseMessage,
  createSafariErrorMessage,
  supportsHostCaptureRequest,
} from "../src/index.js";

describe("safari extension contracts", () => {
  it("builds protocol-versioned capture responses", () => {
    const payload = createSafariBrowserPayload({
      url: "https://example.com",
      title: "Example",
      fullText: "Captured content",
      headings: [],
      links: [],
    });

    const message = createSafariCaptureResponseMessage(
      payload,
      "msg-2",
      "2026-02-14T00:00:00.000Z",
    );

    expect(message.type).toBe("extension.capture.result");
    expect(message.payload.capture.browser).toBe("safari");
    expect(message.payload.protocolVersion).toBe("1");
  });

  it("builds extension errors", () => {
    const error = createSafariErrorMessage(
      "ERR_TIMEOUT",
      "Timed out waiting for page extraction.",
      "err-1",
      "2026-02-14T00:00:00.000Z",
    );

    expect(error.type).toBe("extension.error");
    expect(error.payload.code).toBe("ERR_TIMEOUT");
  });

  it("validates host capture requests", () => {
    expect(
      supportsHostCaptureRequest({
        id: "req-1",
        type: "host.capture.request",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {
          protocolVersion: "1",
          requestId: "req-1",
          mode: "manual_menu",
          requestedAt: "2026-02-14T00:00:00.000Z",
          timeoutMs: 1200,
          includeSelectionText: true,
        },
      }),
    ).toBe(true);
  });
});
