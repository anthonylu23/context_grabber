import {
  type BrowserContextPayload,
  type ExtensionResponseMessage,
  PROTOCOL_VERSION,
  createNativeMessageEnvelope,
} from "@context-grabber/shared-types";

export const createChromeCaptureResponseMessage = (
  capture: BrowserContextPayload,
  id: string,
  timestamp: string,
): ExtensionResponseMessage => {
  return createNativeMessageEnvelope({
    id,
    type: "extension.capture.result",
    timestamp,
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      capture,
    },
  });
};
