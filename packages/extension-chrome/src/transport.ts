import {
  type ExtractionInput,
  type HostRequestHandlingOptions,
  handleHostCaptureRequest as sharedHandleHostCaptureRequest,
} from "@context-grabber/extension-shared";
import type { ExtensionMessage, HostRequestMessage } from "@context-grabber/shared-types";

export type { HostRequestHandlingOptions };

export const handleHostCaptureRequest = async (
  request: unknown,
  loadActiveTabCapture: (request: HostRequestMessage) => Promise<ExtractionInput>,
  options: HostRequestHandlingOptions = {},
): Promise<ExtensionMessage> => {
  return sharedHandleHostCaptureRequest(request, loadActiveTabCapture, "chrome", options);
};
