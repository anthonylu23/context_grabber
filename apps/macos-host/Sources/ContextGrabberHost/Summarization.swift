import Foundation

private let maxLLMInputChars = 24_000
private let defaultSummaryKeyPointLimit = 8
private let briefSummaryKeyPointLimit = 5
private let summaryKeyPointCharLimit = 220

struct SummarizationSections {
  let summary: String
  let keyPoints: [String]
  let warnings: [String]
}

struct LLMSummaryRequest {
  let provider: SummarizationProvider
  let model: String
  let title: String
  let url: String
  let headings: [BrowserContextPayload.Heading]
  let fullText: String
  let summaryTokenBudget: Int
  let keyPointLimit: Int
  let timeoutMs: Int
}

struct LLMSummaryResponse {
  let summary: String
  let keyPoints: [String]
}

protocol LLMSummaryProviding {
  func summarize(_ request: LLMSummaryRequest) async throws -> LLMSummaryResponse
}

enum LLMSummaryError: LocalizedError {
  case providerNotConfigured
  case missingCredential(String)
  case invalidResponse(String)
  case transportFailure(String)

  var errorDescription: String? {
    switch self {
    case .providerNotConfigured:
      return "LLM provider is not configured."
    case .missingCredential(let provider):
      return "Missing credentials for \(provider)."
    case .invalidResponse(let message):
      return "LLM response was invalid: \(message)"
    case .transportFailure(let message):
      return "LLM transport failed: \(message)"
    }
  }
}

private struct ScoredSentence {
  let index: Int
  let sentence: String
  let score: Double
  let words: Set<String>
}

func summarizationProviderDefaultModel(_ provider: SummarizationProvider) -> String {
  switch provider {
  case .openAI:
    return "gpt-4o-mini"
  case .anthropic:
    return "claude-3-5-haiku-latest"
  case .gemini:
    return "gemini-1.5-flash"
  case .ollama:
    return "llama3.1:8b-instruct"
  }
}

func summarizationModelOptions(for provider: SummarizationProvider?) -> [String] {
  guard let provider else {
    return []
  }

  switch provider {
  case .openAI:
    return ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4.1"]
  case .anthropic:
    return ["claude-3-5-haiku-latest", "claude-3-7-sonnet-latest"]
  case .gemini:
    return ["gemini-1.5-flash", "gemini-1.5-pro"]
  case .ollama:
    return ["llama3.1:8b-instruct", "qwen2.5:7b-instruct", "mistral:7b-instruct"]
  }
}

func summarizationModelLabel(_ model: String?) -> String {
  let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  return trimmed.isEmpty ? "Auto" : trimmed
}

func resolveSummarizationSections(
  payload: BrowserContextPayload,
  settings: HostSettings,
  outputPreset: OutputFormatPreset,
  llmProvider: LLMSummaryProviding = URLSessionLLMSummaryProvider()
) async -> SummarizationSections {
  let normalizedText = sanitizeSummarizationText(payload.fullText)
  let keyPointLimit = outputPreset == .brief ? briefSummaryKeyPointLimit : defaultSummaryKeyPointLimit

  let heuristic = buildHeuristicSummarizationSections(
    text: normalizedText,
    headings: payload.headings,
    summaryTokenBudget: settings.summaryTokenBudget,
    keyPointLimit: keyPointLimit
  )

  guard settings.summarizationMode == .llm else {
    return heuristic
  }

  guard let selectedProvider = settings.summarizationProvider else {
    return appendSummarizationWarning(
      to: heuristic,
      warning: "LLM summary fallback: provider not configured."
    )
  }

  let model = settings.summarizationModel?.trimmingCharacters(in: .whitespacesAndNewlines)
  let resolvedModel = (model?.isEmpty ?? true)
    ? summarizationProviderDefaultModel(selectedProvider)
    : (model ?? summarizationProviderDefaultModel(selectedProvider))

  do {
    let llmResponse = try await llmProvider.summarize(
      LLMSummaryRequest(
        provider: selectedProvider,
        model: resolvedModel,
        title: payload.title,
        url: payload.url,
        headings: payload.headings,
        fullText: normalizedText,
        summaryTokenBudget: settings.summaryTokenBudget,
        keyPointLimit: keyPointLimit,
        timeoutMs: settings.summaryTimeoutMs
      )
    )

    let summary = trimSummaryToBudget(
      llmResponse.summary,
      summaryTokenBudget: settings.summaryTokenBudget
    )
    let keyPoints = normalizeKeyPoints(
      llmResponse.keyPoints,
      limit: keyPointLimit
    )

    guard !summary.isEmpty || !keyPoints.isEmpty else {
      throw LLMSummaryError.invalidResponse("Empty summary and key points.")
    }

    return SummarizationSections(
      summary: summary.isEmpty ? heuristic.summary : summary,
      keyPoints: keyPoints.isEmpty ? heuristic.keyPoints : keyPoints,
      warnings: []
    )
  } catch {
    let fallbackWarning = "LLM summary fallback: \(error.localizedDescription)"
    return appendSummarizationWarning(to: heuristic, warning: fallbackWarning)
  }
}

func buildHeuristicSummarizationSections(
  text: String,
  headings: [BrowserContextPayload.Heading],
  summaryTokenBudget: Int,
  keyPointLimit: Int
) -> SummarizationSections {
  let scoredSentences = scoreSentences(text, headings: headings)
  let summarySentences = selectSummarySentences(
    scoredSentences,
    summaryTokenBudget: summaryTokenBudget
  )
  let keyPoints = selectKeyPoints(
    scoredSentences,
    limit: keyPointLimit
  )

  let summary = summarySentences.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  return SummarizationSections(
    summary: summary.isEmpty ? "(none)" : summary,
    keyPoints: keyPoints,
    warnings: []
  )
}

private func appendSummarizationWarning(
  to sections: SummarizationSections,
  warning: String
) -> SummarizationSections {
  return SummarizationSections(
    summary: sections.summary,
    keyPoints: sections.keyPoints,
    warnings: uniqueInOrder(sections.warnings + [warning])
  )
}

func sanitizeSummarizationText(_ text: String) -> String {
  let normalizedLineEndings = text.replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n")
  let compactWhitespace = normalizedLineEndings.replacingOccurrences(
    of: #"[ \t]+"#,
    with: " ",
    options: .regularExpression
  )
  let compactParagraphs = compactWhitespace.replacingOccurrences(
    of: #"\n{3,}"#,
    with: "\n\n",
    options: .regularExpression
  )
  return compactParagraphs.trimmingCharacters(in: .whitespacesAndNewlines)
}

func summarizeSentences(_ text: String) -> [String] {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    return []
  }

  guard let regex = try? NSRegularExpression(pattern: #"(?<=[.!?])\s+|\n+"#) else {
    return [trimmed]
  }

  let nsText = trimmed as NSString
  let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsText.length))
  if matches.isEmpty {
    return [trimmed]
  }

  var sentences: [String] = []
  var cursor = 0
  for match in matches {
    let range = NSRange(location: cursor, length: match.range.location - cursor)
    let segment = nsText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
    if !segment.isEmpty {
      sentences.append(segment)
    }
    cursor = match.range.location + match.range.length
  }

  if cursor < nsText.length {
    let tailRange = NSRange(location: cursor, length: nsText.length - cursor)
    let tail = nsText.substring(with: tailRange).trimmingCharacters(in: .whitespacesAndNewlines)
    if !tail.isEmpty {
      sentences.append(tail)
    }
  }

  return sentences
}

private func wordTokens(_ text: String) -> [String] {
  return text
    .lowercased()
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { !$0.isEmpty }
}

private func wordSet(_ text: String) -> Set<String> {
  return Set(wordTokens(text))
}

private func scoreSentences(
  _ text: String,
  headings: [BrowserContextPayload.Heading]
) -> [ScoredSentence] {
  let sentences = summarizeSentences(text)
  guard !sentences.isEmpty else {
    return []
  }

  let headingWordSet = Set(headings.flatMap { wordTokens($0.text) })
  let sentenceCount = sentences.count

  return sentences.enumerated().map { index, sentence in
    let words = wordSet(sentence)
    let headingOverlap = words.filter { headingWordSet.contains($0) }.count
    let lengthScore = min(Double(words.count) / 24.0, 1.0)
    let headingScore = Double(min(headingOverlap, 4)) * 0.6
    let positionScore = 1.0 / Double(index + 1)
    let punctuationScore = sentence.contains(":") ? 0.2 : 0.0

    let region: Double
    if sentenceCount < 3 {
      region = 0
    } else {
      let bucket = min(2, (index * 3) / sentenceCount)
      region = bucket == 1 ? 0.05 : 0.0
    }

    return ScoredSentence(
      index: index,
      sentence: sentence,
      score: lengthScore + headingScore + positionScore + punctuationScore + region,
      words: words
    )
  }
}

private func overlapScore(_ left: Set<String>, _ right: Set<String>) -> Double {
  guard !left.isEmpty, !right.isEmpty else {
    return 0
  }

  var intersection = 0
  for word in left where right.contains(word) {
    intersection += 1
  }
  return Double(intersection) / Double(min(left.count, right.count))
}

private func sortByScoreThenIndex(_ sentences: [ScoredSentence]) -> [ScoredSentence] {
  return sentences.sorted { lhs, rhs in
    if lhs.score != rhs.score {
      return lhs.score > rhs.score
    }
    return lhs.index < rhs.index
  }
}

private func selectSummarySentences(
  _ scored: [ScoredSentence],
  summaryTokenBudget: Int
) -> [String] {
  guard !scored.isEmpty else {
    return []
  }

  let sorted = sortByScoreThenIndex(scored)
  let sentenceCount = scored.count
  var selected: [ScoredSentence] = []

  if sentenceCount >= 3 {
    for region in 0...2 {
      let regionCandidates = sorted.filter { ((($0.index * 3) / sentenceCount) == region) }
      if let first = regionCandidates.first {
        selected.append(first)
      }
    }
  }

  for candidate in sorted {
    if selected.contains(where: { $0.index == candidate.index }) {
      continue
    }
    let nearDuplicate = selected.contains { overlapScore($0.words, candidate.words) >= 0.72 }
    if nearDuplicate {
      continue
    }
    selected.append(candidate)
    if selected.count >= 8 {
      break
    }
  }

  let ordered = selected.sorted { $0.index < $1.index }
  let maxSummaryChars = max(80, summaryTokenBudget * 4)

  var lines: [String] = []
  var usedChars = 0
  for sentence in ordered {
    let normalized = sentence.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.isEmpty {
      continue
    }
    if usedChars > 0, usedChars + normalized.count + 1 > maxSummaryChars {
      break
    }
    lines.append(normalized)
    usedChars += normalized.count + 1
  }

  if lines.isEmpty, let first = ordered.first {
    return [trimSummaryToBudget(first.sentence, summaryTokenBudget: summaryTokenBudget)]
  }

  return lines
}

private func selectKeyPoints(_ scored: [ScoredSentence], limit: Int) -> [String] {
  guard !scored.isEmpty, limit > 0 else {
    return []
  }

  var selected: [ScoredSentence] = []
  for candidate in sortByScoreThenIndex(scored) {
    let nearDuplicate = selected.contains { overlapScore($0.words, candidate.words) >= 0.72 }
    if nearDuplicate {
      continue
    }
    selected.append(candidate)
    if selected.count >= limit {
      break
    }
  }

  return selected
    .sorted(by: { $0.index < $1.index })
    .map { trimKeyPoint($0.sentence) }
    .filter { !$0.isEmpty }
}

func trimSummaryToBudget(_ text: String, summaryTokenBudget: Int) -> String {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    return ""
  }

  let maxChars = max(80, summaryTokenBudget * 4)
  guard trimmed.count > maxChars else {
    return trimmed
  }

  let sentences = summarizeSentences(trimmed)
  var result: [String] = []
  var usedChars = 0
  for sentence in sentences {
    if usedChars > 0, usedChars + sentence.count + 1 > maxChars {
      break
    }
    result.append(sentence)
    usedChars += sentence.count + 1
  }

  if result.isEmpty {
    return String(trimmed.prefix(maxChars)).trimmingCharacters(in: .whitespacesAndNewlines)
  }
  return result.joined(separator: "\n")
}

private func trimKeyPoint(_ value: String) -> String {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    return ""
  }

  if trimmed.count <= summaryKeyPointCharLimit {
    return trimmed
  }

  let prefix = String(trimmed.prefix(summaryKeyPointCharLimit - 1))
  return "\(prefix)…"
}

private func normalizeKeyPoints(_ values: [String], limit: Int) -> [String] {
  let normalized = values
    .map { trimKeyPoint($0) }
    .filter { !$0.isEmpty }
  return Array(uniqueInOrder(normalized).prefix(max(1, limit)))
}

private func uniqueInOrder(_ values: [String]) -> [String] {
  var seen = Set<String>()
  var unique: [String] = []
  for value in values {
    if seen.contains(value) {
      continue
    }
    seen.insert(value)
    unique.append(value)
  }
  return unique
}

private struct ParsedLLMResult: Decodable {
  let summary: String
  let keyPoints: [String]

  enum CodingKeys: String, CodingKey {
    case summary
    case keyPoints
    case key_points
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
    if let camel = try? container.decode([String].self, forKey: .keyPoints) {
      keyPoints = camel
    } else if let snake = try? container.decode([String].self, forKey: .key_points) {
      keyPoints = snake
    } else {
      keyPoints = []
    }
  }
}

private func extractJSONPayload(_ raw: String) -> String? {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else {
    return nil
  }

  if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
    return trimmed
  }

  let withoutFence = trimmed
    .replacingOccurrences(of: "```json", with: "")
    .replacingOccurrences(of: "```", with: "")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if withoutFence.hasPrefix("{"), withoutFence.hasSuffix("}") {
    return withoutFence
  }

  guard let first = withoutFence.firstIndex(of: "{"),
    let last = withoutFence.lastIndex(of: "}"),
    first < last
  else {
    return nil
  }
  return String(withoutFence[first...last])
}

private func parseLLMSummary(raw: String) throws -> LLMSummaryResponse {
  guard let payload = extractJSONPayload(raw) else {
    throw LLMSummaryError.invalidResponse("No JSON object found.")
  }
  let data = Data(payload.utf8)
  let decoded = try JSONDecoder().decode(ParsedLLMResult.self, from: data)
  return LLMSummaryResponse(
    summary: decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines),
    keyPoints: decoded.keyPoints
  )
}

private func summarizePrompt(for request: LLMSummaryRequest) -> String {
  let headingText = request.headings
    .prefix(12)
    .map { "- h\($0.level): \($0.text)" }
    .joined(separator: "\n")
  let trimmedText = String(request.fullText.prefix(maxLLMInputChars))
  return """
  Produce a concise summary for captured context.
  Return ONLY valid JSON with this schema:
  {"summary":"string","keyPoints":["string"]}

  Constraints:
  - summary should be high coverage and brief
  - summary token target: ~\(request.summaryTokenBudget)
  - keyPoints count: at most \(request.keyPointLimit)
  - no markdown code fences
  - no extra keys

  Title: \(request.title)
  URL/Origin: \(request.url)
  Headings:
  \(headingText.isEmpty ? "- (none)" : headingText)

  Content:
  \(trimmedText)
  """
}

struct URLSessionLLMSummaryProvider: LLMSummaryProviding {
  func summarize(_ request: LLMSummaryRequest) async throws -> LLMSummaryResponse {
    let prompt = summarizePrompt(for: request)
    let rawResponse: String

    switch request.provider {
    case .openAI:
      rawResponse = try await requestOpenAISummary(prompt: prompt, request: request)
    case .anthropic:
      rawResponse = try await requestAnthropicSummary(prompt: prompt, request: request)
    case .gemini:
      rawResponse = try await requestGeminiSummary(prompt: prompt, request: request)
    case .ollama:
      rawResponse = try await requestOllamaSummary(prompt: prompt, request: request)
    }

    return try parseLLMSummary(raw: rawResponse)
  }
}

private func requestOpenAISummary(prompt: String, request: LLMSummaryRequest) async throws -> String {
  guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
    throw LLMSummaryError.missingCredential("OpenAI")
  }

  let base = ProcessInfo.processInfo.environment["OPENAI_BASE_URL"] ?? "https://api.openai.com"
  guard let url = URL(string: "\(base)/v1/chat/completions") else {
    throw LLMSummaryError.transportFailure("Invalid OpenAI URL.")
  }

  let body: [String: Any] = [
    "model": request.model,
    "temperature": 0,
    "response_format": ["type": "json_object"],
    "messages": [
      ["role": "system", "content": "You summarize captured app/browser context into compact JSON."],
      ["role": "user", "content": prompt],
    ],
  ]

  let data = try await sendJSONRequest(
    url: url,
    timeoutMs: request.timeoutMs,
    headers: [
      "Authorization": "Bearer \(key)",
      "Content-Type": "application/json",
    ],
    body: body
  )

  struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        let content: String
      }
      let message: Message
    }
    let choices: [Choice]
  }

  let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
  guard let content = decoded.choices.first?.message.content else {
    throw LLMSummaryError.invalidResponse("OpenAI choices were empty.")
  }
  return content
}

private func requestAnthropicSummary(prompt: String, request: LLMSummaryRequest) async throws -> String {
  guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
    throw LLMSummaryError.missingCredential("Anthropic")
  }

  let base = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? "https://api.anthropic.com"
  guard let url = URL(string: "\(base)/v1/messages") else {
    throw LLMSummaryError.transportFailure("Invalid Anthropic URL.")
  }

  let body: [String: Any] = [
    "model": request.model,
    "max_tokens": 600,
    "temperature": 0,
    "system": "You summarize captured app/browser context into compact JSON.",
    "messages": [
      ["role": "user", "content": prompt]
    ],
  ]

  let data = try await sendJSONRequest(
    url: url,
    timeoutMs: request.timeoutMs,
    headers: [
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    ],
    body: body
  )

  struct AnthropicResponse: Decodable {
    struct Content: Decodable {
      let type: String
      let text: String?
    }
    let content: [Content]
  }

  let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
  guard let text = decoded.content.first(where: { $0.type == "text" })?.text else {
    throw LLMSummaryError.invalidResponse("Anthropic text content missing.")
  }
  return text
}

private func requestGeminiSummary(prompt: String, request: LLMSummaryRequest) async throws -> String {
  let env = ProcessInfo.processInfo.environment
  let key = env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"] ?? ""
  guard !key.isEmpty else {
    throw LLMSummaryError.missingCredential("Gemini")
  }

  let base = env["GEMINI_BASE_URL"] ?? "https://generativelanguage.googleapis.com"
  guard let encodedModel = request.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
    let url = URL(string: "\(base)/v1beta/models/\(encodedModel):generateContent?key=\(key)")
  else {
    throw LLMSummaryError.transportFailure("Invalid Gemini URL.")
  }

  let body: [String: Any] = [
    "contents": [
      ["parts": [["text": prompt]]]
    ],
    "generationConfig": [
      "temperature": 0,
      "responseMimeType": "application/json",
    ],
  ]

  let data = try await sendJSONRequest(
    url: url,
    timeoutMs: request.timeoutMs,
    headers: ["Content-Type": "application/json"],
    body: body
  )

  struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
      struct Content: Decodable {
        struct Part: Decodable {
          let text: String?
        }
        let parts: [Part]?
      }
      let content: Content?
    }
    let candidates: [Candidate]?
  }

  let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
  guard let text = decoded.candidates?.first?.content?.parts?.first?.text else {
    throw LLMSummaryError.invalidResponse("Gemini content missing.")
  }
  return text
}

private func requestOllamaSummary(prompt: String, request: LLMSummaryRequest) async throws -> String {
  let base = ProcessInfo.processInfo.environment["OLLAMA_BASE_URL"] ?? "http://localhost:11434"
  guard let url = URL(string: "\(base)/api/chat") else {
    throw LLMSummaryError.transportFailure("Invalid Ollama URL.")
  }

  let body: [String: Any] = [
    "model": request.model,
    "stream": false,
    "format": "json",
    "messages": [
      ["role": "system", "content": "You summarize captured app/browser context into compact JSON."],
      ["role": "user", "content": prompt],
    ],
  ]

  let data = try await sendJSONRequest(
    url: url,
    timeoutMs: request.timeoutMs,
    headers: ["Content-Type": "application/json"],
    body: body
  )

  struct OllamaResponse: Decodable {
    struct Message: Decodable {
      let content: String
    }
    let message: Message?
  }

  let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
  guard let content = decoded.message?.content else {
    throw LLMSummaryError.invalidResponse("Ollama message content missing.")
  }
  return content
}

private func sendJSONRequest(
  url: URL,
  timeoutMs: Int,
  headers: [String: String],
  body: [String: Any]
) async throws -> Data {
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.timeoutInterval = TimeInterval(max(1, timeoutMs)) / 1000.0
  for (key, value) in headers {
    request.setValue(value, forHTTPHeaderField: key)
  }
  request.httpBody = try JSONSerialization.data(withJSONObject: body)

  let (data, response): (Data, URLResponse)
  do {
    (data, response) = try await URLSession.shared.data(for: request)
  } catch {
    throw LLMSummaryError.transportFailure(error.localizedDescription)
  }

  guard let httpResponse = response as? HTTPURLResponse else {
    throw LLMSummaryError.transportFailure("No HTTP response.")
  }
  guard (200...299).contains(httpResponse.statusCode) else {
    let snippet = String(data: data.prefix(400), encoding: .utf8) ?? ""
    throw LLMSummaryError.transportFailure(
      "status \(httpResponse.statusCode)\(snippet.isEmpty ? "" : ": \(snippet)")"
    )
  }

  return data
}
