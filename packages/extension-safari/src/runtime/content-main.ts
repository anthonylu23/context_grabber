import { registerSafariContentCaptureListener } from "./content-entrypoint.js";

interface RuntimeBrowserLike {
  runtime?: {
    onMessage?: {
      addListener?: (
        listener: (message: unknown, sender: unknown) => unknown | Promise<unknown>,
      ) => void;
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

export const bootstrapSafariRuntimeContent = (browserOverride?: RuntimeBrowserLike): boolean => {
  const runtimeBrowser = browserOverride ?? resolveRuntimeBrowser();
  if (!runtimeBrowser?.runtime?.onMessage?.addListener) {
    return false;
  }

  registerSafariContentCaptureListener(runtimeBrowser as never);
  return true;
};

void bootstrapSafariRuntimeContent();
