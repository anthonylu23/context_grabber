import {
  type BrowserContextPayload,
  type ExtractionMethod,
  MAX_BROWSER_FULL_TEXT_CHARS,
  type NormalizedContext,
} from "@context-grabber/shared-types";

const MAX_SUMMARY_LINES = 6;
const MAX_KEY_POINTS = 8;
const MAX_RAW_EXCERPT_CHARS = 8_000;
const TARGET_CHUNK_TOKENS = 1_500;
const HARD_CHUNK_TOKENS = 2_000;

interface NormalizeBrowserContextOptions {
  id: string;
  capturedAt: string;
  extractionMethod: ExtractionMethod;
  warnings?: string[];
}

interface ScoredSentence {
  index: number;
  sentence: string;
  score: number;
  words: Set<string>;
}

const toWords = (text: string): string[] => {
  const matches = text.toLowerCase().match(/[a-z0-9]+/g);
  return matches ?? [];
};

const toWordSet = (text: string): Set<string> => {
  return new Set(toWords(text));
};

const estimateTokens = (text: string): number => {
  const trimmed = text.trim();
  if (trimmed.length === 0) {
    return 0;
  }

  return Math.ceil(trimmed.length / 4);
};

const sanitizeText = (text: string): string => {
  return text
    .replace(/\r\n?/g, "\n")
    .replace(/[\t ]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
};

const sentenceSplit = (text: string): string[] => {
  return text
    .split(/(?<=[.!?])\s+/)
    .map((sentence) => sentence.trim())
    .filter((sentence) => sentence.length > 0);
};

const scoreSentences = (
  text: string,
  headings: Array<{ level: number; text: string }>,
): ScoredSentence[] => {
  const sentences = sentenceSplit(text);
  const headingWordSet = new Set(headings.flatMap((heading) => toWords(heading.text)));

  return sentences.map((sentence, index) => {
    const words = toWordSet(sentence);
    const headingOverlap = Array.from(words).filter((word) => headingWordSet.has(word)).length;
    const lengthScore = Math.min(words.size / 24, 1);
    const headingScore = Math.min(headingOverlap, 4) * 0.6;
    const positionScore = 1 / (index + 1);
    const punctuationScore = sentence.includes(":") ? 0.2 : 0;

    return {
      index,
      sentence,
      words,
      score: lengthScore + headingScore + positionScore + punctuationScore,
    };
  });
};

const selectSummaryLines = (scoredSentences: ScoredSentence[]): string[] => {
  const selected = [...scoredSentences]
    .sort((left, right) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }

      return left.index - right.index;
    })
    .slice(0, MAX_SUMMARY_LINES)
    .sort((left, right) => left.index - right.index)
    .map((entry) => entry.sentence);

  return selected;
};

const wordSetOverlap = (left: Set<string>, right: Set<string>): number => {
  if (left.size === 0 || right.size === 0) {
    return 0;
  }

  let intersectionCount = 0;
  for (const value of left) {
    if (right.has(value)) {
      intersectionCount += 1;
    }
  }

  return intersectionCount / Math.min(left.size, right.size);
};

const selectKeyPoints = (scoredSentences: ScoredSentence[]): string[] => {
  const selected: ScoredSentence[] = [];

  for (const candidate of [...scoredSentences].sort((left, right) => {
    if (right.score !== left.score) {
      return right.score - left.score;
    }

    return left.index - right.index;
  })) {
    const isNearDuplicate = selected.some(
      (current) => wordSetOverlap(current.words, candidate.words) >= 0.7,
    );
    if (isNearDuplicate) {
      continue;
    }

    selected.push(candidate);
    if (selected.length >= MAX_KEY_POINTS) {
      break;
    }
  }

  return selected.sort((left, right) => left.index - right.index).map((entry) => entry.sentence);
};

const splitLongParagraph = (paragraph: string): string[] => {
  const sentenceParts = sentenceSplit(paragraph);
  if (sentenceParts.length <= 1) {
    const chunkSizeChars = HARD_CHUNK_TOKENS * 4;
    const chunks: string[] = [];

    for (let offset = 0; offset < paragraph.length; offset += chunkSizeChars) {
      chunks.push(paragraph.slice(offset, offset + chunkSizeChars).trim());
    }

    return chunks.filter((chunk) => chunk.length > 0);
  }

  const chunks: string[] = [];
  let currentChunk: string[] = [];
  let currentTokens = 0;

  for (const sentence of sentenceParts) {
    const sentenceTokens = estimateTokens(sentence);
    if (currentTokens > 0 && currentTokens + sentenceTokens > HARD_CHUNK_TOKENS) {
      chunks.push(currentChunk.join(" "));
      currentChunk = [];
      currentTokens = 0;
    }

    currentChunk.push(sentence);
    currentTokens += sentenceTokens;
  }

  if (currentChunk.length > 0) {
    chunks.push(currentChunk.join(" "));
  }

  return chunks;
};

const createChunks = (
  text: string,
): Array<{ chunkId: string; tokenEstimate: number; text: string }> => {
  const paragraphs = text
    .split(/\n{2,}/)
    .map((paragraph) => paragraph.trim())
    .filter((paragraph) => paragraph.length > 0);

  const chunks: Array<{ chunkId: string; tokenEstimate: number; text: string }> = [];
  let currentParts: string[] = [];
  let currentTokens = 0;

  const flushCurrentChunk = (): void => {
    if (currentParts.length === 0) {
      return;
    }

    const chunkText = currentParts.join("\n\n").trim();
    chunks.push({
      chunkId: `chunk-${String(chunks.length + 1).padStart(3, "0")}`,
      tokenEstimate: estimateTokens(chunkText),
      text: chunkText,
    });

    currentParts = [];
    currentTokens = 0;
  };

  const addParagraph = (paragraph: string): void => {
    const paragraphTokens = estimateTokens(paragraph);

    if (currentTokens > 0 && currentTokens + paragraphTokens > TARGET_CHUNK_TOKENS) {
      flushCurrentChunk();
    }

    currentParts.push(paragraph);
    currentTokens += paragraphTokens;

    if (currentTokens >= HARD_CHUNK_TOKENS) {
      flushCurrentChunk();
    }
  };

  for (const paragraph of paragraphs) {
    const paragraphTokens = estimateTokens(paragraph);
    if (paragraphTokens <= HARD_CHUNK_TOKENS) {
      addParagraph(paragraph);
      continue;
    }

    for (const splitPart of splitLongParagraph(paragraph)) {
      addParagraph(splitPart);
    }
  }

  flushCurrentChunk();
  return chunks;
};

const uniqueInOrder = (values: string[]): string[] => {
  const seen = new Set<string>();
  const unique: string[] = [];

  for (const value of values) {
    if (seen.has(value)) {
      continue;
    }

    seen.add(value);
    unique.push(value);
  }

  return unique;
};

const extractUrlHost = (url: string): string | null => {
  try {
    return new URL(url).host;
  } catch {
    return null;
  }
};

export const normalizeBrowserContext = (
  payload: BrowserContextPayload,
  options: NormalizeBrowserContextOptions,
): NormalizedContext => {
  const warningMessages = [...(options.warnings ?? []), ...(payload.extractionWarnings ?? [])];
  let normalizedText = sanitizeText(payload.fullText);
  let truncated = false;

  if (normalizedText.length > MAX_BROWSER_FULL_TEXT_CHARS) {
    normalizedText = normalizedText.slice(0, MAX_BROWSER_FULL_TEXT_CHARS);
    truncated = true;
    warningMessages.push(
      `Capture text exceeded ${MAX_BROWSER_FULL_TEXT_CHARS} characters and was truncated.`,
    );
  }

  const scoredSentences = scoreSentences(normalizedText, payload.headings);
  const summaryLines = selectSummaryLines(scoredSentences);
  const keyPoints = selectKeyPoints(scoredSentences);
  const chunks = createChunks(normalizedText);

  const metadataEntries: Array<[string, string]> = [
    ["browser", payload.browser],
    ["url", payload.url],
  ];

  if (payload.metaDescription) {
    metadataEntries.push(["meta_description", payload.metaDescription]);
  }
  if (payload.siteName) {
    metadataEntries.push(["site_name", payload.siteName]);
  }
  if (payload.language) {
    metadataEntries.push(["language", payload.language]);
  }
  if (payload.author) {
    metadataEntries.push(["author", payload.author]);
  }
  if (payload.publishedTime) {
    metadataEntries.push(["published_time", payload.publishedTime]);
  }

  metadataEntries.sort(([left], [right]) => left.localeCompare(right));

  const metadata: Record<string, string> = {};
  for (const [key, value] of metadataEntries) {
    metadata[key] = value;
  }

  return {
    id: options.id,
    capturedAt: options.capturedAt,
    sourceType: "webpage",
    title: payload.title.trim().length > 0 ? payload.title.trim() : "(untitled)",
    origin: payload.url,
    appOrSite: payload.siteName ?? extractUrlHost(payload.url) ?? payload.browser,
    extractionMethod: options.extractionMethod,
    confidence: options.extractionMethod === "browser_extension" ? 0.92 : 0.45,
    truncated,
    tokenEstimate: estimateTokens(normalizedText),
    metadata,
    captureWarnings: uniqueInOrder(warningMessages),
    summary: summaryLines.join("\n"),
    keyPoints,
    chunks,
    rawExcerpt: normalizedText.slice(0, MAX_RAW_EXCERPT_CHARS),
  };
};

const yamlQuote = (value: string): string => {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
};

export const renderNormalizedContextMarkdown = (
  context: NormalizedContext,
  payload: BrowserContextPayload,
): string => {
  const frontmatterLines: string[] = [
    "---",
    `id: ${yamlQuote(context.id)}`,
    `captured_at: ${yamlQuote(context.capturedAt)}`,
    `source_type: ${yamlQuote(context.sourceType)}`,
    `origin: ${yamlQuote(context.origin)}`,
    `title: ${yamlQuote(context.title)}`,
    `app_or_site: ${yamlQuote(context.appOrSite)}`,
    `extraction_method: ${yamlQuote(context.extractionMethod)}`,
    `confidence: ${context.confidence.toFixed(2)}`,
    `truncated: ${context.truncated ? "true" : "false"}`,
    `token_estimate: ${context.tokenEstimate}`,
    "warnings:",
  ];

  if (context.captureWarnings.length === 0) {
    frontmatterLines.push('  - ""');
  } else {
    for (const warning of context.captureWarnings) {
      frontmatterLines.push(`  - ${yamlQuote(warning)}`);
    }
  }

  frontmatterLines.push("---", "");

  const summaryBody = context.summary.length > 0 ? context.summary : "";
  const keyPointsBody =
    context.keyPoints.length > 0
      ? context.keyPoints.map((point) => `- ${point}`).join("\n")
      : "- (none)";

  const chunkBody =
    context.chunks.length > 0
      ? context.chunks
          .map((chunk) => `### ${chunk.chunkId} (tokens: ${chunk.tokenEstimate})\n${chunk.text}`)
          .join("\n\n")
      : "(none)";

  const linkBody =
    payload.links.length > 0
      ? payload.links.map((link) => `- [${link.text}](${link.href})`).join("\n")
      : "- (none)";

  const metadataEntries = Object.entries(context.metadata).sort(([left], [right]) =>
    left.localeCompare(right),
  );
  const metadataBody =
    metadataEntries.length > 0
      ? metadataEntries.map(([key, value]) => `- ${key}: ${value}`).join("\n")
      : "- (none)";

  return [
    ...frontmatterLines,
    "## Summary",
    summaryBody,
    "",
    "## Key Points",
    keyPointsBody,
    "",
    "## Content Chunks",
    chunkBody,
    "",
    "## Raw Excerpt",
    "```text",
    context.rawExcerpt,
    "```",
    "",
    "## Links & Metadata",
    "### Links",
    linkBody,
    "",
    "### Metadata",
    metadataBody,
    "",
  ].join("\n");
};
