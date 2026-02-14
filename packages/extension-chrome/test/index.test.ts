import { describe, expect, it } from "bun:test";
import {
  createChromeBrowserPayload,
  createChromeCaptureResponseMessage,
  createChromeErrorMessage,
  supportsHostCaptureRequest,
} from "../src/index.js";

describe("chrome extension contracts", () => {
  it("builds protocol-versioned browser capture response envelope", () => {
    const payload = createChromeBrowserPayload({
      url: "https://example.com",
      title: "Example",
      fullText: "Captured content",
      headings: [],
      links: [],
    });

    const message = createChromeCaptureResponseMessage(
      payload,
      "msg-1",
      "2026-02-14T00:00:00.000Z",
    );

    expect(message.type).toBe("extension.capture.result");
    expect(message.payload.capture.browser).toBe("chrome");
    expect(message.payload.protocolVersion).toBe("1");
  });

  it("builds extension error envelopes", () => {
    const error = createChromeErrorMessage(
      "ERR_TIMEOUT",
      "Timed out waiting for response.",
      "err-1",
      "2026-02-14T00:00:00.000Z",
    );

    expect(error.type).toBe("extension.error");
    expect(error.payload.code).toBe("ERR_TIMEOUT");
  });

  it("validates host capture request shape", () => {
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
