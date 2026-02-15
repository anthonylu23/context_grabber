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
 * Chrome-specific alias for the browser-agnostic {@link ExtractionInput}.
 * Kept for backward compatibility with existing consumers.
 */
export type ChromeExtractionInput = ExtractionInput;

export { supportsHostCaptureRequest };

export const createChromeBrowserPayload = (input: ChromeExtractionInput): BrowserContextPayload => {
  return createBrowserPayload(input, "chrome");
};

export const createChromeCaptureResponseMessage = (
  capture: BrowserContextPayload,
  id: string,
  timestamp: string,
): ExtensionResponseMessage => {
  return createCaptureResponseMessage(capture, id, timestamp);
};

export const createChromeErrorMessage = (
  code: ProtocolErrorCode,
  message: string,
  id: string,
  timestamp: string,
  recoverable = true,
): ErrorMessage => {
  return createErrorMessage(code, message, id, timestamp, recoverable);
};
