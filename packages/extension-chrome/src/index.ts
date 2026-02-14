import type { BrowserContextPayload, NativeMessageEnvelope } from "@context-grabber/shared-types";

export type ChromeCaptureMessage = NativeMessageEnvelope<"browser.capture", BrowserContextPayload>;

export const createChromeCaptureMessage = (
  payload: BrowserContextPayload,
  id: string,
  timestamp: string,
): ChromeCaptureMessage => {
  return {
    id,
    type: "browser.capture",
    timestamp,
    payload,
  };
};
