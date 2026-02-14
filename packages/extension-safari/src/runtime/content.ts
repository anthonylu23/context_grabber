import { toSafariExtractionInput } from "../extract-active-tab.js";
import type { SafariExtractionInput } from "../index.js";

const normalizeText = (value: string): string => {
  return value
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
};

const safeText = (value: string | null | undefined): string => {
  if (typeof value !== "string") {
    return "";
  }

  return normalizeText(value);
};

const readMetaContent = (document: Document, selectors: string[]): string | undefined => {
  for (const selector of selectors) {
    const element = document.querySelector(selector);
    if (!element) {
      continue;
    }

    const content = element.getAttribute("content");
    if (typeof content !== "string") {
      continue;
    }

    const normalized = normalizeText(content);
    if (normalized.length > 0) {
      return normalized;
    }
  }

  return undefined;
};

export interface CaptureFromDocumentOptions {
  includeSelectionText: boolean;
  selectionProvider?: () => string;
}

export interface RuntimeSafariPageSnapshot {
  url: string;
  title: string;
  fullText: string;
  headings: Array<{ level: number; text: string }>;
  links: Array<{ text: string; href: string }>;
  metaDescription?: string;
  siteName?: string;
  language?: string;
  author?: string;
  publishedTime?: string;
  selectionText?: string;
}

export const capturePageSnapshotFromDocument = (
  document: Document,
  options: CaptureFromDocumentOptions,
): RuntimeSafariPageSnapshot => {
  const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4, h5, h6"))
    .map((heading) => {
      const tag = heading.tagName.toLowerCase();
      const parsedLevel = Number.parseInt(tag.slice(1), 10);
      return {
        level: Number.isInteger(parsedLevel) ? parsedLevel : 1,
        text: safeText(heading.textContent),
      };
    })
    .filter((heading) => heading.text.length > 0);

  const links = Array.from(document.querySelectorAll("a[href]"))
    .map((link) => ({
      text: safeText(link.textContent),
      href: safeText((link as HTMLAnchorElement).href),
    }))
    .filter((link) => link.text.length > 0 && link.href.length > 0)
    .slice(0, 200);

  const selectionText = options.includeSelectionText
    ? safeText(
        options.selectionProvider
          ? options.selectionProvider()
          : String(globalThis.getSelection ? globalThis.getSelection() : ""),
      )
    : undefined;

  const snapshot: RuntimeSafariPageSnapshot = {
    url: safeText(document.location?.href),
    title: safeText(document.title),
    fullText: safeText(document.body?.innerText ?? ""),
    headings,
    links,
  };

  const metaDescription = readMetaContent(document, [
    'meta[name="description"]',
    'meta[property="og:description"]',
  ]);
  if (metaDescription !== undefined) {
    snapshot.metaDescription = metaDescription;
  }

  const siteName = readMetaContent(document, [
    'meta[property="og:site_name"]',
    'meta[name="application-name"]',
  ]);
  if (siteName !== undefined) {
    snapshot.siteName = siteName;
  }

  const language = safeText(document.documentElement?.lang ?? "") || undefined;
  if (language !== undefined) {
    snapshot.language = language;
  }

  const author = readMetaContent(document, [
    'meta[name="author"]',
    'meta[property="article:author"]',
  ]);
  if (author !== undefined) {
    snapshot.author = author;
  }

  const publishedTime = readMetaContent(document, [
    'meta[property="article:published_time"]',
    'meta[name="article:published_time"]',
  ]);
  if (publishedTime !== undefined) {
    snapshot.publishedTime = publishedTime;
  }

  if (selectionText && selectionText.length > 0) {
    snapshot.selectionText = selectionText;
  }

  return snapshot;
};

export const extractSafariContextFromDocument = (
  document: Document,
  options: CaptureFromDocumentOptions,
): SafariExtractionInput => {
  const snapshot = capturePageSnapshotFromDocument(document, options);
  return toSafariExtractionInput(snapshot, options.includeSelectionText);
};
