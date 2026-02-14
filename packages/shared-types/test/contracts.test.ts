import { describe, expect, it } from "bun:test";
import {
  type BrowserContextPayload,
  MAX_BROWSER_FULL_TEXT_CHARS,
  PROTOCOL_VERSION,
  createNativeMessageEnvelope,
  isBrowserContextPayload,
  isCaptureNativeMessage,
  isDesktopContextPayload,
  isErrorMessage,
  isExtensionMessage,
  isExtensionResponseMessage,
  isHostRequestMessage,
  isNativeMessageEnvelope,
  validateBrowserPayloadSize,
  validateExtensionResponseMessage,
} from "../src/index.js";

const createValidBrowserPayload = (): BrowserContextPayload => {
  return {
    source: "browser",
    browser: "chrome",
    url: "https://example.com",
    title: "Example",
    fullText: "Captured text",
    headings: [{ level: 1, text: "Heading" }],
    links: [{ text: "Home", href: "https://example.com" }],
  };
};

describe("native message contracts", () => {
  it("accepts a valid envelope", () => {
    const envelope = createNativeMessageEnvelope({
      id: "msg-1",
      type: "browser.capture",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: createValidBrowserPayload(),
    });

    expect(isNativeMessageEnvelope(envelope)).toBe(true);
  });

  it("rejects malformed envelopes", () => {
    expect(isNativeMessageEnvelope({})).toBe(false);
    expect(isNativeMessageEnvelope({ id: "1", type: "x", timestamp: 1, payload: {} })).toBe(false);
  });

  it("validates browser payload structure", () => {
    expect(isBrowserContextPayload(createValidBrowserPayload())).toBe(true);

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

  it("validates host request messages", () => {
    expect(
      isHostRequestMessage({
        id: "req-1",
        type: "host.capture.request",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {
          protocolVersion: PROTOCOL_VERSION,
          requestId: "req-1",
          mode: "manual_menu",
          requestedAt: "2026-02-14T00:00:00.000Z",
          timeoutMs: 1200,
          includeSelectionText: true,
        },
      }),
    ).toBe(true);

    expect(
      isHostRequestMessage({
        id: "req-2",
        type: "host.capture.request",
        timestamp: "2026-02-14T00:00:00.000Z",
        payload: {
          protocolVersion: "2",
          requestId: "req-2",
          mode: "manual_menu",
          requestedAt: "2026-02-14T00:00:00.000Z",
          timeoutMs: 1200,
          includeSelectionText: true,
        },
      }),
    ).toBe(false);
  });

  it("validates extension response and error messages", () => {
    const responseMessage = {
      id: "res-1",
      type: "extension.capture.result",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        capture: createValidBrowserPayload(),
      },
    };

    const errorMessage = {
      id: "err-1",
      type: "extension.error",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        code: "ERR_TIMEOUT",
        message: "Timed out waiting for extension response.",
        recoverable: true,
      },
    };

    expect(isExtensionResponseMessage(responseMessage)).toBe(true);
    expect(isErrorMessage(errorMessage)).toBe(true);
    expect(isExtensionMessage(responseMessage)).toBe(true);
    expect(isExtensionMessage(errorMessage)).toBe(true);
  });

  it("rejects oversized browser payloads", () => {
    const oversizedPayload: BrowserContextPayload = {
      ...createValidBrowserPayload(),
      fullText: "x".repeat(MAX_BROWSER_FULL_TEXT_CHARS + 1),
    };

    const result = validateBrowserPayloadSize(oversizedPayload);
    expect(result.ok).toBe(false);
  });

  it("validates extension response with protocol and size checks", () => {
    const result = validateExtensionResponseMessage({
      id: "res-2",
      type: "extension.capture.result",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        capture: createValidBrowserPayload(),
      },
    });

    expect(result.ok).toBe(true);
  });
});
