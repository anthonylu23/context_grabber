import { describe, expect, it } from "bun:test";
import { createChromeCaptureResponseMessage } from "../src/index.js";

describe("createChromeCaptureResponseMessage", () => {
  it("builds a protocol-versioned browser capture response envelope", () => {
    const message = createChromeCaptureResponseMessage(
      {
        source: "browser",
        browser: "chrome",
        url: "https://example.com",
        title: "Example",
        fullText: "Captured content",
        headings: [],
        links: [],
      },
      "msg-1",
      "2026-02-14T00:00:00.000Z",
    );

    expect(message.type).toBe("extension.capture.result");
    expect(message.payload.capture.browser).toBe("chrome");
    expect(message.payload.protocolVersion).toBe("1");
  });
});
