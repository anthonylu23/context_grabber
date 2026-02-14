import { describe, expect, it } from "bun:test";
import { createSafariCaptureMessage } from "../src/index.js";

describe("createSafariCaptureMessage", () => {
  it("builds a browser capture envelope", () => {
    const message = createSafariCaptureMessage(
      {
        source: "browser",
        browser: "safari",
        url: "https://example.com",
        title: "Example",
        fullText: "Captured content",
        headings: [],
        links: [],
      },
      "msg-2",
      "2026-02-14T00:00:00.000Z",
    );

    expect(message.type).toBe("browser.capture");
    expect(message.payload.browser).toBe("safari");
  });
});
