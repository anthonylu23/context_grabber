import { describe, expect, it } from "bun:test";
import {
  type BrowserContextPayload,
  createNativeMessageEnvelope,
  isBrowserContextPayload,
  isCaptureNativeMessage,
  isDesktopContextPayload,
  isNativeMessageEnvelope,
} from "../src/index.js";

describe("native message contracts", () => {
  it("accepts a valid envelope", () => {
    const payload: BrowserContextPayload = {
      source: "browser",
      browser: "chrome",
      url: "https://example.com",
      title: "Example",
      fullText: "Captured text",
      headings: [{ level: 1, text: "Heading" }],
      links: [{ text: "Home", href: "https://example.com" }],
    };

    const envelope = createNativeMessageEnvelope({
      id: "msg-1",
      type: "browser.capture",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload,
    });

    expect(isNativeMessageEnvelope(envelope)).toBe(true);
  });

  it("rejects malformed envelopes", () => {
    expect(isNativeMessageEnvelope({})).toBe(false);
    expect(isNativeMessageEnvelope({ id: "1", type: "x", timestamp: 1, payload: {} })).toBe(false);
  });

  it("validates browser payload structure", () => {
    expect(
      isBrowserContextPayload({
        source: "browser",
        browser: "chrome",
        url: "https://example.com",
        title: "Example",
        fullText: "Captured text",
        headings: [{ level: 1, text: "Heading" }],
        links: [{ text: "Home", href: "https://example.com" }],
      }),
    ).toBe(true);

    expect(
      isBrowserContextPayload({
        source: "browser",
        browser: "chrome",
        url: "https://example.com",
        title: "Example",
        fullText: "Captured text",
        headings: [{ level: 9, text: "Bad heading" }],
        links: [],
      }),
    ).toBe(false);
  });

  it("validates desktop payload structure", () => {
    expect(
      isDesktopContextPayload({
        source: "desktop",
        appBundleId: "com.example.app",
        appName: "Example App",
        usedOcr: false,
      }),
    ).toBe(true);

    expect(
      isDesktopContextPayload({
        source: "desktop",
        appBundleId: "com.example.app",
        appName: "Example App",
        usedOcr: true,
        ocrConfidence: 2,
      }),
    ).toBe(false);
  });

  it("validates supported capture message envelope types and payloads", () => {
    expect(
      isCaptureNativeMessage({
        id: "msg-2",
        type: "browser.capture",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {
          source: "browser",
          browser: "chrome",
          url: "https://example.com",
          title: "Example",
          fullText: "Captured text",
          headings: [],
          links: [],
        },
      }),
    ).toBe(true);

    expect(
      isCaptureNativeMessage({
        id: "msg-3",
        type: "unknown.message",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {},
      }),
    ).toBe(false);
  });
});
