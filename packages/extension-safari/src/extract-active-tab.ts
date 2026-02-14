import { spawnSync } from "node:child_process";
import type { SafariExtractionInput } from "./index.js";
import { toSafariExtractionInput } from "./sanitize-snapshot.js";

export { type SafariPageSnapshot, toSafariExtractionInput } from "./sanitize-snapshot.js";

export interface SafariActiveTabExtractionOptions {
  includeSelectionText: boolean;
  timeoutMs?: number;
  osascriptBinary?: string;
  maxBufferBytes?: number;
}

const DEFAULT_OSASCRIPT_MAX_BUFFER_BYTES = 8 * 1024 * 1024;

export const buildSafariDocumentScript = (includeSelectionText: boolean): string => {
  const includeSelectionLiteral = includeSelectionText ? "true" : "false";

  return `(() => {
  const normalize = (value) => {
    if (typeof value !== "string") {
      return "";
    }

    return value
      .replace(/\\r\\n?/g, "\\n")
      .replace(/[ \\t]+\\n/g, "\\n")
      .replace(/\\n{3,}/g, "\\n\\n")
      .trim();
  };

  const meta = (selector) => {
    const element = document.querySelector(selector);
    if (!element) {
      return undefined;
    }

    const content = element.getAttribute("content");
    if (typeof content !== "string") {
      return undefined;
    }

    const trimmed = content.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  };

  const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4, h5, h6")).map((heading) => {
    const tagName = heading.tagName.toLowerCase();
    const parsedLevel = Number.parseInt(tagName.slice(1), 10);
    return {
      level: Number.isInteger(parsedLevel) ? parsedLevel : 1,
      text: normalize(heading.textContent || ""),
    };
  }).filter((heading) => heading.text.length > 0);

  const links = Array.from(document.querySelectorAll("a[href]")).map((link) => ({
    text: normalize(link.textContent || ""),
    href: normalize(link.href || ""),
  })).filter((link) => link.text.length > 0 && link.href.length > 0).slice(0, 200);

  const selectionText = ${includeSelectionLiteral}
    ? normalize(String(window.getSelection ? window.getSelection() : ""))
    : undefined;

  return JSON.stringify({
    url: document.location ? document.location.href : "",
    title: document.title || "",
    fullText: normalize(document.body ? document.body.innerText : ""),
    headings,
    links,
    metaDescription: meta('meta[name="description"]') || meta('meta[property="og:description"]'),
    siteName: meta('meta[property="og:site_name"]') || meta('meta[name="application-name"]'),
    language: (document.documentElement && document.documentElement.lang) || undefined,
    author: meta('meta[name="author"]') || meta('meta[property="article:author"]'),
    publishedTime: meta('meta[property="article:published_time"]') || meta('meta[name="article:published_time"]'),
    selectionText,
  });
})();`;
};

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
): SafariExtractionInput => {
  const script = buildSafariDocumentScript(options.includeSelectionText);
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
