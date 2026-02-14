import type { ExtensionMessage } from "@context-grabber/shared-types";
import { PROTOCOL_VERSION } from "@context-grabber/shared-types";
import { type SafariExtractionInput, createSafariErrorMessage } from "../index.js";
import { handleBackgroundCaptureRequest } from "./background.js";

interface RuntimeNativeHostPort {
  onMessage: {
    addListener: (listener: (request: unknown) => void | Promise<void>) => void;
  };
  postMessage: (response: ExtensionMessage) => void;
}

interface RuntimeNativeHostDependencies {
  captureActiveTab: (options: { includeSelectionText: boolean }) => Promise<SafariExtractionInput>;
  now?: () => string;
}

const requestIdFromUnknown = (request: unknown): string => {
  if (typeof request !== "object" || request === null) {
    return crypto.randomUUID();
  }

  const record = request as Record<string, unknown>;
  return typeof record.id === "string" ? record.id : crypto.randomUUID();
};

const createFatalBridgeError = (request: unknown, message: string): ExtensionMessage => {
  return createSafariErrorMessage(
    "ERR_EXTENSION_UNAVAILABLE",
    message,
    requestIdFromUnknown(request),
    new Date().toISOString(),
    true,
  );
};

export const bindRuntimeNativeHostPort = (
  port: RuntimeNativeHostPort,
  dependencies: RuntimeNativeHostDependencies,
): void => {
  port.onMessage.addListener((request: unknown) => {
    void (async () => {
      try {
        const backgroundDependencies = dependencies.now
          ? { captureActiveTab: dependencies.captureActiveTab, now: dependencies.now }
          : { captureActiveTab: dependencies.captureActiveTab };
        const response = await handleBackgroundCaptureRequest(request, backgroundDependencies);
        port.postMessage(response);
      } catch (error) {
        const reason =
          error instanceof Error ? error.message : "Unhandled Safari runtime bridge failure.";
        port.postMessage(
          createFatalBridgeError(
            request,
            `Runtime bridge failed unexpectedly (${PROTOCOL_VERSION}): ${reason}`,
          ),
        );
      }
    })();
  });
};
