import { describe, expect, it } from "bun:test";
import { createChromeCaptureMessage } from "../src/index.js";

describe("createChromeCaptureMessage", () => {
  it("builds a browser capture envelope", () => {
    const message = createChromeCaptureMessage(
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

    expect(message.type).toBe("browser.capture");
    expect(message.payload.browser).toBe("chrome");
  });
});
