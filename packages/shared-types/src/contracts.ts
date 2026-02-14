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
