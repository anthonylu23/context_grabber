import {
  type ExtensionMessage,
  type HostRequestMessage,
  PROTOCOL_VERSION,
  validateBrowserPayloadSize,
} from "@context-grabber/shared-types";
import {
  type SafariExtractionInput,
  createSafariBrowserPayload,
  createSafariCaptureResponseMessage,
  createSafariErrorMessage,
  supportsHostCaptureRequest,
} from "./index.js";

export interface HostRequestHandlingOptions {
  now?: () => string;
}

const asRecord = (value: unknown): Record<string, unknown> | null => {
  if (typeof value !== "object" || value === null) {
    return null;
  }

  return value as Record<string, unknown>;
};

const inferRequestId = (request: unknown): string => {
  const record = asRecord(request);
  if (!record) {
    return crypto.randomUUID();
  }

  return typeof record.id === "string" ? record.id : crypto.randomUUID();
};

const inferProtocolVersion = (request: unknown): string | undefined => {
  const record = asRecord(request);
  if (!record) {
    return undefined;
  }

  const payload = asRecord(record.payload);
  if (!payload) {
    return undefined;
  }

  return typeof payload.protocolVersion === "string" ? payload.protocolVersion : undefined;
};

const resolveErrorCode = (request: unknown): "ERR_PROTOCOL_VERSION" | "ERR_PAYLOAD_INVALID" => {
  const protocolVersion = inferProtocolVersion(request);
  if (protocolVersion !== undefined && protocolVersion !== PROTOCOL_VERSION) {
    return "ERR_PROTOCOL_VERSION";
  }

  return "ERR_PAYLOAD_INVALID";
};

export const handleHostCaptureRequest = async (
  request: unknown,
  loadActiveTabCapture: (request: HostRequestMessage) => Promise<SafariExtractionInput>,
  options: HostRequestHandlingOptions = {},
): Promise<ExtensionMessage> => {
  const timestamp = options.now ? options.now() : new Date().toISOString();
  const requestId = inferRequestId(request);

  if (!supportsHostCaptureRequest(request)) {
    const errorCode = resolveErrorCode(request);
    const message =
      errorCode === "ERR_PROTOCOL_VERSION"
        ? `Protocol version mismatch. Expected ${PROTOCOL_VERSION}.`
        : "Host capture request payload is invalid.";

    return createSafariErrorMessage(errorCode, message, requestId, timestamp, false);
  }

  let extraction: SafariExtractionInput;
  try {
    extraction = await loadActiveTabCapture(request);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown extension transport failure.";
    return createSafariErrorMessage(
      "ERR_EXTENSION_UNAVAILABLE",
      `Failed to load active tab context: ${reason}`,
      request.id,
      timestamp,
      true,
    );
  }

  const payload = createSafariBrowserPayload(extraction);
  const sizeValidation = validateBrowserPayloadSize(payload);
  if (!sizeValidation.ok) {
    const issue = sizeValidation.issues[0] ?? {
      code: "ERR_PAYLOAD_INVALID" as const,
      message: "Browser payload validation failed.",
    };

    return createSafariErrorMessage(issue.code, issue.message, request.id, timestamp, true);
  }

  return createSafariCaptureResponseMessage(payload, request.id, timestamp);
};
