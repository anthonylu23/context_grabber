import type { ExtractionInput } from "./payload.js";

/**
 * Loosely-typed snapshot returned from an in-page document script.
 * Every field is `unknown` so the sanitizer can validate and coerce
 * before producing a well-typed {@link ExtractionInput}.
 */
export interface PageSnapshot {
  url?: unknown;
  title?: unknown;
  fullText?: unknown;
  headings?: unknown;
  links?: unknown;
  metaDescription?: unknown;
  siteName?: unknown;
  language?: unknown;
  author?: unknown;
  publishedTime?: unknown;
  selectionText?: unknown;
}

const MAX_LINKS = 200;

export const asString = (value: unknown): string | undefined => {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
};

export const normalizeText = (value: unknown): string => {
  if (typeof value !== "string") {
    return "";
  }

  return value
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
};

export const sanitizeHeadings = (value: unknown): Array<{ level: number; text: string }> => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => {
      if (typeof item !== "object" || item === null) {
        return null;
      }

      const level = (item as { level?: unknown }).level;
      const text = asString((item as { text?: unknown }).text);
      if (
        typeof level !== "number" ||
        !Number.isInteger(level) ||
        level < 1 ||
        level > 6 ||
        !text
      ) {
        return null;
      }

      return { level, text };
    })
    .filter((item): item is { level: number; text: string } => item !== null);
};

export const sanitizeLinks = (value: unknown): Array<{ text: string; href: string }> => {
  if (!Array.isArray(value)) {
    return [];
  }

  const unique = new Set<string>();
  const links: Array<{ text: string; href: string }> = [];

  for (const item of value) {
    if (typeof item !== "object" || item === null) {
      continue;
    }

    const text = asString((item as { text?: unknown }).text);
    const href = asString((item as { href?: unknown }).href);

    if (!text || !href) {
      continue;
    }

    const dedupeKey = `${text}::${href}`;
    if (unique.has(dedupeKey)) {
      continue;
    }

    unique.add(dedupeKey);
    links.push({ text, href });

    if (links.length >= MAX_LINKS) {
      break;
    }
  }

  return links;
};

/**
 * Validate and coerce a raw in-page snapshot into a well-typed
 * {@link ExtractionInput}.
 *
 * @param rawSnapshot  - The loosely-typed value produced by the document script.
 * @param includeSelectionText - Whether to retain the user's text selection.
 * @param browserLabel - A human-readable browser name used in error messages (e.g. "Chrome", "Safari").
 */
export const toExtractionInput = (
  rawSnapshot: unknown,
  includeSelectionText: boolean,
  browserLabel: string,
): ExtractionInput => {
  if (typeof rawSnapshot !== "object" || rawSnapshot === null) {
    throw new Error(`${browserLabel} extraction snapshot is not an object.`);
  }

  const snapshot = rawSnapshot as PageSnapshot;
  const url = asString(snapshot.url);
  const title = asString(snapshot.title);

  if (!url || !title) {
    throw new Error(`${browserLabel} extraction is missing required url/title fields.`);
  }

  const result: ExtractionInput = {
    url,
    title,
    fullText: normalizeText(snapshot.fullText),
    headings: sanitizeHeadings(snapshot.headings),
    links: sanitizeLinks(snapshot.links),
  };

  const metaDescription = asString(snapshot.metaDescription);
  const siteName = asString(snapshot.siteName);
  const language = asString(snapshot.language);
  const author = asString(snapshot.author);
  const publishedTime = asString(snapshot.publishedTime);
  const selectionText = asString(snapshot.selectionText);

  if (metaDescription) {
    result.metaDescription = metaDescription;
  }
  if (siteName) {
    result.siteName = siteName;
  }
  if (language) {
    result.language = language;
  }
  if (author) {
    result.author = author;
  }
  if (publishedTime) {
    result.publishedTime = publishedTime;
  }
  if (includeSelectionText && selectionText) {
    result.selectionText = selectionText;
  }

  return result;
};
