import Foundation

private enum HostSettingsKeys {
  static let outputDirectoryPath = "context_grabber.output_directory_path"
  static let retentionMaxFileCount = "context_grabber.retention_max_file_count"
  static let retentionMaxAgeDays = "context_grabber.retention_max_age_days"
  static let capturesPausedPlaceholder = "context_grabber.captures_paused_placeholder"
}

struct HostSettings {
  static let defaultRetentionMaxFileCount = 200
  static let defaultRetentionMaxAgeDays = 30

  var outputDirectoryPath: String?
  var retentionMaxFileCount: Int
  var retentionMaxAgeDays: Int
  var capturesPausedPlaceholder: Bool

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

  let retentionMaxFileCount = sanitizeRetentionValue(
    storedCount,
    fallback: HostSettings.defaultRetentionMaxFileCount
  )
  let retentionMaxAgeDays = sanitizeRetentionValue(
    storedAge,
    fallback: HostSettings.defaultRetentionMaxAgeDays
  )

  return HostSettings(
    outputDirectoryPath: outputDirectoryPath,
    retentionMaxFileCount: retentionMaxFileCount,
    retentionMaxAgeDays: retentionMaxAgeDays,
    capturesPausedPlaceholder: capturesPaused
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
    .prefix(max(1, limit))
    .map { $0 }
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
