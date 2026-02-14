import { describe, expect, it } from "bun:test";
import { type HostRequestMessage, PROTOCOL_VERSION } from "@context-grabber/shared-types";
import { handleBackgroundCaptureRequest } from "../../src/runtime/background.js";

describe("safari runtime background handler", () => {
  it("passes includeSelectionText from host request to capture dependency", async () => {
    let includeSelectionTextValue: boolean | undefined;

    const request: HostRequestMessage = {
      id: "req-bg-1",
      type: "host.capture.request",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: {
        protocolVersion: PROTOCOL_VERSION,
        requestId: "req-bg-1",
        mode: "manual_menu",
        requestedAt: "2026-02-14T00:00:00.000Z",
        timeoutMs: 1200,
        includeSelectionText: true,
      },
    };

    const response = await handleBackgroundCaptureRequest(request, {
      captureActiveTab: async (options) => {
        includeSelectionTextValue = options.includeSelectionText;
        const capture: {
          url: string;
          title: string;
          fullText: string;
          headings: Array<{ level: number; text: string }>;
          links: Array<{ text: string; href: string }>;
          selectionText?: string;
        } = {
          url: "https://example.com",
          title: "Example",
          fullText: "Example content",
          headings: [],
          links: [],
        };

        if (options.includeSelectionText) {
          capture.selectionText = "Selected text";
        }

        return capture;
      },
      now: () => "2026-02-14T00:00:00.000Z",
    });

    expect(includeSelectionTextValue).toBe(true);
    expect(response.type).toBe("extension.capture.result");
  });
});
