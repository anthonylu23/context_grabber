import type { ExtensionMessage, HostRequestMessage } from "@context-grabber/shared-types";
import type { SafariExtractionInput } from "../index.js";
import { handleHostCaptureRequest } from "../transport.js";

export interface BackgroundCaptureDependencies {
  captureActiveTab: (options: { includeSelectionText: boolean }) => Promise<SafariExtractionInput>;
  now?: () => string;
}

export const handleBackgroundCaptureRequest = async (
  request: unknown,
  dependencies: BackgroundCaptureDependencies,
): Promise<ExtensionMessage> => {
  const options = dependencies.now ? { now: dependencies.now } : {};

  return handleHostCaptureRequest(
    request,
    async (hostRequest: HostRequestMessage) => {
      return dependencies.captureActiveTab({
        includeSelectionText: hostRequest.payload.includeSelectionText,
      });
    },
    options,
  );
};
