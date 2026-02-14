import { describe, expect, it } from "bun:test";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";
import { bindRuntimeNativeHostPort } from "../../src/runtime/native-host.js";

interface TestPort {
  onMessage: {
    addListener: (listener: (request: unknown) => void | Promise<void>) => void;
  };
  postMessage: (response: unknown) => void;
}

const createHostRequest = (): HostRequestMessage => {
  return {
    id: "req-runtime-host-1",
    type: "host.capture.request",
    timestamp: "2026-02-14T00:00:00.000Z",
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      requestId: "req-runtime-host-1",
      mode: "manual_menu",
      requestedAt: "2026-02-14T00:00:00.000Z",
      timeoutMs: 1200,
      includeSelectionText: true,
    },
  };
};

const setupPort = (): {
  port: TestPort;
  trigger: (request: unknown) => Promise<void>;
  responses: unknown[];
} => {
  let listener: ((request: unknown) => void | Promise<void>) | undefined;
  const responses: unknown[] = [];

  const port: TestPort = {
    onMessage: {
      addListener(next) {
        listener = next;
      },
    },
    postMessage(response) {
      responses.push(response);
    },
  };

  return {
    port,
    responses,
    async trigger(request: unknown) {
      if (!listener) {
        throw new Error("Listener was not registered.");
      }

      await listener(request);
      await new Promise((resolve) => setTimeout(resolve, 0));
    },
  };
};

describe("runtime native host bridge", () => {
  it("posts capture result for valid host request", async () => {
    const { port, trigger, responses } = setupPort();
    bindRuntimeNativeHostPort(port, {
      now: () => "2026-02-14T00:00:00.000Z",
      async captureActiveTab() {
        return {
          url: "https://example.com",
          title: "Example",
          fullText: "Body text.",
          headings: [],
          links: [],
        };
      },
    });

    await trigger(createHostRequest());

    expect(responses.length).toBe(1);
    const response = responses[0] as { type?: string };
    expect(response.type).toBe("extension.capture.result");
  });

  it("posts recoverable transport error when active-tab capture throws", async () => {
    const { port, trigger, responses } = setupPort();
    bindRuntimeNativeHostPort(port, {
      now: () => "2026-02-14T00:00:00.000Z",
      async captureActiveTab() {
        throw new Error("tab unavailable");
      },
    });

    await trigger(createHostRequest());

    expect(responses.length).toBe(1);
    const response = responses[0] as {
      type?: string;
      payload?: { code?: string; recoverable?: boolean };
    };
    expect(response.type).toBe("extension.error");
    expect(response.payload?.code).toBe("ERR_EXTENSION_UNAVAILABLE");
    expect(response.payload?.recoverable).toBe(true);
  });

  it("posts fatal bridge error when unexpected runtime failure escapes request handling", async () => {
    const { port, trigger, responses } = setupPort();
    bindRuntimeNativeHostPort(port, {
      now: () => {
        throw new Error("clock unavailable");
      },
      async captureActiveTab() {
        return {
          url: "https://example.com",
          title: "Example",
          fullText: "Body text.",
          headings: [],
          links: [],
        };
      },
    });

    await trigger(createHostRequest());

    expect(responses.length).toBe(1);
    const response = responses[0] as {
      type?: string;
      payload?: { code?: string; message?: string };
    };
    expect(response.type).toBe("extension.error");
    expect(response.payload?.code).toBe("ERR_EXTENSION_UNAVAILABLE");
    expect(response.payload?.message?.includes("Runtime bridge failed unexpectedly")).toBe(true);
  });
});
