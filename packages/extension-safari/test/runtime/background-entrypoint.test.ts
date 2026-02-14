import { describe, expect, it } from "bun:test";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";
import {
  DEFAULT_NATIVE_HOST_PORT_NAME,
  registerSafariBackgroundRuntimeBridge,
} from "../../src/runtime/index.js";

interface TestRuntimePort {
  name?: string;
  onMessage: {
    addListener: (listener: (request: unknown) => void | Promise<void>) => void;
  };
  postMessage: (response: unknown) => void;
}

const createHostRequest = (): HostRequestMessage => {
  return {
    id: "req-runtime-background-1",
    type: "host.capture.request",
    timestamp: "2026-02-14T00:00:00.000Z",
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      requestId: "req-runtime-background-1",
      mode: "manual_menu",
      requestedAt: "2026-02-14T00:00:00.000Z",
      timeoutMs: 1200,
      includeSelectionText: true,
    },
  };
};

describe("safari runtime background entrypoint", () => {
  it("registers native host port handling and forwards tab capture requests", async () => {
    let onConnectListener: ((port: TestRuntimePort) => void) | undefined;
    let forwardedMessage: unknown;
    const responses: unknown[] = [];

    const browser = {
      runtime: {
        onConnect: {
          addListener(listener: (port: TestRuntimePort) => void) {
            onConnectListener = listener;
          },
        },
      },
      tabs: {
        async query() {
          return [{ id: 17 }];
        },
        async sendMessage(_tabId: number, message: unknown) {
          forwardedMessage = message;
          return {
            url: "https://example.com",
            title: "Example",
            fullText: "Captured text.",
            headings: [],
            links: [],
          };
        },
      },
    };

    registerSafariBackgroundRuntimeBridge(browser, {
      now: () => "2026-02-14T00:00:00.000Z",
    });

    if (!onConnectListener) {
      throw new Error("onConnect listener was not registered.");
    }

    let requestListener: ((request: unknown) => void | Promise<void>) | undefined;
    onConnectListener({
      name: DEFAULT_NATIVE_HOST_PORT_NAME,
      onMessage: {
        addListener(listener) {
          requestListener = listener;
        },
      },
      postMessage(response) {
        responses.push(response);
      },
    });

    if (!requestListener) {
      throw new Error("Runtime port request listener was not registered.");
    }

    await requestListener(createHostRequest());
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(
      (forwardedMessage as { type?: string; includeSelectionText?: boolean } | undefined)?.type,
    ).toBe("context-grabber.capture-active-tab");
    expect(responses.length).toBe(1);
    expect((responses[0] as { type?: string }).type).toBe("extension.capture.result");
  });

  it("ignores non-native-host port names", () => {
    let onConnectListener: ((port: TestRuntimePort) => void) | undefined;
    let registered = false;
    const browser = {
      runtime: {
        onConnect: {
          addListener(listener: (port: TestRuntimePort) => void) {
            onConnectListener = listener;
          },
        },
      },
      tabs: {
        async query() {
          return [{ id: 1 }];
        },
        async sendMessage() {
          registered = true;
          return {};
        },
      },
    };

    registerSafariBackgroundRuntimeBridge(browser);
    if (!onConnectListener) {
      throw new Error("onConnect listener was not registered.");
    }

    onConnectListener({
      name: "other-port",
      onMessage: {
        addListener() {
          registered = true;
        },
      },
      postMessage() {},
    });

    expect(registered).toBe(false);
  });
});
