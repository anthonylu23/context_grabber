import { spawnSync } from "node:child_process";
import {
  type ExtractionInput,
  type PageSnapshot,
  buildDocumentScript,
  toExtractionInput,
} from "@context-grabber/extension-shared";

export type { PageSnapshot as ChromePageSnapshot };

export interface ChromeActiveTabExtractionOptions {
  includeSelectionText: boolean;
  timeoutMs?: number;
  osascriptBinary?: string;
  maxBufferBytes?: number;
  /** AppleScript application name for the Chromium browser (e.g. "Google Chrome", "Arc", "Brave Browser"). */
  chromeAppName?: string;
}

const DEFAULT_OSASCRIPT_MAX_BUFFER_BYTES = 8 * 1024 * 1024;

/**
 * Re-export shared helpers under Chrome-specific names for backward
 * compatibility with existing test imports.
 */
export const toChromeExtractionInput = (
  rawSnapshot: unknown,
  includeSelectionText: boolean,
): ExtractionInput => {
  return toExtractionInput(rawSnapshot, includeSelectionText, "Chrome");
};

export const buildChromeDocumentScript = buildDocumentScript;

const escapeAppleScriptString = (value: string): string => {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
};

const buildAppleScriptProgram = (javascript: string, appName = "Google Chrome"): string[] => {
  const escapedScript = escapeAppleScriptString(javascript);

  return [
    `tell application "${appName}"`,
    `if (count of windows) = 0 then error "No ${appName} window is open."`,
    "set frontTab to active tab of front window",
    `set pageJSON to execute frontTab javascript "${escapedScript}"`,
    "return pageJSON",
    "end tell",
  ];
};

export const extractActiveTabContextFromChrome = (
  options: ChromeActiveTabExtractionOptions,
): ExtractionInput => {
  const script = buildDocumentScript(options.includeSelectionText);
  const appName = options.chromeAppName ?? "Google Chrome";
  const program = buildAppleScriptProgram(script, appName);

  const result = spawnSync(
    options.osascriptBinary ?? "osascript",
    program.flatMap((line) => ["-e", line]),
    {
      encoding: "utf8",
      timeout: options.timeoutMs ?? 1_000,
      maxBuffer: options.maxBufferBytes ?? DEFAULT_OSASCRIPT_MAX_BUFFER_BYTES,
    },
  );

  if (result.error) {
    throw new Error(`Failed to execute ${appName} extraction script: ${result.error.message}`);
  }

  if (typeof result.status === "number" && result.status !== 0) {
    const stderr = (result.stderr || "").trim();
    throw new Error(stderr.length > 0 ? stderr : `osascript exited with status ${result.status}`);
  }

  const stdout = (result.stdout || "").trim();
  if (stdout.length === 0) {
    throw new Error(`${appName} extraction returned an empty response.`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown JSON parse failure.";
    throw new Error(`${appName} extraction produced invalid JSON: ${reason}`);
  }

  return toChromeExtractionInput(parsed, options.includeSelectionText);
};
