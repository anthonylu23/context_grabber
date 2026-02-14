import { toSafariExtractionInput } from "../extract-active-tab.js";
import type { SafariExtractionInput } from "../index.js";
import { DEFAULT_NATIVE_HOST_PORT_NAME, createCaptureActiveTabMessage } from "./messages.js";
import { bindRuntimeNativeHostPort } from "./native-host.js";

interface RuntimePort {
  name?: string;
  onMessage: {
    addListener: (listener: (request: unknown) => void | Promise<void>) => void;
  };
  postMessage: (response: unknown) => void;
}

interface RuntimeBrowserTabsApi {
  query: (queryInfo: { active: boolean; currentWindow: boolean }) => Promise<
    Array<{ id?: number }>
  >;
  sendMessage: (tabId: number, message: unknown) => Promise<unknown>;
}

interface RuntimeBrowserApi {
  tabs: RuntimeBrowserTabsApi;
  runtime: {
    onConnect: {
      addListener: (listener: (port: RuntimePort) => void) => void;
    };
  };
}

export interface RegisterSafariBackgroundRuntimeBridgeOptions {
  nativeHostPortName?: string;
  now?: () => string;
}

const resolveActiveTabCapture = async (
  browser: RuntimeBrowserApi,
  includeSelectionText: boolean,
): Promise<SafariExtractionInput> => {
  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const activeTab = tabs[0];
  if (!activeTab || typeof activeTab.id !== "number") {
    throw new Error("No active tab is available for Safari runtime capture.");
  }

  const rawCapture = await browser.tabs.sendMessage(
    activeTab.id,
    createCaptureActiveTabMessage(includeSelectionText),
  );
  return toSafariExtractionInput(rawCapture, includeSelectionText);
};

export const registerSafariBackgroundRuntimeBridge = (
  browser: RuntimeBrowserApi,
  options: RegisterSafariBackgroundRuntimeBridgeOptions = {},
): void => {
  const nativeHostPortName = options.nativeHostPortName ?? DEFAULT_NATIVE_HOST_PORT_NAME;

  browser.runtime.onConnect.addListener((port) => {
    if (port.name !== nativeHostPortName) {
      return;
    }

    const captureActiveTab = async ({
      includeSelectionText,
    }: { includeSelectionText: boolean }) => {
      return resolveActiveTabCapture(browser, includeSelectionText);
    };

    const dependencies = options.now
      ? { now: options.now, captureActiveTab }
      : { captureActiveTab };

    bindRuntimeNativeHostPort(port, dependencies);
  });
};
