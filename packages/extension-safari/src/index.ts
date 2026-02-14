import type { BrowserContextPayload, NativeMessageEnvelope } from "@context-grabber/shared-types";

export type SafariCaptureMessage = NativeMessageEnvelope<"browser.capture", BrowserContextPayload>;

export const createSafariCaptureMessage = (
  payload: BrowserContextPayload,
  id: string,
  timestamp: string,
): SafariCaptureMessage => {
  return {
    id,
    type: "browser.capture",
    timestamp,
    payload,
  };
};
