import { registerSafariContentCaptureListener } from "./content-entrypoint.js";

type ContentBridgeBrowser = Parameters<typeof registerSafariContentCaptureListener>[0];

interface RuntimeBrowserLike {
  runtime?: {
    onMessage?: {
      addListener?: (
        listener: (message: unknown, sender: unknown) => unknown | Promise<unknown>,
      ) => void;
    };
  };
}

const isRuntimeContentBrowser = (
  value: RuntimeBrowserLike | undefined,
): value is ContentBridgeBrowser => {
  return Boolean(value && typeof value.runtime?.onMessage?.addListener === "function");
};

const resolveRuntimeBrowser = (): RuntimeBrowserLike | undefined => {
  const maybeBrowser = (globalThis as { browser?: RuntimeBrowserLike }).browser;
  if (!maybeBrowser) {
    return undefined;
  }

  return maybeBrowser;
};

export const bootstrapSafariRuntimeContent = (browserOverride?: RuntimeBrowserLike): boolean => {
  const runtimeBrowser = browserOverride ?? resolveRuntimeBrowser();
  if (!isRuntimeContentBrowser(runtimeBrowser)) {
    return false;
  }

  registerSafariContentCaptureListener(runtimeBrowser);
  return true;
};

void bootstrapSafariRuntimeContent();
