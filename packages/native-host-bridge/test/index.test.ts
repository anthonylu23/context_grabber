import { describe, expect, it } from "bun:test";
import { parseNativeMessage } from "../src/index.js";

describe("parseNativeMessage", () => {
  it("returns valid typed capture envelopes", () => {
    const message = parseNativeMessage({
      id: "msg-3",
      type: "browser.capture",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        source: "browser",
        browser: "chrome",
        url: "https://example.com",
        title: "Example",
        fullText: "Captured content",
        headings: [],
        links: [],
      },
    });

    expect(message.id).toBe("msg-3");
    expect(message.type).toBe("browser.capture");
  });

  it("throws on malformed envelopes", () => {
    expect(() => parseNativeMessage({ type: "missing-fields" })).toThrow();
  });

  it("throws on unsupported message types", () => {
    expect(() =>
      parseNativeMessage({
        id: "msg-4",
        type: "unsupported.type",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {},
      }),
    ).toThrow();
  });
});
