import Foundation

private enum HostSettingsKeys {
  static let outputDirectoryPath = "context_grabber.output_directory_path"
  static let retentionMaxFileCount = "context_grabber.retention_max_file_count"
  static let retentionMaxAgeDays = "context_grabber.retention_max_age_days"
  static let capturesPausedPlaceholder = "context_grabber.captures_paused_placeholder"
  static let clipboardCopyMode = "context_grabber.clipboard_copy_mode"
  static let outputFormatPreset = "context_grabber.output_format_preset"
  static let includeProductContextLine = "context_grabber.include_product_context_line"
  static let summarizationMode = "context_grabber.summarization_mode"
  static let summarizationProvider = "context_grabber.summarization_provider"
  static let summarizationModel = "context_grabber.summarization_model"
  static let summaryTokenBudget = "context_grabber.summary_token_budget"
  static let summaryTimeoutMs = "context_grabber.summary_timeout_ms"
}

enum ClipboardCopyMode: String, CaseIterable {
  case markdownFile = "markdown_file"
  case text = "text"
}

enum OutputFormatPreset: String, CaseIterable {
  case brief = "brief"
  case full = "full"
}

enum SummarizationMode: String, CaseIterable {
  case heuristic = "heuristic"
  case llm = "llm"
}

enum SummarizationProvider: String, CaseIterable {
  case openAI = "openai"
  case anthropic = "anthropic"
  case gemini = "gemini"
  case ollama = "ollama"
}

struct HostSettings {
  static let defaultRetentionMaxFileCount = 200
  static let defaultRetentionMaxAgeDays = 30
  static let defaultClipboardCopyMode: ClipboardCopyMode = .markdownFile
  static let defaultOutputFormatPreset: OutputFormatPreset = .full
  static let defaultIncludeProductContextLine = true
  static let defaultSummarizationMode: SummarizationMode = .heuristic
  static let defaultSummaryTokenBudget = 120
  static let defaultSummaryTimeoutMs = 2_500

  var outputDirectoryPath: String?
  var retentionMaxFileCount: Int
  var retentionMaxAgeDays: Int
  var capturesPausedPlaceholder: Bool
  var clipboardCopyMode: ClipboardCopyMode
  var outputFormatPreset: OutputFormatPreset
  var includeProductContextLine: Bool
  var summarizationMode: SummarizationMode
  var summarizationProvider: SummarizationProvider?
  var summarizationModel: String?
  var summaryTokenBudget: Int
  var summaryTimeoutMs: Int

  var outputDirectoryURL: URL? {
    guard let outputDirectoryPath else {
      return nil
    }
    let trimmed = outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: trimmed, isDirectory: true)
  }
}

let retentionMaxFileCountOptions: [Int] = [50, 100, 200, 500, 0]
let retentionMaxAgeDaysOptions: [Int] = [7, 30, 90, 0]
let summaryTokenBudgetOptions: [Int] = [80, 120, 180]

struct HostRetentionPolicy {
  let maxFileCount: Int
  let maxFileAgeDays: Int
}

private let captureFrontmatterRequiredKeys: Set<String> = [
  "id",
  "captured_at",
  "source_type",
  "extraction_method",
]
private let captureFrontmatterScanLineLimit = 120

func retentionMaxFileCountLabel(_ value: Int) -> String {
  if value <= 0 {
    return "Unlimited"
  }
  return "\(value)"
}

func retentionMaxAgeDaysLabel(_ value: Int) -> String {
  if value <= 0 {
    return "Unlimited"
  }
  return "\(value) days"
}

func loadHostSettings(userDefaults: UserDefaults = .standard) -> HostSettings {
  let storedCount = userDefaults.object(forKey: HostSettingsKeys.retentionMaxFileCount) as? Int
  let storedAge = userDefaults.object(forKey: HostSettingsKeys.retentionMaxAgeDays) as? Int
  let outputDirectoryPath = userDefaults.string(forKey: HostSettingsKeys.outputDirectoryPath)
  let capturesPaused = userDefaults.bool(forKey: HostSettingsKeys.capturesPausedPlaceholder)
  let storedClipboardCopyMode = userDefaults.string(forKey: HostSettingsKeys.clipboardCopyMode)
  let storedOutputFormatPreset = userDefaults.string(forKey: HostSettingsKeys.outputFormatPreset)
  let includeProductContextStored = userDefaults.object(
    forKey: HostSettingsKeys.includeProductContextLine
  ) as? Bool
  let storedSummarizationMode = userDefaults.string(forKey: HostSettingsKeys.summarizationMode)
  let storedSummarizationProvider = userDefaults.string(forKey: HostSettingsKeys.summarizationProvider)
  let storedSummarizationModel = userDefaults.string(forKey: HostSettingsKeys.summarizationModel)
  let storedSummaryTokenBudget = userDefaults.object(forKey: HostSettingsKeys.summaryTokenBudget) as? Int
  let storedSummaryTimeoutMs = userDefaults.object(forKey: HostSettingsKeys.summaryTimeoutMs) as? Int

  let retentionMaxFileCount = sanitizeRetentionValue(
    storedCount,
    fallback: HostSettings.defaultRetentionMaxFileCount
  )
  let retentionMaxAgeDays = sanitizeRetentionValue(
    storedAge,
    fallback: HostSettings.defaultRetentionMaxAgeDays
  )
  let clipboardCopyMode = ClipboardCopyMode(rawValue: storedClipboardCopyMode ?? "")
    ?? HostSettings.defaultClipboardCopyMode
  let outputFormatPreset = OutputFormatPreset(rawValue: storedOutputFormatPreset ?? "")
    ?? HostSettings.defaultOutputFormatPreset
  let includeProductContextLine =
    includeProductContextStored ?? HostSettings.defaultIncludeProductContextLine
  var summarizationMode = SummarizationMode(rawValue: storedSummarizationMode ?? "")
    ?? HostSettings.defaultSummarizationMode
  let summarizationProvider = SummarizationProvider(rawValue: storedSummarizationProvider ?? "")
  let summaryTokenBudget = sanitizeSummaryTokenBudget(
    storedSummaryTokenBudget,
    fallback: HostSettings.defaultSummaryTokenBudget
  )
  let summaryTimeoutMs = sanitizeSummaryTimeoutMs(
    storedSummaryTimeoutMs,
    fallback: HostSettings.defaultSummaryTimeoutMs
  )
  let summarizationModel = storedSummarizationModel?
    .trimmingCharacters(in: .whitespacesAndNewlines)
  if summarizationMode == .llm, summarizationProvider == nil {
    summarizationMode = .heuristic
  }

  return HostSettings(
    outputDirectoryPath: outputDirectoryPath,
    retentionMaxFileCount: retentionMaxFileCount,
    retentionMaxAgeDays: retentionMaxAgeDays,
    capturesPausedPlaceholder: capturesPaused,
    clipboardCopyMode: clipboardCopyMode,
    outputFormatPreset: outputFormatPreset,
    includeProductContextLine: includeProductContextLine,
    summarizationMode: summarizationMode,
    summarizationProvider: summarizationProvider,
    summarizationModel: (summarizationModel?.isEmpty ?? true) ? nil : summarizationModel,
    summaryTokenBudget: summaryTokenBudget,
    summaryTimeoutMs: summaryTimeoutMs
  )
}

func saveHostSettings(
  _ settings: HostSettings,
  userDefaults: UserDefaults = .standard
) {
  if let outputDirectoryPath = settings.outputDirectoryPath?.trimmingCharacters(in: .whitespacesAndNewlines),
    !outputDirectoryPath.isEmpty
  {
    userDefaults.set(outputDirectoryPath, forKey: HostSettingsKeys.outputDirectoryPath)
  } else {
    userDefaults.removeObject(forKey: HostSettingsKeys.outputDirectoryPath)
  }

  userDefaults.set(settings.retentionMaxFileCount, forKey: HostSettingsKeys.retentionMaxFileCount)
  userDefaults.set(settings.retentionMaxAgeDays, forKey: HostSettingsKeys.retentionMaxAgeDays)
  userDefaults.set(settings.capturesPausedPlaceholder, forKey: HostSettingsKeys.capturesPausedPlaceholder)
  userDefaults.set(settings.clipboardCopyMode.rawValue, forKey: HostSettingsKeys.clipboardCopyMode)
  userDefaults.set(settings.outputFormatPreset.rawValue, forKey: HostSettingsKeys.outputFormatPreset)
  userDefaults.set(
    settings.includeProductContextLine,
    forKey: HostSettingsKeys.includeProductContextLine
  )
  userDefaults.set(settings.summarizationMode.rawValue, forKey: HostSettingsKeys.summarizationMode)
  if let summarizationProvider = settings.summarizationProvider {
    userDefaults.set(summarizationProvider.rawValue, forKey: HostSettingsKeys.summarizationProvider)
  } else {
    userDefaults.removeObject(forKey: HostSettingsKeys.summarizationProvider)
  }
  if let summarizationModel = settings.summarizationModel?.trimmingCharacters(in: .whitespacesAndNewlines),
    !summarizationModel.isEmpty
  {
    userDefaults.set(summarizationModel, forKey: HostSettingsKeys.summarizationModel)
  } else {
    userDefaults.removeObject(forKey: HostSettingsKeys.summarizationModel)
  }
  userDefaults.set(settings.summaryTokenBudget, forKey: HostSettingsKeys.summaryTokenBudget)
  userDefaults.set(settings.summaryTimeoutMs, forKey: HostSettingsKeys.summaryTimeoutMs)
}

func clipboardCopyModeLabel(_ mode: ClipboardCopyMode) -> String {
  switch mode {
  case .markdownFile:
    return "Markdown File"
  case .text:
    return "Text"
  }
}

func outputFormatPresetLabel(_ preset: OutputFormatPreset) -> String {
  switch preset {
  case .brief:
    return "Brief"
  case .full:
    return "Full"
  }
}

func summarizationModeLabel(_ mode: SummarizationMode) -> String {
  switch mode {
  case .heuristic:
    return "Heuristic"
  case .llm:
    return "LLM"
  }
}

func summarizationProviderLabel(_ provider: SummarizationProvider?) -> String {
  guard let provider else {
    return "Not Set"
  }

  switch provider {
  case .openAI:
    return "OpenAI"
  case .anthropic:
    return "Anthropic"
  case .gemini:
    return "Gemini"
  case .ollama:
    return "Ollama"
  }
}

func sanitizeSummaryTokenBudget(_ value: Int?, fallback: Int) -> Int {
  guard let value, summaryTokenBudgetOptions.contains(value) else {
    return fallback
  }
  return value
}

func sanitizeSummaryTimeoutMs(_ value: Int?, fallback: Int) -> Int {
  guard let value, value >= 500, value <= 20_000 else {
    return fallback
  }
  return value
}

func retentionPruneCandidates(
  files: [URL],
  policy: HostRetentionPolicy,
  now: Date = Date(),
  modifiedDate: (URL) -> Date?
) -> [URL] {
  let sortedFiles = files.sorted { lhs, rhs in
    let lhsDate = modifiedDate(lhs)
    let rhsDate = modifiedDate(rhs)

    switch (lhsDate, rhsDate) {
    case let (l?, r?):
      if l != r {
        return l > r
      }
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      break
    }

    return lhs.lastPathComponent > rhs.lastPathComponent
  }

  var candidates = sortedFiles
  var pruneSet = Set<URL>()

  if policy.maxFileAgeDays > 0 {
    let maxAgeSeconds = TimeInterval(policy.maxFileAgeDays * 86_400)
    candidates = candidates.filter { fileURL in
      guard let fileDate = modifiedDate(fileURL) else {
        return true
      }
      let ageSeconds = now.timeIntervalSince(fileDate)
      if ageSeconds > maxAgeSeconds {
        pruneSet.insert(fileURL)
        return false
      }
      return true
    }
  }

  if policy.maxFileCount > 0, candidates.count > policy.maxFileCount {
    for fileURL in candidates.dropFirst(policy.maxFileCount) {
      pruneSet.insert(fileURL)
    }
  }

  return sortedFiles.filter { pruneSet.contains($0) }
}

func isHostGeneratedCaptureFilename(_ filename: String) -> Bool {
  guard filename.hasSuffix(".md") else {
    return false
  }

  let stem = URL(fileURLWithPath: filename, isDirectory: false)
    .deletingPathExtension()
    .lastPathComponent
  let parts = stem.split(separator: "-")
  guard parts.count == 3 else {
    return false
  }

  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyyMMdd-HHmmss"
  let timestamp = "\(parts[0])-\(parts[1])"
  guard formatter.date(from: timestamp) != nil else {
    return false
  }

  let suffix = String(parts[2])
  guard (8...64).contains(suffix.count) else {
    return false
  }
  guard suffix.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
    return false
  }

  return true
}

func hasRequiredCaptureFrontmatter(_ markdown: String) -> Bool {
  guard let frontmatter = parseMarkdownFrontmatter(markdown) else {
    return false
  }

  for key in captureFrontmatterRequiredKeys {
    guard let value = frontmatter[key], !value.isEmpty else {
      return false
    }
  }

  return true
}

func isHostGeneratedCaptureFile(
  _ fileURL: URL,
  readMarkdown: (URL) -> String? = defaultReadMarkdown
) -> Bool {
  guard isHostGeneratedCaptureFilename(fileURL.lastPathComponent) else {
    return false
  }
  guard let markdown = readMarkdown(fileURL) else {
    return false
  }
  return hasRequiredCaptureFrontmatter(markdown)
}

func filterHostGeneratedCaptureFiles(
  _ files: [URL],
  readMarkdown: (URL) -> String? = defaultReadMarkdown
) -> [URL] {
  return files.filter { fileURL in
    isHostGeneratedCaptureFile(fileURL, readMarkdown: readMarkdown)
  }
}

func recentHostCaptureFiles(
  _ files: [URL],
  limit: Int,
  readMarkdown: (URL) -> String? = defaultReadMarkdown
) -> [URL] {
  return filterHostGeneratedCaptureFiles(files, readMarkdown: readMarkdown)
    .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
    .prefix(max(0, limit))
    .map { $0 }
}

func outputDirectoryValidationError(
  _ directoryURL: URL,
  writableCheck: (URL) -> Bool = { isDirectoryWritable($0) }
) -> String? {
  let normalizedURL = directoryURL.standardizedFileURL
  guard writableCheck(normalizedURL) else {
    return "Selected output directory is not writable."
  }
  return nil
}

func isDirectoryWritable(
  _ directoryURL: URL,
  ensureDirectory: (URL) throws -> Void = defaultEnsureDirectory,
  writeProbe: (Data, URL) throws -> Void = defaultWriteProbe,
  removeProbe: (URL) throws -> Void = defaultRemoveProbe,
  makeProbeURL: (URL) -> URL = defaultProbeURL
) -> Bool {
  do {
    try ensureDirectory(directoryURL)
  } catch {
    return false
  }

  let probeURL = makeProbeURL(directoryURL)
  let probeData = Data("context-grabber-write-probe".utf8)

  do {
    try writeProbe(probeData, probeURL)
    try removeProbe(probeURL)
  } catch {
    try? removeProbe(probeURL)
    return false
  }

  return true
}

func defaultEnsureDirectory(_ directoryURL: URL) throws {
  try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
}

func defaultWriteProbe(_ data: Data, _ fileURL: URL) throws {
  try data.write(to: fileURL, options: .atomic)
}

func defaultRemoveProbe(_ fileURL: URL) throws {
  try FileManager.default.removeItem(at: fileURL)
}

func defaultProbeURL(_ directoryURL: URL) -> URL {
  return directoryURL.appendingPathComponent(
    ".context-grabber-write-test-\(UUID().uuidString.lowercased())",
    isDirectory: false
  )
}

func defaultReadMarkdown(_ fileURL: URL) -> String? {
  return try? String(contentsOf: fileURL, encoding: .utf8)
}

private func parseMarkdownFrontmatter(_ markdown: String) -> [String: String]? {
  let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
  guard let first = lines.first, String(first).trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
    return nil
  }

  var frontmatter: [String: String] = [:]
  var foundTerminator = false

  for rawLine in lines.dropFirst().prefix(captureFrontmatterScanLineLimit) {
    let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
    if line == "---" {
      foundTerminator = true
      break
    }
    guard !line.isEmpty, let colonIndex = line.firstIndex(of: ":") else {
      continue
    }

    let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !key.isEmpty else {
      continue
    }

    var value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
      value.removeFirst()
      value.removeLast()
    }
    frontmatter[key] = value
  }

  return foundTerminator ? frontmatter : nil
}

private func sanitizeRetentionValue(_ value: Int?, fallback: Int) -> Int {
  guard let value else {
    return fallback
  }
  return value < 0 ? fallback : value
}
