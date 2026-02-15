import {
  type ExtractionInput,
  createBrowserPayload,
  createCaptureResponseMessage,
  createErrorMessage,
  supportsHostCaptureRequest,
} from "@context-grabber/extension-shared";
import type {
  BrowserContextPayload,
  ErrorMessage,
  ExtensionResponseMessage,
  ProtocolErrorCode,
} from "@context-grabber/shared-types";

/**
 * Safari-specific alias for the browser-agnostic {@link ExtractionInput}.
 * Kept for backward compatibility with existing consumers.
 */
export type SafariExtractionInput = ExtractionInput;

export { supportsHostCaptureRequest };

export const createSafariBrowserPayload = (input: SafariExtractionInput): BrowserContextPayload => {
  return createBrowserPayload(input, "safari");
};

export const createSafariCaptureResponseMessage = (
  capture: BrowserContextPayload,
  id: string,
  timestamp: string,
): ExtensionResponseMessage => {
  return createCaptureResponseMessage(capture, id, timestamp);
};

export const createSafariErrorMessage = (
  code: ProtocolErrorCode,
  message: string,
  id: string,
  timestamp: string,
  recoverable = true,
): ErrorMessage => {
  return createErrorMessage(code, message, id, timestamp, recoverable);
};
