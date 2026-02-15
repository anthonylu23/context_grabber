import Foundation

func isoTimestamp() -> String {
  return ISO8601DateFormatter().string(from: Date())
}

func renderMarkdown(
  requestID: String,
  capturedAt: String,
  extractionMethod: String,
  payload: BrowserContextPayload
) -> String {
  let isDesktopSource = payload.source == "desktop"
  let normalizedText = payload.fullText.replacingOccurrences(of: "\r\n", with: "\n")
  let trimmedText = String(normalizedText.prefix(maxBrowserFullTextChars))
  let truncated = normalizedText.count > maxBrowserFullTextChars

  let summary = buildSummary(from: trimmedText)
  let keyPoints = buildKeyPoints(from: trimmedText)
  let chunks = buildChunks(from: trimmedText)
  let rawExcerpt = String(trimmedText.prefix(maxRawExcerptChars))

  let warnings = (payload.extractionWarnings ?? [])
    + (truncated ? ["Capture truncated at \(maxBrowserFullTextChars) chars."] : [])
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
  lines.append("## Summary")
  lines.append(summary)
  lines.append("")
  lines.append("## Key Points")
  if keyPoints.isEmpty {
    lines.append("- (none)")
  } else {
    keyPoints.forEach { point in
      lines.append("- \(point)")
    }
  }

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
  lines.append("")
  lines.append("## Links & Metadata")
  lines.append("### Links")
  if payload.links.isEmpty {
    lines.append("- (none)")
  } else {
    payload.links.forEach { link in
      lines.append("- [\(link.text)](\(link.href))")
    }
  }

  lines.append("")
  lines.append("### Metadata")
  if isDesktopSource {
    lines.append("- source: desktop")
    lines.append("- app_name: \(payload.title)")
    lines.append("- app_bundle_id: \(desktopBundleIdentifierFromOrigin(payload.url) ?? "unknown")")
  } else {
    lines.append("- browser: \(payload.browser)")
    lines.append("- url: \(payload.url)")
    if let language = payload.language {
      lines.append("- language: \(language)")
    }
    if let author = payload.author {
      lines.append("- author: \(author)")
    }
  }

  lines.append("")
  return lines.joined(separator: "\n")
}

func buildSummary(from text: String) -> String {
  let sentences = splitSentences(text)
  if sentences.isEmpty {
    return ""
  }

  return sentences.prefix(6).joined(separator: "\n")
}

func buildKeyPoints(from text: String) -> [String] {
  let sentences = splitSentences(text)
  return Array(sentences.prefix(8))
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

func splitSentences(_ text: String) -> [String] {
  let parts = text.split(separator: ".")
  return parts
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .map { "\($0)." }
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

func yamlQuoted(_ value: String) -> String {
  let escaped = value
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")

  return "\"\(escaped)\""
}
