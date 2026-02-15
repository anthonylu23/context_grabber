import { spawnSync } from "node:child_process";
import { type ExtractionInput, buildDocumentScript } from "@context-grabber/extension-shared";
import { toSafariExtractionInput } from "./sanitize-snapshot.js";

export { type SafariPageSnapshot, toSafariExtractionInput } from "./sanitize-snapshot.js";

export interface SafariActiveTabExtractionOptions {
  includeSelectionText: boolean;
  timeoutMs?: number;
  osascriptBinary?: string;
  maxBufferBytes?: number;
}

const DEFAULT_OSASCRIPT_MAX_BUFFER_BYTES = 8 * 1024 * 1024;

export const buildSafariDocumentScript = buildDocumentScript;

const escapeAppleScriptString = (value: string): string => {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
};

const buildAppleScriptProgram = (javascript: string): string[] => {
  const escapedScript = escapeAppleScriptString(javascript);

  return [
    'tell application "Safari"',
    'if (count of windows) = 0 then error "No Safari window is open."',
    "set frontDoc to current tab of front window",
    `set pageJSON to do JavaScript "${escapedScript}" in frontDoc`,
    "return pageJSON",
    "end tell",
  ];
};

export const extractActiveTabContextFromSafari = (
  options: SafariActiveTabExtractionOptions,
): ExtractionInput => {
  const script = buildDocumentScript(options.includeSelectionText);
  const program = buildAppleScriptProgram(script);

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
    throw new Error(`Failed to execute Safari extraction script: ${result.error.message}`);
  }

  if (typeof result.status === "number" && result.status !== 0) {
    const stderr = (result.stderr || "").trim();
    throw new Error(stderr.length > 0 ? stderr : `osascript exited with status ${result.status}`);
  }

  const stdout = (result.stdout || "").trim();
  if (stdout.length === 0) {
    throw new Error("Safari extraction returned an empty response.");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown JSON parse failure.";
    throw new Error(`Safari extraction produced invalid JSON: ${reason}`);
  }

  return toSafariExtractionInput(parsed, options.includeSelectionText);
};
