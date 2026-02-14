import AppKit
import Foundation
import SwiftUI
import UserNotifications

struct BrowserContextPayload: Codable {
  let source: String
  let browser: String
  let url: String
  let title: String
  let fullText: String
  let headings: [Heading]
  let links: [Link]
  let metaDescription: String?
  let siteName: String?
  let language: String?
  let author: String?
  let publishedTime: String?
  let selectionText: String?
  let extractionWarnings: [String]?

  struct Heading: Codable {
    let level: Int
    let text: String
  }

  struct Link: Codable {
    let text: String
    let href: String
  }
}

struct MarkdownCaptureOutput {
  let requestID: String
  let markdown: String
  let fileURL: URL
}

final class HostLogger {
  private let logURL: URL

  init() {
    let baseURL = Self.appSupportBaseURL()
    let logsDirectory = baseURL.appendingPathComponent("logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    self.logURL = logsDirectory.appendingPathComponent("host.log", isDirectory: false)
  }

  func info(_ message: String) {
    write(level: "INFO", message: message)
  }

  func error(_ message: String) {
    write(level: "ERROR", message: message)
  }

  private func write(level: String, message: String) {
    let line = "[\(isoTimestamp())] [\(level)] \(message)\n"
    guard let data = line.data(using: .utf8) else {
      return
    }

    if !FileManager.default.fileExists(atPath: logURL.path) {
      FileManager.default.createFile(atPath: logURL.path, contents: data)
      return
    }

    guard let handle = try? FileHandle(forWritingTo: logURL) else {
      return
    }

    defer {
      try? handle.close()
    }

    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
    } catch {
      // Ignored: logging should not fail app operations.
    }
  }

  private static func appSupportBaseURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appendingPathComponent("ContextGrabber", isDirectory: true)
  }
}

@MainActor
final class ContextGrabberModel: ObservableObject {
  @Published var statusLine: String = "Ready"

  private let logger = HostLogger()

  init() {
    requestNotificationAuthorization()
  }

  func captureNow() {
    do {
      let payload = try loadFixturePayload()
      let output = try createCaptureOutput(from: payload)
      try writeMarkdown(output)
      try copyToClipboard(output.markdown)

      statusLine = "Captured via mock fixture (\(output.requestID))"
      logger.info("Capture complete: \(output.fileURL.path)")
      postUserNotification(title: "Context Captured", subtitle: output.fileURL.lastPathComponent)
    } catch {
      statusLine = "Capture failed"
      logger.error("Capture failed: \(error.localizedDescription)")
      postUserNotification(title: "Capture Failed", subtitle: error.localizedDescription)
    }
  }

  func openRecentCaptures() {
    let historyURL = Self.historyDirectoryURL()
    do {
      try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
      NSWorkspace.shared.open(historyURL)
      statusLine = "Opened history folder"
      logger.info("Opened history folder: \(historyURL.path)")
    } catch {
      statusLine = "Unable to open history folder"
      logger.error("Failed to open history folder: \(error.localizedDescription)")
    }
  }

  func runDiagnostics() {
    let historyURL = Self.historyDirectoryURL()
    let fixtureFound = Bundle.module.url(forResource: "sample-browser-capture", withExtension: "json") != nil
    let writable = FileManager.default.isWritableFile(atPath: Self.appSupportBaseURL().path)

    let summary = "Fixture: \(fixtureFound ? "ok" : "missing") | Storage writable: \(writable ? "yes" : "no") | History: \(historyURL.path)"

    statusLine = summary
    logger.info("Diagnostics: \(summary)")
  }

  private func loadFixturePayload() throws -> BrowserContextPayload {
    guard let fixtureURL = Bundle.module.url(forResource: "sample-browser-capture", withExtension: "json") else {
      throw NSError(domain: "ContextGrabberHost", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Fixture file not found."])
    }

    let data = try Data(contentsOf: fixtureURL)
    return try JSONDecoder().decode(BrowserContextPayload.self, from: data)
  }

  private func createCaptureOutput(from payload: BrowserContextPayload) throws -> MarkdownCaptureOutput {
    let requestID = UUID().uuidString.lowercased()
    let timestamp = isoTimestamp()

    let markdown = renderMarkdown(
      requestID: requestID,
      capturedAt: timestamp,
      extractionMethod: "browser_extension",
      payload: payload
    )

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
    let filePrefix = dateFormatter.string(from: Date())

    let filename = "\(filePrefix)-\(requestID.prefix(8)).md"
    let fileURL = Self.historyDirectoryURL().appendingPathComponent(filename, isDirectory: false)

    return MarkdownCaptureOutput(requestID: requestID, markdown: markdown, fileURL: fileURL)
  }

  private func writeMarkdown(_ output: MarkdownCaptureOutput) throws {
    let historyURL = Self.historyDirectoryURL()
    try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
    try output.markdown.write(to: output.fileURL, atomically: true, encoding: .utf8)
  }

  private func copyToClipboard(_ text: String) throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let wrote = pasteboard.setString(text, forType: .string)
    if !wrote {
      throw NSError(
        domain: "ContextGrabberHost",
        code: 1002,
        userInfo: [NSLocalizedDescriptionKey: "Failed to write capture to clipboard."]
      )
    }
  }

  private func postUserNotification(title: String, subtitle: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = subtitle

    let request = UNNotificationRequest(
      identifier: UUID().uuidString.lowercased(),
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        fputs("ContextGrabberHost notification error: \(error.localizedDescription)\n", stderr)
      }
    }
  }

  private func requestNotificationAuthorization() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
      if let error {
        fputs("ContextGrabberHost notification authorization error: \(error.localizedDescription)\n", stderr)
      }
    }
  }

  private static func appSupportBaseURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appendingPathComponent("ContextGrabber", isDirectory: true)
  }

  private static func historyDirectoryURL() -> URL {
    return appSupportBaseURL().appendingPathComponent("history", isDirectory: true)
  }
}

@main
struct ContextGrabberHostApp: App {
  @StateObject private var model = ContextGrabberModel()

  var body: some Scene {
    MenuBarExtra("Context Grabber", systemImage: "text.viewfinder") {
      Button("Capture Now") {
        model.captureNow()
      }

      Button("Open Recent Captures") {
        model.openRecentCaptures()
      }

      Button("Run Diagnostics") {
        model.runDiagnostics()
      }

      Divider()
      Text(model.statusLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)

      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
    .menuBarExtraStyle(.window)
  }
}

private func isoTimestamp() -> String {
  return ISO8601DateFormatter().string(from: Date())
}

private func renderMarkdown(
  requestID: String,
  capturedAt: String,
  extractionMethod: String,
  payload: BrowserContextPayload
) -> String {
  let normalizedText = payload.fullText.replacingOccurrences(of: "\r\n", with: "\n")
  let trimmedText = String(normalizedText.prefix(200_000))
  let truncated = normalizedText.count > 200_000

  let summary = buildSummary(from: trimmedText)
  let keyPoints = buildKeyPoints(from: trimmedText)
  let chunks = buildChunks(from: trimmedText)
  let rawExcerpt = String(trimmedText.prefix(8_000))

  let warnings = (payload.extractionWarnings ?? []) + (truncated ? ["Capture truncated at 200000 chars."] : [])
  let tokenEstimate = max(1, Int(ceil(Double(trimmedText.count) / 4.0)))

  var lines: [String] = []
  lines.append("---")
  lines.append("id: \(yamlQuoted(requestID))")
  lines.append("captured_at: \(yamlQuoted(capturedAt))")
  lines.append("source_type: \(yamlQuoted("webpage"))")
  lines.append("origin: \(yamlQuoted(payload.url))")
  lines.append("title: \(yamlQuoted(payload.title))")
  lines.append("app_or_site: \(yamlQuoted(payload.siteName ?? hostFromURL(payload.url) ?? payload.browser))")
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
  lines.append("- browser: \(payload.browser)")
  lines.append("- url: \(payload.url)")
  if let language = payload.language {
    lines.append("- language: \(language)")
  }
  if let author = payload.author {
    lines.append("- author: \(author)")
  }

  lines.append("")
  return lines.joined(separator: "\n")
}

private func buildSummary(from text: String) -> String {
  let sentences = splitSentences(text)
  if sentences.isEmpty {
    return ""
  }

  return sentences.prefix(6).joined(separator: "\n")
}

private func buildKeyPoints(from text: String) -> [String] {
  let sentences = splitSentences(text)
  return Array(sentences.prefix(8))
}

private func buildChunks(from text: String) -> [String] {
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

private func splitSentences(_ text: String) -> [String] {
  let parts = text.split(separator: ".")
  return parts
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .map { "\($0)." }
}

private func hostFromURL(_ urlString: String) -> String? {
  guard let url = URL(string: urlString) else {
    return nil
  }

  return url.host
}

private func yamlQuoted(_ value: String) -> String {
  let escaped = value
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")

  return "\"\(escaped)\""
}
