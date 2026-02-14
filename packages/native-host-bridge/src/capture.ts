import {
  type BrowserContextPayload,
  type CaptureMode,
  type ErrorMessage,
  type ExtensionMessage,
  type ExtensionResponseMessage,
  type ExtractionMethod,
  type HostRequestMessage,
  type NormalizedContext,
  PROTOCOL_VERSION,
  type ProtocolErrorCode,
  createNativeMessageEnvelope,
  isErrorMessage,
  isExtensionMessage,
  validateExtensionResponseMessage,
} from "@context-grabber/shared-types";
import { normalizeBrowserContext, renderNormalizedContextMarkdown } from "./markdown.js";

const DEFAULT_TIMEOUT_MS = 1_200;

export interface BrowserCaptureMetadata {
  browser: "chrome" | "safari";
  url?: string;
  title?: string;
  siteName?: string;
}

export interface BrowserCaptureRequestOptions {
  requestId: string;
  mode: CaptureMode;
  metadata: BrowserCaptureMetadata;
  send: (request: HostRequestMessage) => Promise<unknown>;
  timeoutMs?: number;
  includeSelectionText?: boolean;
  now?: () => string;
}

export interface BrowserCaptureAttempt {
  request: HostRequestMessage;
  response?: ExtensionMessage;
  extractionMethod: ExtractionMethod;
  warnings: string[];
  errorCode?: ProtocolErrorCode;
  payload: BrowserContextPayload;
  normalizedContext: NormalizedContext;
  markdown: string;
}

const isTimeoutError = (value: unknown): boolean => {
  return value instanceof Error && value.message === "ERR_TIMEOUT";
};

const withTimeout = async <T>(promise: Promise<T>, timeoutMs: number): Promise<T> => {
  return new Promise<T>((resolve, reject) => {
    const timeoutHandle = setTimeout(() => {
      reject(new Error("ERR_TIMEOUT"));
    }, timeoutMs);

    promise
      .then((value) => {
        clearTimeout(timeoutHandle);
        resolve(value);
      })
      .catch((error) => {
        clearTimeout(timeoutHandle);
        reject(error);
      });
  });
};

const createMetadataOnlyPayload = (
  metadata: BrowserCaptureMetadata,
  warnings: string[],
): BrowserContextPayload => {
  const payload: BrowserContextPayload = {
    source: "browser",
    browser: metadata.browser,
    url: metadata.url ?? "about:blank",
    title: metadata.title ?? "(untitled)",
    fullText: "",
    headings: [],
    links: [],
    extractionWarnings: warnings,
  };

  if (metadata.siteName !== undefined) {
    payload.siteName = metadata.siteName;
  }

  return payload;
};

const finalizeAttempt = (
  request: HostRequestMessage,
  payload: BrowserContextPayload,
  extractionMethod: ExtractionMethod,
  warnings: string[],
  errorCode?: ProtocolErrorCode,
  response?: ExtensionMessage,
): BrowserCaptureAttempt => {
  const normalizedContext = normalizeBrowserContext(payload, {
    id: request.payload.requestId,
    capturedAt: request.timestamp,
    extractionMethod,
    warnings,
  });

  const markdown = renderNormalizedContextMarkdown(normalizedContext, payload);

  const attempt: BrowserCaptureAttempt = {
    request,
    extractionMethod,
    warnings,
    payload,
    normalizedContext,
    markdown,
  };

  if (response !== undefined) {
    attempt.response = response;
  }
  if (errorCode !== undefined) {
    attempt.errorCode = errorCode;
  }

  return attempt;
};

export const createHostCaptureRequestMessage = (
  requestId: string,
  mode: CaptureMode,
  timeoutMs: number,
  timestamp: string,
  includeSelectionText: boolean,
): HostRequestMessage => {
  return createNativeMessageEnvelope({
    id: requestId,
    type: "host.capture.request",
    timestamp,
    payload: {
      protocolVersion: PROTOCOL_VERSION,
      requestId,
      mode,
      requestedAt: timestamp,
      timeoutMs,
      includeSelectionText,
    },
  });
};

export const requestBrowserCapture = async (
  options: BrowserCaptureRequestOptions,
): Promise<BrowserCaptureAttempt> => {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const includeSelectionText = options.includeSelectionText ?? true;
  const timestamp = options.now ? options.now() : new Date().toISOString();
  const request = createHostCaptureRequestMessage(
    options.requestId,
    options.mode,
    timeoutMs,
    timestamp,
    includeSelectionText,
  );

  const fallback = (warning: string, errorCode: ProtocolErrorCode, response?: ExtensionMessage) => {
    const warnings = [warning];
    const payload = createMetadataOnlyPayload(options.metadata, warnings);
    return finalizeAttempt(request, payload, "metadata_only", warnings, errorCode, response);
  };

  let rawResponse: unknown;
  try {
    rawResponse = await withTimeout(options.send(request), timeoutMs);
  } catch (error) {
    if (isTimeoutError(error)) {
      return fallback("Timed out waiting for extension response.", "ERR_TIMEOUT");
    }

    return fallback("Extension transport is unavailable.", "ERR_EXTENSION_UNAVAILABLE");
  }

  const extensionMessage = isExtensionMessage(rawResponse) ? rawResponse : undefined;

  if (extensionMessage && isErrorMessage(extensionMessage)) {
    return fallback(
      extensionMessage.payload.message,
      extensionMessage.payload.code,
      extensionMessage,
    );
  }

  const validation = validateExtensionResponseMessage(rawResponse);
  if (!validation.ok) {
    const primaryIssue = validation.issues[0] ?? {
      code: "ERR_PAYLOAD_INVALID" as const,
      message: "Invalid extension response payload.",
    };
    return fallback(primaryIssue.message, primaryIssue.code, extensionMessage);
  }

  const responseMessage: ExtensionResponseMessage = validation.value;
  const payload = responseMessage.payload.capture;
  const warnings = payload.extractionWarnings ?? [];

  return finalizeAttempt(
    request,
    payload,
    "browser_extension",
    warnings,
    undefined,
    responseMessage,
  );
};

export const isExtensionErrorMessage = (value: unknown): value is ErrorMessage => {
  return isErrorMessage(value);
};
