import {
  type BrowserCaptureAttempt,
  requestBrowserCapture,
} from "@context-grabber/native-host-bridge";
import type { HostRequestMessage } from "@context-grabber/shared-types";
import type { BridgeClient, BrowserTarget } from "./native-bridge.js";

interface CaptureFocusedResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

interface CaptureFocusedOptions {
  bridge: BridgeClient;
  env?: NodeJS.ProcessEnv;
  now?: () => string;
  randomUUID?: () => string;
}

const DEFAULT_TIMEOUT_MS = 1_200;

const resolveTargetOverride = (env: NodeJS.ProcessEnv): BrowserTarget | null => {
  const raw = env.CONTEXT_GRABBER_BROWSER_TARGET?.trim().toLowerCase();
  if (!raw) {
    return null;
  }

  if (raw === "safari" || raw === "chrome") {
    return raw;
  }

  throw new Error(
    `Invalid CONTEXT_GRABBER_BROWSER_TARGET value: ${raw}. Expected "safari" or "chrome".`,
  );
};

const targetDisplayName = (target: BrowserTarget): string => {
  return target === "safari" ? "Safari" : "Chrome";
};

const attemptBrowserCapture = async (
  target: BrowserTarget,
  options: CaptureFocusedOptions,
): Promise<BrowserCaptureAttempt> => {
  const requestId = options.randomUUID ? options.randomUUID() : crypto.randomUUID();
  return requestBrowserCapture({
    requestId: requestId.toLowerCase(),
    mode: "manual_menu",
    timeoutMs: DEFAULT_TIMEOUT_MS,
    now: options.now ?? (() => new Date().toISOString()),
    metadata: {
      browser: target,
      title: `${targetDisplayName(target)} (focused)`,
    },
    send: async (request: HostRequestMessage) => {
      return options.bridge.sendCaptureRequest(target, request);
    },
  });
};

const describeAttemptFailure = (target: BrowserTarget, attempt: BrowserCaptureAttempt): string => {
  const warning = attempt.warnings[0] ?? "Unknown capture error.";
  const code = attempt.errorCode ?? "ERR_EXTENSION_UNAVAILABLE";
  return `${targetDisplayName(target)} capture failed (${code}): ${warning}`;
};

export const runCaptureFocused = async (
  options: CaptureFocusedOptions,
): Promise<CaptureFocusedResult> => {
  const env = options.env ?? process.env;
  const targetOverride = resolveTargetOverride(env);
  const order: BrowserTarget[] = targetOverride ? [targetOverride] : ["safari", "chrome"];

  let unavailableCount = 0;
  let terminalError: string | null = null;

  for (const target of order) {
    const attempt = await attemptBrowserCapture(target, options);

    if (attempt.extractionMethod === "browser_extension") {
      return {
        exitCode: 0,
        stdout: `${attempt.markdown}\n`,
        stderr: "",
      };
    }

    if (attempt.errorCode === "ERR_EXTENSION_UNAVAILABLE") {
      unavailableCount += 1;
      terminalError = describeAttemptFailure(target, attempt);
      continue;
    }

    return {
      exitCode: 1,
      stdout: "",
      stderr: `${describeAttemptFailure(target, attempt)}\n`,
    };
  }

  if (unavailableCount === order.length) {
    const onlyTarget = order[0];
    const suffix =
      order.length > 1
        ? "Neither Safari nor Chrome bridge is currently reachable."
        : `${targetDisplayName(onlyTarget ?? "safari")} bridge is currently unreachable.`;
    return {
      exitCode: 1,
      stdout: "",
      stderr: `${terminalError ?? "Capture failed."} ${suffix}\n`,
    };
  }

  return {
    exitCode: 1,
    stdout: "",
    stderr: "Capture failed for an unknown reason.\n",
  };
};
