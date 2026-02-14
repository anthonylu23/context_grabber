import {
  type BrowserContextPayload,
  type ErrorMessage,
  type ExtensionResponseMessage,
  type HostRequestMessage,
  PROTOCOL_VERSION,
  type ProtocolErrorCode,
  createNativeMessageEnvelope,
  isHostRequestMessage,
} from "@context-grabber/shared-types";

export interface ChromeExtractionInput {
  url: string;
  title: string;
  fullText: string;
  headings?: Array<{ level: number; text: string }>;
  links?: Array<{ text: string; href: string }>;
  metaDescription?: string;
  siteName?: string;
  language?: string;
  author?: string;
  publishedTime?: string;
  selectionText?: string;
  extractionWarnings?: string[];
}

export const supportsHostCaptureRequest = (value: unknown): value is HostRequestMessage => {
  return isHostRequestMessage(value);
};

export const createChromeBrowserPayload = (input: ChromeExtractionInput): BrowserContextPayload => {
  const payload: BrowserContextPayload = {
    source: "browser",
    browser: "chrome",
    url: input.url,
    title: input.title,
    fullText: input.fullText,
    headings: input.headings ?? [],
    links: input.links ?? [],
  };

  if (input.metaDescription !== undefined) {
    payload.metaDescription = input.metaDescription;
  }
  if (input.siteName !== undefined) {
    payload.siteName = input.siteName;
  }
  if (input.language !== undefined) {
    payload.language = input.language;
  }
  if (input.author !== undefined) {
    payload.author = input.author;
  }
  if (input.publishedTime !== undefined) {
    payload.publishedTime = input.publishedTime;
  }
  if (input.selectionText !== undefined) {
    payload.selectionText = input.selectionText;
  }
  if (input.extractionWarnings !== undefined) {
    payload.extractionWarnings = input.extractionWarnings;
  }

  return payload;
};

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

export const createChromeErrorMessage = (
  code: ProtocolErrorCode,
  message: string,
  id: string,
  timestamp: string,
  recoverable = true,
): ErrorMessage => {
  return createNativeMessageEnvelope({
    id,
    type: "extension.error",
    timestamp,
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      code,
      message,
      recoverable,
    },
  });
};
