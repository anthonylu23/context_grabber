import { registerSafariBackgroundRuntimeBridge } from "./background-entrypoint.js";

interface RuntimeBrowserLike {
  tabs?: unknown;
  runtime?: {
    onConnect?: {
      addListener?: (listener: (port: unknown) => void) => void;
    };
  };
}

const resolveRuntimeBrowser = (): RuntimeBrowserLike | undefined => {
  const maybeBrowser = (globalThis as { browser?: RuntimeBrowserLike }).browser;
  if (!maybeBrowser) {
    return undefined;
  }

  return maybeBrowser;
};

export const bootstrapSafariRuntimeBackground = (browserOverride?: RuntimeBrowserLike): boolean => {
  const runtimeBrowser = browserOverride ?? resolveRuntimeBrowser();
  if (!runtimeBrowser?.tabs || !runtimeBrowser.runtime?.onConnect?.addListener) {
    return false;
  }

  registerSafariBackgroundRuntimeBridge(runtimeBrowser as never);
  return true;
};

void bootstrapSafariRuntimeBackground();
