export const PROTOCOL_VERSION = "1" as const;
export type ProtocolVersion = typeof PROTOCOL_VERSION;

export const MAX_BROWSER_FULL_TEXT_CHARS = 200_000;
export const MAX_ENVELOPE_CHARS = 250_000;

export type CaptureMode = "manual_hotkey" | "manual_menu";

export interface CaptureRequest {
  requestId: string;
  timestamp: string;
  mode: CaptureMode;
}

export interface BrowserContextPayload {
  source: "browser";
  browser: "chrome" | "safari";
  url: string;
  title: string;
  metaDescription?: string;
  siteName?: string;
  language?: string;
  author?: string;
  publishedTime?: string;
  selectionText?: string;
  fullText: string;
  headings: Array<{ level: number; text: string }>;
  links: Array<{ text: string; href: string }>;
  extractionWarnings?: string[];
}

export interface DesktopContextPayload {
  source: "desktop";
  appBundleId: string;
  appName: string;
  windowTitle?: string;
  accessibilityText?: string;
  ocrText?: string;
  usedOcr: boolean;
  ocrConfidence?: number;
  extractionWarnings?: string[];
}

export type ExtractionMethod = "browser_extension" | "accessibility" | "ocr" | "metadata_only";

export interface NormalizedContext {
  id: string;
  capturedAt: string;
  sourceType: "webpage" | "desktop_app";
  title: string;
  origin: string;
  appOrSite: string;
  extractionMethod: ExtractionMethod;
  confidence: number;
  truncated: boolean;
  tokenEstimate: number;
  metadata: Record<string, string>;
  captureWarnings: string[];
  summary: string;
  keyPoints: string[];
  chunks: Array<{ chunkId: string; tokenEstimate: number; text: string }>;
  rawExcerpt: string;
}

export interface NativeMessageEnvelope<TType extends string = string, TPayload = unknown> {
  id: string;
  type: TType;
  timestamp: string;
  payload: TPayload;
}

export type BrowserCaptureMessage = NativeMessageEnvelope<"browser.capture", BrowserContextPayload>;
export type DesktopCaptureMessage = NativeMessageEnvelope<"desktop.capture", DesktopContextPayload>;
export type CaptureNativeMessage = BrowserCaptureMessage | DesktopCaptureMessage;

export type ProtocolErrorCode =
  | "ERR_PROTOCOL_VERSION"
  | "ERR_PAYLOAD_INVALID"
  | "ERR_TIMEOUT"
  | "ERR_EXTENSION_UNAVAILABLE"
  | "ERR_PAYLOAD_TOO_LARGE";

export interface HostCaptureRequestPayload {
  protocolVersion: ProtocolVersion;
  requestId: string;
  mode: CaptureMode;
  requestedAt: string;
  timeoutMs: number;
  includeSelectionText: boolean;
}

export type HostRequestMessage = NativeMessageEnvelope<
  "host.capture.request",
  HostCaptureRequestPayload
>;

export interface ExtensionCaptureResponsePayload {
  protocolVersion: ProtocolVersion;
  capture: BrowserContextPayload;
}

export type ExtensionResponseMessage = NativeMessageEnvelope<
  "extension.capture.result",
  ExtensionCaptureResponsePayload
>;

export interface ErrorPayload {
  protocolVersion: ProtocolVersion;
  code: ProtocolErrorCode;
  message: string;
  recoverable: boolean;
  details?: Record<string, string>;
}

export type ErrorMessage = NativeMessageEnvelope<"extension.error", ErrorPayload>;

export type ExtensionMessage = ExtensionResponseMessage | ErrorMessage;

export type CaptureResultSource = "safari_extension" | "chrome_extension" | "metadata_only";

export interface CaptureResult {
  requestId: string;
  status: "success" | "fallback";
  source: CaptureResultSource;
  capturedAt: string;
  warnings: string[];
  context: NormalizedContext;
}

export interface ProtocolValidationIssue {
  code: ProtocolErrorCode;
  message: string;
}

export type ProtocolValidationResult<T> =
  | {
      ok: true;
      value: T;
    }
  | {
      ok: false;
      issues: ProtocolValidationIssue[];
    };

const isRecord = (value: unknown): value is Record<string, unknown> => {
  return typeof value === "object" && value !== null;
};

const isString = (value: unknown): value is string => {
  return typeof value === "string";
};

const isOptionalString = (value: unknown): value is string | undefined => {
  return value === undefined || isString(value);
};

const isStringArray = (value: unknown): value is string[] => {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
};

const isRecordOfStrings = (value: unknown): value is Record<string, string> => {
  if (!isRecord(value)) {
    return false;
  }

  return Object.values(value).every((entry) => typeof entry === "string");
};

const isHeading = (value: unknown): value is { level: number; text: string } => {
  if (!isRecord(value)) {
    return false;
  }

  const level = value.level;
  const text = value.text;

  return (
    typeof level === "number" &&
    Number.isInteger(level) &&
    level >= 1 &&
    level <= 6 &&
    isString(text)
  );
};

const isHeadingArray = (value: unknown): value is Array<{ level: number; text: string }> => {
  return Array.isArray(value) && value.every(isHeading);
};

const isLink = (value: unknown): value is { text: string; href: string } => {
  if (!isRecord(value)) {
    return false;
  }

  return isString(value.text) && isString(value.href);
};

const isLinkArray = (value: unknown): value is Array<{ text: string; href: string }> => {
  return Array.isArray(value) && value.every(isLink);
};

const safeSerializedLength = (value: unknown): number | null => {
  try {
    return JSON.stringify(value).length;
  } catch {
    return null;
  }
};

export const isProtocolVersion = (value: unknown): value is ProtocolVersion => {
  return value === PROTOCOL_VERSION;
};

export const isProtocolErrorCode = (value: unknown): value is ProtocolErrorCode => {
  return (
    value === "ERR_PROTOCOL_VERSION" ||
    value === "ERR_PAYLOAD_INVALID" ||
    value === "ERR_TIMEOUT" ||
    value === "ERR_EXTENSION_UNAVAILABLE" ||
    value === "ERR_PAYLOAD_TOO_LARGE"
  );
};

export const isBrowserContextPayload = (value: unknown): value is BrowserContextPayload => {
  if (!isRecord(value)) {
    return false;
  }

  if (value.source !== "browser") {
    return false;
  }

  return (
    (value.browser === "chrome" || value.browser === "safari") &&
    isString(value.url) &&
    isString(value.title) &&
    isString(value.fullText) &&
    isHeadingArray(value.headings) &&
    isLinkArray(value.links) &&
    isOptionalString(value.metaDescription) &&
    isOptionalString(value.siteName) &&
    isOptionalString(value.language) &&
    isOptionalString(value.author) &&
    isOptionalString(value.publishedTime) &&
    isOptionalString(value.selectionText) &&
    (value.extractionWarnings === undefined || isStringArray(value.extractionWarnings))
  );
};

export const isDesktopContextPayload = (value: unknown): value is DesktopContextPayload => {
  if (!isRecord(value)) {
    return false;
  }

  if (value.source !== "desktop") {
    return false;
  }

  if (
    !isString(value.appBundleId) ||
    !isString(value.appName) ||
    typeof value.usedOcr !== "boolean"
  ) {
    return false;
  }

  if (!isOptionalString(value.windowTitle) || !isOptionalString(value.accessibilityText)) {
    return false;
  }

  if (!isOptionalString(value.ocrText)) {
    return false;
  }

  if (value.ocrConfidence !== undefined) {
    if (
      typeof value.ocrConfidence !== "number" ||
      value.ocrConfidence < 0 ||
      value.ocrConfidence > 1
    ) {
      return false;
    }
  }

  if (value.extractionWarnings !== undefined && !isStringArray(value.extractionWarnings)) {
    return false;
  }

  return true;
};

export const validateBrowserPayloadSize = (
  payload: BrowserContextPayload,
): ProtocolValidationResult<BrowserContextPayload> => {
  const issues: ProtocolValidationIssue[] = [];

  if (payload.fullText.length > MAX_BROWSER_FULL_TEXT_CHARS) {
    issues.push({
      code: "ERR_PAYLOAD_TOO_LARGE",
      message: `fullText length (${payload.fullText.length}) exceeds ${MAX_BROWSER_FULL_TEXT_CHARS}.`,
    });
  }

  const serializedLength = safeSerializedLength(payload);
  if (serializedLength === null) {
    issues.push({
      code: "ERR_PAYLOAD_INVALID",
      message: "Browser payload could not be serialized.",
    });
  } else if (serializedLength > MAX_ENVELOPE_CHARS) {
    issues.push({
      code: "ERR_PAYLOAD_TOO_LARGE",
      message: `Serialized payload length (${serializedLength}) exceeds ${MAX_ENVELOPE_CHARS}.`,
    });
  }

  if (issues.length > 0) {
    return {
      ok: false,
      issues,
    };
  }

  return {
    ok: true,
    value: payload,
  };
};

export const isNativeMessageEnvelope = (value: unknown): value is NativeMessageEnvelope => {
  if (!isRecord(value)) {
    return false;
  }

  return (
    typeof value.id === "string" &&
    typeof value.type === "string" &&
    typeof value.timestamp === "string" &&
    "payload" in value
  );
};

export const isCaptureNativeMessage = (value: unknown): value is CaptureNativeMessage => {
  if (!isNativeMessageEnvelope(value)) {
    return false;
  }

  if (value.type === "browser.capture") {
    return isBrowserContextPayload(value.payload);
  }

  if (value.type === "desktop.capture") {
    return isDesktopContextPayload(value.payload);
  }

  return false;
};

export const isHostCaptureRequestPayload = (value: unknown): value is HostCaptureRequestPayload => {
  if (!isRecord(value)) {
    return false;
  }

  return (
    isProtocolVersion(value.protocolVersion) &&
    isString(value.requestId) &&
    (value.mode === "manual_hotkey" || value.mode === "manual_menu") &&
    isString(value.requestedAt) &&
    typeof value.timeoutMs === "number" &&
    Number.isFinite(value.timeoutMs) &&
    value.timeoutMs > 0 &&
    typeof value.includeSelectionText === "boolean"
  );
};

export const isExtensionCaptureResponsePayload = (
  value: unknown,
): value is ExtensionCaptureResponsePayload => {
  if (!isRecord(value)) {
    return false;
  }

  return isProtocolVersion(value.protocolVersion) && isBrowserContextPayload(value.capture);
};

export const isErrorPayload = (value: unknown): value is ErrorPayload => {
  if (!isRecord(value)) {
    return false;
  }

  return (
    isProtocolVersion(value.protocolVersion) &&
    isProtocolErrorCode(value.code) &&
    isString(value.message) &&
    typeof value.recoverable === "boolean" &&
    (value.details === undefined || isRecordOfStrings(value.details))
  );
};

export const isHostRequestMessage = (value: unknown): value is HostRequestMessage => {
  if (!isNativeMessageEnvelope(value) || value.type !== "host.capture.request") {
    return false;
  }

  return isHostCaptureRequestPayload(value.payload);
};

export const isExtensionResponseMessage = (value: unknown): value is ExtensionResponseMessage => {
  if (!isNativeMessageEnvelope(value) || value.type !== "extension.capture.result") {
    return false;
  }

  return isExtensionCaptureResponsePayload(value.payload);
};

export const isErrorMessage = (value: unknown): value is ErrorMessage => {
  if (!isNativeMessageEnvelope(value) || value.type !== "extension.error") {
    return false;
  }

  return isErrorPayload(value.payload);
};

export const isExtensionMessage = (value: unknown): value is ExtensionMessage => {
  return isExtensionResponseMessage(value) || isErrorMessage(value);
};

export const validateExtensionResponseMessage = (
  value: unknown,
): ProtocolValidationResult<ExtensionResponseMessage> => {
  const issues: ProtocolValidationIssue[] = [];

  if (!isNativeMessageEnvelope(value)) {
    return {
      ok: false,
      issues: [
        {
          code: "ERR_PAYLOAD_INVALID",
          message: "Message is not a valid envelope.",
        },
      ],
    };
  }

  if (value.type !== "extension.capture.result") {
    issues.push({
      code: "ERR_PAYLOAD_INVALID",
      message: `Unexpected message type: ${value.type}.`,
    });
  }

  if (!isExtensionCaptureResponsePayload(value.payload)) {
    issues.push({
      code: "ERR_PAYLOAD_INVALID",
      message: "Message payload does not match extension capture response shape.",
    });
  }

  if (issues.length === 0) {
    const sizeValidation = validateBrowserPayloadSize(
      (value.payload as ExtensionCaptureResponsePayload).capture,
    );
    if (!sizeValidation.ok) {
      issues.push(...sizeValidation.issues);
    }
  }

  const serializedLength = safeSerializedLength(value);
  if (serializedLength === null) {
    issues.push({
      code: "ERR_PAYLOAD_INVALID",
      message: "Extension response message could not be serialized.",
    });
  } else if (serializedLength > MAX_ENVELOPE_CHARS) {
    issues.push({
      code: "ERR_PAYLOAD_TOO_LARGE",
      message: `Serialized message length (${serializedLength}) exceeds ${MAX_ENVELOPE_CHARS}.`,
    });
  }

  if (issues.length > 0) {
    return {
      ok: false,
      issues,
    };
  }

  return {
    ok: true,
    value: value as ExtensionResponseMessage,
  };
};

export const createNativeMessageEnvelope = <TType extends string, TPayload>(
  input: NativeMessageEnvelope<TType, TPayload>,
): NativeMessageEnvelope<TType, TPayload> => {
  return {
    id: input.id,
    type: input.type,
    timestamp: input.timestamp,
    payload: input.payload,
  };
};
