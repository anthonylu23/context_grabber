import Foundation

private let productContextSummary =
  "Context Grabber captures focused browser tabs or desktop apps into structured markdown for AI workflows."
private let briefKeyPointLimit = 5
private let briefLinkLimit = 5

func isoTimestamp() -> String {
  return ISO8601DateFormatter().string(from: Date())
}

func renderMarkdown(
  requestID: String,
  capturedAt: String,
  extractionMethod: String,
  payload: BrowserContextPayload,
  outputPreset: OutputFormatPreset = HostSettings.defaultOutputFormatPreset,
  includeProductContextLine: Bool = HostSettings.defaultIncludeProductContextLine,
  summaryOverride: String? = nil,
  keyPointsOverride: [String]? = nil,
  additionalWarnings: [String] = [],
  summaryTokenBudget: Int = HostSettings.defaultSummaryTokenBudget
) -> String {
  let isDesktopSource = payload.source == "desktop"
  let normalizedText = payload.fullText.replacingOccurrences(of: "\r\n", with: "\n")
  let trimmedText = String(normalizedText.prefix(maxBrowserFullTextChars))
  let truncated = normalizedText.count > maxBrowserFullTextChars

  let heuristicSections = buildHeuristicSummarizationSections(
    text: sanitizeSummarizationText(trimmedText),
    headings: payload.headings,
    summaryTokenBudget: summaryTokenBudget,
    keyPointLimit: outputPreset == .brief ? briefKeyPointLimit : 8
  )
  let summaryOverrideValue = summaryOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
  let summary: String
  if let override = summaryOverrideValue, !override.isEmpty {
    summary = override
  } else {
    summary = heuristicSections.summary
  }
  let keyPoints: [String]
  if let override = keyPointsOverride, !override.isEmpty {
    keyPoints = override
  } else {
    keyPoints = heuristicSections.keyPoints
  }
  let chunks = buildChunks(from: trimmedText)
  let rawExcerpt = String(trimmedText.prefix(maxRawExcerptChars))

  let warnings = uniqueWarningLines(
    (payload.extractionWarnings ?? [])
      + additionalWarnings
      + (truncated ? ["Capture truncated at \(maxBrowserFullTextChars) chars."] : [])
  )
  let tokenEstimate = max(1, Int(ceil(Double(trimmedText.count) / 4.0)))

  var lines: [String] = []
  lines.append("---")
  lines.append("id: \(yamlQuoted(requestID))")
  lines.append("captured_at: \(yamlQuoted(capturedAt))")
  lines.append("source_type: \(yamlQuoted(isDesktopSource ? "desktop_app" : "webpage"))")
  lines.append("origin: \(yamlQuoted(payload.url))")
  lines.append("title: \(yamlQuoted(payload.title))")
  lines.append(
    "app_or_site: \(yamlQuoted(isDesktopSource ? (payload.siteName ?? payload.title) : (payload.siteName ?? hostFromURL(payload.url) ?? payload.browser)))"
  )
  lines.append("extraction_method: \(yamlQuoted(extractionMethod))")
  lines.append("confidence: 0.92")
  lines.append("truncated: \(truncated ? "true" : "false")")
  lines.append("token_estimate: \(tokenEstimate)")
  lines.append("warnings:")

  if warnings.isEmpty {
    lines.append("  - \(yamlQuoted(""))")
  } else {
    warnings.forEach { warning in
      lines.append("  - \(yamlQuoted(warning))")
    }
  }

  lines.append("---")
  lines.append("")
  if includeProductContextLine {
    lines.append("## Product Context")
    lines.append(productContextSummary)
    lines.append("")
  }
  lines.append("## Summary")
  lines.append(summary.isEmpty ? "(none)" : summary)
  lines.append("")
  lines.append("## Key Points")
  let keyPointsForPreset =
    outputPreset == .brief ? Array(keyPoints.prefix(briefKeyPointLimit)) : keyPoints
  if keyPointsForPreset.isEmpty {
    lines.append("- (none)")
  } else {
    keyPointsForPreset.forEach { point in
      lines.append("- \(point)")
    }
  }

  if outputPreset == .full {
    lines.append("")
    lines.append("## Content Chunks")
    if chunks.isEmpty {
      lines.append("(none)")
    } else {
      chunks.enumerated().forEach { index, chunk in
        lines.append("### chunk-\(String(format: "%03d", index + 1))")
        lines.append(chunk)
        lines.append("")
      }
    }
    lines.append("## Raw Excerpt")
    lines.append("```text")
    lines.append(rawExcerpt)
    lines.append("```")
  }
  lines.append("")
  lines.append("## Links & Metadata")
  lines.append("### Links")
  let linksForPreset: [BrowserContextPayload.Link]
  if outputPreset == .brief {
    linksForPreset = Array(payload.links.prefix(briefLinkLimit))
  } else {
    linksForPreset = payload.links
  }
  if linksForPreset.isEmpty {
    lines.append("- (none)")
  } else {
    linksForPreset.forEach { link in
      lines.append("- [\(link.text)](\(link.href))")
    }
    if outputPreset == .brief, payload.links.count > briefLinkLimit {
      lines.append("- (\(payload.links.count - briefLinkLimit) additional links omitted)")
    }
  }

  lines.append("")
  lines.append("### Metadata")
  metadataLines(
    payload: payload,
    isDesktopSource: isDesktopSource,
    outputPreset: outputPreset
  ).forEach { line in
    lines.append(line)
  }

  lines.append("")
  return lines.joined(separator: "\n")
}

func buildSummary(from text: String) -> String {
  let sections = buildHeuristicSummarizationSections(
    text: sanitizeSummarizationText(text),
    headings: [],
    summaryTokenBudget: HostSettings.defaultSummaryTokenBudget,
    keyPointLimit: 6
  )
  return sections.summary
}

func buildKeyPoints(from text: String) -> [String] {
  let sections = buildHeuristicSummarizationSections(
    text: sanitizeSummarizationText(text),
    headings: [],
    summaryTokenBudget: HostSettings.defaultSummaryTokenBudget,
    keyPointLimit: 8
  )
  return sections.keyPoints
}

func buildChunks(from text: String) -> [String] {
  let paragraphs = text
    .components(separatedBy: "\n\n")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

  var chunks: [String] = []
  var currentChunk: [String] = []
  var currentTokens = 0

  for paragraph in paragraphs {
    let paragraphTokens = max(1, Int(ceil(Double(paragraph.count) / 4.0)))
    if currentTokens > 0 && currentTokens + paragraphTokens > 1500 {
      chunks.append(currentChunk.joined(separator: "\n\n"))
      currentChunk = []
      currentTokens = 0
    }

    currentChunk.append(paragraph)
    currentTokens += paragraphTokens
  }

  if !currentChunk.isEmpty {
    chunks.append(currentChunk.joined(separator: "\n\n"))
  }

  return chunks
}

func uniqueWarningLines(_ warnings: [String]) -> [String] {
  var seen = Set<String>()
  var unique: [String] = []
  for warning in warnings {
    let normalized = warning.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      continue
    }
    if seen.contains(normalized) {
      continue
    }
    seen.insert(normalized)
    unique.append(normalized)
  }
  return unique
}

func hostFromURL(_ urlString: String) -> String? {
  guard let url = URL(string: urlString) else {
    return nil
  }

  return url.host
}

func desktopBundleIdentifierFromOrigin(_ origin: String) -> String? {
  guard let url = URL(string: origin) else {
    return nil
  }

  guard url.scheme == "app" else {
    return nil
  }

  return url.host
}

func metadataLines(
  payload: BrowserContextPayload,
  isDesktopSource: Bool,
  outputPreset: OutputFormatPreset
) -> [String] {
  if isDesktopSource {
    return [
      "- source: desktop",
      "- app_name: \(payload.title)",
      "- app_bundle_id: \(desktopBundleIdentifierFromOrigin(payload.url) ?? "unknown")",
    ]
  }

  var lines: [String] = [
    "- browser: \(payload.browser)",
    "- url: \(payload.url)",
  ]

  if let language = payload.language {
    lines.append("- language: \(language)")
  }

  guard outputPreset == .full else {
    return lines
  }

  if let author = payload.author {
    lines.append("- author: \(author)")
  }
  if let siteName = payload.siteName {
    lines.append("- site_name: \(siteName)")
  }
  if let metaDescription = payload.metaDescription {
    lines.append("- meta_description: \(metaDescription)")
  }
  if let publishedTime = payload.publishedTime {
    lines.append("- published_time: \(publishedTime)")
  }

  return lines
}

func yamlQuoted(_ value: String) -> String {
  let escaped = value
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")

  return "\"\(escaped)\""
}
