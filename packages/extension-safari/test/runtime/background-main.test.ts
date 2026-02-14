import { describe, expect, it } from "bun:test";
import { bootstrapSafariRuntimeBackground } from "../../src/runtime/background-main.js";

describe("safari runtime background bootstrap", () => {
  it("returns false when browser runtime APIs are unavailable", () => {
    const bootstrapped = bootstrapSafariRuntimeBackground({});
    expect(bootstrapped).toBe(false);
  });

  it("registers runtime bridge when browser runtime APIs are available", () => {
    let registered = false;
    const browser = {
      tabs: {
        query: async () => [{ id: 1 }],
        sendMessage: async () => ({
          url: "https://example.com",
          title: "Example",
          fullText: "Text",
          headings: [],
          links: [],
        }),
      },
      runtime: {
        onConnect: {
          addListener() {
            registered = true;
          },
        },
      },
    };

    const bootstrapped = bootstrapSafariRuntimeBackground(browser);
    expect(bootstrapped).toBe(true);
    expect(registered).toBe(true);
  });
});
