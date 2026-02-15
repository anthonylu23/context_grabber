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

const sanitizeProcessMessage = (value: string): string => {
  let sanitized = "";
  for (const char of value) {
    const code = char.charCodeAt(0);
    const isPrintable = code >= 32 && code !== 127;
    const isAllowedWhitespace = code === 9 || code === 10 || code === 13;
    if (isPrintable || isAllowedWhitespace) {
      sanitized += char;
    }
  }
  return sanitized.trim();
};

const decodeSnapshotFromStdout = (stdout: string): unknown => {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Unknown JSON parse failure.";
    throw new Error(`Safari extraction produced invalid JSON: ${reason}`);
  }

  if (typeof parsed === "string") {
    const nested = parsed.trim();
    if (nested.length === 0) {
      return parsed;
    }

    try {
      return JSON.parse(nested);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "Unknown nested JSON parse failure.";
      throw new Error(
        `Safari extraction produced wrapped JSON that could not be decoded: ${reason}`,
      );
    }
  }

  return parsed;
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
    const stderr = sanitizeProcessMessage(result.stderr || "");
    throw new Error(stderr.length > 0 ? stderr : `osascript exited with status ${result.status}`);
  }

  const stdout = (result.stdout || "").trim();
  if (stdout.length === 0) {
    throw new Error("Safari extraction returned an empty response.");
  }

  const parsed = decodeSnapshotFromStdout(stdout);

  return toSafariExtractionInput(parsed, options.includeSelectionText);
};
