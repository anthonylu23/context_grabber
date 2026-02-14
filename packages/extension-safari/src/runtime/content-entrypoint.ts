import { capturePageSnapshotFromDocument } from "./content.js";
import { isCaptureActiveTabMessage } from "./messages.js";

interface RuntimeContentApi {
  onMessage: {
    addListener: (
      listener: (message: unknown, sender: unknown) => unknown | Promise<unknown>,
    ) => void;
  };
}

interface RuntimeContentBrowserApi {
  runtime: RuntimeContentApi;
}

export const registerSafariContentCaptureListener = (
  browser: RuntimeContentBrowserApi,
  documentProvider: () => Document = () => document,
): void => {
  browser.runtime.onMessage.addListener(async (message: unknown) => {
    if (!isCaptureActiveTabMessage(message)) {
      return undefined;
    }

    const snapshot = capturePageSnapshotFromDocument(documentProvider(), {
      includeSelectionText: message.includeSelectionText,
    });

    return snapshot;
  });
};
