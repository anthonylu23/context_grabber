import { describe, expect, it } from "bun:test";
import { bootstrapSafariRuntimeContent } from "../../src/runtime/content-main.js";

describe("safari runtime content bootstrap", () => {
  it("returns false when browser runtime APIs are unavailable", () => {
    const bootstrapped = bootstrapSafariRuntimeContent({});
    expect(bootstrapped).toBe(false);
  });

  it("registers runtime listener when APIs are available", () => {
    let registered = false;
    const browser = {
      runtime: {
        onMessage: {
          addListener() {
            registered = true;
          },
        },
      },
    };

    const bootstrapped = bootstrapSafariRuntimeContent(browser);
    expect(bootstrapped).toBe(true);
    expect(registered).toBe(true);
  });
});
