import { registerSafariBackgroundRuntimeBridge } from "./background-entrypoint.js";

type BackgroundBridgeBrowser = Parameters<typeof registerSafariBackgroundRuntimeBridge>[0];

interface RuntimeBrowserLike {
  tabs?: {
    query?: unknown;
    sendMessage?: unknown;
  };
  runtime?: {
    onConnect?: {
      addListener?: (listener: (port: unknown) => void) => void;
    };
  };
}

const isRuntimeBackgroundBrowser = (
  value: RuntimeBrowserLike | undefined,
): value is BackgroundBridgeBrowser => {
  return Boolean(
    value &&
      typeof value.tabs?.query === "function" &&
      typeof value.tabs?.sendMessage === "function" &&
      typeof value.runtime?.onConnect?.addListener === "function",
  );
};

const resolveRuntimeBrowser = (): RuntimeBrowserLike | undefined => {
  const maybeBrowser = (globalThis as { browser?: RuntimeBrowserLike }).browser;
  if (!maybeBrowser) {
    return undefined;
  }

  return maybeBrowser;
};

export const bootstrapSafariRuntimeBackground = (browserOverride?: RuntimeBrowserLike): boolean => {
  const runtimeBrowser = browserOverride ?? resolveRuntimeBrowser();
  if (!isRuntimeBackgroundBrowser(runtimeBrowser)) {
    return false;
  }

  registerSafariBackgroundRuntimeBridge(runtimeBrowser);
  return true;
};

void bootstrapSafariRuntimeBackground();
