import AppKit
import Foundation
import SwiftUI
import UserNotifications

private let protocolVersion = "1"
private let defaultCaptureTimeoutMs = 1_200
private let hotkeyKeyCodeC: UInt16 = 8
private let hotkeyModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
private let hotkeyDebounceWindowSeconds = 0.25

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

struct HostCaptureRequestPayload: Codable {
  let protocolVersion: String
  let requestId: String
  let mode: String
  let requestedAt: String
  let timeoutMs: Int
  let includeSelectionText: Bool
}

struct HostCaptureRequestMessage: Codable {
  let id: String
  let type: String
  let timestamp: String
  let payload: HostCaptureRequestPayload
}

struct ExtensionCaptureResponsePayload: Codable {
  let protocolVersion: String
  let capture: BrowserContextPayload
}

struct ExtensionCaptureResponseMessage: Codable {
  let id: String
  let type: String
  let timestamp: String
  let payload: ExtensionCaptureResponsePayload
}

struct ExtensionErrorPayload: Codable {
  let protocolVersion: String
  let code: String
  let message: String
  let recoverable: Bool
  let details: [String: String]?
}

struct ExtensionErrorMessage: Codable {
  let id: String
  let type: String
  let timestamp: String
  let payload: ExtensionErrorPayload
}

private struct GenericEnvelope: Codable {
  let id: String
  let type: String
  let timestamp: String
}

enum ExtensionBridgeMessage {
  case captureResult(ExtensionCaptureResponseMessage)
  case error(ExtensionErrorMessage)
}

struct NativeMessagingPingResponse: Codable {
  let ok: Bool
  let protocolVersion: String
}

struct MarkdownCaptureOutput {
  let requestID: String
  let markdown: String
  let fileURL: URL
}

private struct CaptureResolution {
  let payload: BrowserContextPayload
  let extractionMethod: String
  let transportStatus: String
  let warning: String?
}

enum SafariNativeMessagingTransportError: LocalizedError {
  case repoRootNotFound
  case extensionPackageNotFound
  case launchFailed(String)
  case timedOut
  case processFailed(exitCode: Int32, stderr: String)
  case emptyOutput
  case invalidJSON(String)

  var errorDescription: String? {
    switch self {
    case .repoRootNotFound:
      return "Unable to locate repository root for Safari extension bridge."
    case .extensionPackageNotFound:
      return "Safari extension package was not found."
    case .launchFailed(let reason):
      return "Failed to launch Safari extension bridge: \(reason)"
    case .timedOut:
      return "Timed out waiting for extension response."
    case .processFailed(let exitCode, let stderr):
      return "Extension bridge failed with exit code \(exitCode): \(stderr)"
    case .emptyOutput:
      return "Extension bridge returned no output."
    case .invalidJSON(let reason):
      return "Extension bridge returned invalid JSON: \(reason)"
    }
  }
}

private struct ProcessExecutionResult {
  let stdout: Data
  let stderr: Data
  let exitCode: Int32
}

final class SafariNativeMessagingTransport {
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let fileManager = FileManager.default

  func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int) throws -> ExtensionBridgeMessage {
    let requestData = try jsonEncoder.encode(request)
    let processResult = try runNativeMessaging(arguments: [], stdinData: requestData, timeoutMs: timeoutMs)

    if !processResult.stdout.isEmpty, let decodedMessage = try? decodeBridgeMessage(processResult.stdout) {
      return decodedMessage
    }

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw SafariNativeMessagingTransportError.processFailed(exitCode: processResult.exitCode, stderr: stderr)
    }

    return try decodeBridgeMessage(processResult.stdout)
  }

  func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
    let processResult = try runNativeMessaging(arguments: ["--ping"], stdinData: nil, timeoutMs: timeoutMs)

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw SafariNativeMessagingTransportError.processFailed(exitCode: processResult.exitCode, stderr: stderr)
    }

    guard !processResult.stdout.isEmpty else {
      throw SafariNativeMessagingTransportError.emptyOutput
    }

    do {
      return try jsonDecoder.decode(NativeMessagingPingResponse.self, from: processResult.stdout)
    } catch {
      throw SafariNativeMessagingTransportError.invalidJSON(error.localizedDescription)
    }
  }

  private func decodeBridgeMessage(_ data: Data) throws -> ExtensionBridgeMessage {
    guard !data.isEmpty else {
      throw SafariNativeMessagingTransportError.emptyOutput
    }

    let envelope: GenericEnvelope
    do {
      envelope = try jsonDecoder.decode(GenericEnvelope.self, from: data)
    } catch {
      throw SafariNativeMessagingTransportError.invalidJSON(error.localizedDescription)
    }

    switch envelope.type {
    case "extension.capture.result":
      do {
        let capture = try jsonDecoder.decode(ExtensionCaptureResponseMessage.self, from: data)
        return .captureResult(capture)
      } catch {
        throw SafariNativeMessagingTransportError.invalidJSON(error.localizedDescription)
      }
    case "extension.error":
      do {
        let errorMessage = try jsonDecoder.decode(ExtensionErrorMessage.self, from: data)
        return .error(errorMessage)
      } catch {
        throw SafariNativeMessagingTransportError.invalidJSON(error.localizedDescription)
      }
    default:
      throw SafariNativeMessagingTransportError.invalidJSON("Unsupported message type: \(envelope.type)")
    }
  }

  private func runNativeMessaging(arguments: [String], stdinData: Data?, timeoutMs: Int) throws -> ProcessExecutionResult {
    let packagePath = try extensionPackagePath()
    let bunExecutablePath = try resolveBunExecutablePath()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: bunExecutablePath)
    process.currentDirectoryURL = packagePath
    let cliPath = packagePath.appendingPathComponent("src/native-messaging-cli.ts", isDirectory: false)
    process.arguments = [cliPath.path] + arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdinPipe = Pipe()
    process.standardInput = stdinPipe

    do {
      try process.run()
    } catch {
      throw SafariNativeMessagingTransportError.launchFailed(error.localizedDescription)
    }

    if let stdinData {
      stdinPipe.fileHandleForWriting.write(stdinData)
    }
    stdinPipe.fileHandleForWriting.closeFile()

    let timeoutDate = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
    while process.isRunning && Date() < timeoutDate {
      _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    if process.isRunning {
      process.terminate()
      throw SafariNativeMessagingTransportError.timedOut
    }

    process.waitUntilExit()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessExecutionResult(stdout: stdoutData, stderr: stderrData, exitCode: process.terminationStatus)
  }

  private func extensionPackagePath() throws -> URL {
    let repoRoot = try resolveRepoRoot()
    let packagePath = repoRoot.appendingPathComponent("packages/extension-safari", isDirectory: true)
    let packageManifest = packagePath.appendingPathComponent("package.json", isDirectory: false)

    guard fileManager.fileExists(atPath: packageManifest.path) else {
      throw SafariNativeMessagingTransportError.extensionPackageNotFound
    }

    return packagePath
  }

  private func resolveRepoRoot() throws -> URL {
    if let envRoot = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_REPO_ROOT"], !envRoot.isEmpty {
      let explicitRoot = URL(fileURLWithPath: envRoot, isDirectory: true)
      if hasRepoMarker(at: explicitRoot) {
        return explicitRoot
      }
    }

    var candidates: [URL] = [
      URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
      URL(fileURLWithPath: #filePath, isDirectory: false).deletingLastPathComponent(),
      Bundle.main.bundleURL,
    ]
    if let executableURL = Bundle.main.executableURL {
      candidates.append(executableURL.deletingLastPathComponent())
    }

    var visited = Set<String>()
    for candidate in candidates {
      if visited.contains(candidate.path) {
        continue
      }
      visited.insert(candidate.path)

      if let resolvedRoot = findRepoRoot(startingAt: candidate, maxDepth: 12) {
        return resolvedRoot
      }
    }

    throw SafariNativeMessagingTransportError.repoRootNotFound
  }

  private func findRepoRoot(startingAt startURL: URL, maxDepth: Int) -> URL? {
    var current = startURL
    for _ in 0..<maxDepth {
      if hasRepoMarker(at: current) {
        return current
      }

      let parent = current.deletingLastPathComponent()
      if parent.path == current.path {
        break
      }

      current = parent
    }

    return nil
  }

  private func hasRepoMarker(at rootURL: URL) -> Bool {
    let marker = rootURL.appendingPathComponent("packages/extension-safari/package.json", isDirectory: false)
    return fileManager.fileExists(atPath: marker.path)
  }

  private func resolveBunExecutablePath() throws -> String {
    if let explicitPath = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_BUN_BIN"], !explicitPath.isEmpty {
      if fileManager.isExecutableFile(atPath: explicitPath) {
        return explicitPath
      }
      throw SafariNativeMessagingTransportError.launchFailed(
        "CONTEXT_GRABBER_BUN_BIN is set but not executable: \(explicitPath)"
      )
    }

    if let pathValue = ProcessInfo.processInfo.environment["PATH"], !pathValue.isEmpty {
      for directory in pathValue.split(separator: ":").map(String.init) where !directory.isEmpty {
        let candidate = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent("bun", isDirectory: false)
        if fileManager.isExecutableFile(atPath: candidate.path) {
          return candidate.path
        }
      }
    }

    var fallbackPaths: [String] = ["/opt/homebrew/bin/bun", "/usr/local/bin/bun"]
    let homeBunPath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .appendingPathComponent(".bun/bin/bun", isDirectory: false).path
    fallbackPaths.append(homeBunPath)

    for candidate in fallbackPaths where fileManager.isExecutableFile(atPath: candidate) {
      return candidate
    }

    throw SafariNativeMessagingTransportError.launchFailed(
      "Unable to locate bun executable. Set CONTEXT_GRABBER_BUN_BIN to the bun binary path."
    )
  }
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

private final class HotkeyMonitorRegistration {
  private let globalMonitor: Any?
  private let localMonitor: Any?

  init(handler: @escaping (NSEvent) -> Void) {
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      handler(event)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handler(event)
      return event
    }
  }

  deinit {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
    }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
    }
  }
}

@MainActor
final class ContextGrabberModel: ObservableObject {
  @Published var statusLine: String = "Ready"

  private let logger = HostLogger()
  private let transport = SafariNativeMessagingTransport()
  private let notificationsEnabled: Bool
  private var hotkeyMonitorRegistration: HotkeyMonitorRegistration?
  private var lastHotkeyFireAt: Date = .distantPast
  private var lastCaptureAt: String?
  private var lastTransportErrorCode: String?
  private var lastTransportLatencyMs: Int?
  private var lastTransportStatus: String = "unknown"
  private var captureInFlight = false

  init() {
    notificationsEnabled = Self.canUseUserNotifications()
    if notificationsEnabled {
      requestNotificationAuthorization()
    } else {
      logger.info("User notifications disabled for unbundled runtime (swift run).")
    }

    registerHotkeyMonitors()
  }

  func captureNow() {
    triggerCapture(mode: "manual_menu")
  }

  private func triggerCapture(mode: String) {
    if captureInFlight {
      statusLine = "Capture already in progress"
      return
    }

    captureInFlight = true
    defer { captureInFlight = false }

    do {
      let requestID = UUID().uuidString.lowercased()
      let timestamp = isoTimestamp()

      let request = HostCaptureRequestMessage(
        id: requestID,
        type: "host.capture.request",
        timestamp: timestamp,
        payload: HostCaptureRequestPayload(
          protocolVersion: protocolVersion,
          requestId: requestID,
          mode: mode,
          requestedAt: timestamp,
          timeoutMs: defaultCaptureTimeoutMs,
          includeSelectionText: true
        )
      )

      let transportStart = Date()
      let resolution = try resolveCapture(request: request)
      lastTransportLatencyMs = Int(Date().timeIntervalSince(transportStart) * 1000.0)
      lastCaptureAt = timestamp

      let output = try createCaptureOutput(
        from: resolution.payload,
        extractionMethod: resolution.extractionMethod,
        requestID: requestID,
        capturedAt: timestamp
      )
      try writeMarkdown(output)
      try copyToClipboard(output.markdown)

      let triggerLabel = mode == "manual_hotkey" ? "hotkey" : "menu"
      let warningCount = resolution.payload.extractionWarnings?.count ?? 0
      statusLine =
        "Captured \(triggerLabel) via \(resolution.extractionMethod) (\(output.requestID.prefix(8))) | \(resolution.transportStatus) | warnings: \(warningCount)"
      logger.info(
        "Capture complete: \(output.fileURL.path) | mode=\(mode) | transport=\(resolution.transportStatus) | latency_ms=\(lastTransportLatencyMs ?? -1)"
      )

      let subtitle = resolution.warning == nil
        ? output.fileURL.lastPathComponent
        : "\(output.fileURL.lastPathComponent) | \(resolution.warning ?? "")"
      postUserNotification(title: "Context Captured", subtitle: subtitle)
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
    let writable = FileManager.default.isWritableFile(atPath: Self.appSupportBaseURL().path)

    var transportReachable = false
    var protocolCompatible = false

    do {
      let ping = try transport.ping(timeoutMs: 800)
      transportReachable = ping.ok
      protocolCompatible = ping.protocolVersion == protocolVersion
      lastTransportStatus = transportReachable ? "safari_extension_ok" : "safari_extension_unreachable"
    } catch {
      lastTransportStatus = "safari_extension_unreachable"
      logger.error("Diagnostics ping failed: \(error.localizedDescription)")
    }

    let lastCaptureLabel = lastCaptureAt ?? "never"
    let lastErrorLabel = lastTransportErrorCode ?? "none"
    let latencyLabel = lastTransportLatencyMs.map { "\($0)ms" } ?? "n/a"

    let summary =
      "Transport: \(transportReachable ? "reachable" : "unreachable") | Protocol: \(protocolCompatible ? "\(protocolVersion)" : "mismatch") | Last capture: \(lastCaptureLabel) | Last error: \(lastErrorLabel) | Latency: \(latencyLabel) | Storage writable: \(writable ? "yes" : "no") | History: \(historyURL.path)"

    statusLine = summary
    logger.info("Diagnostics: \(summary)")
  }

  private func registerHotkeyMonitors() {
    hotkeyMonitorRegistration = HotkeyMonitorRegistration { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handleHotkeyEvent(event)
      }
    }
  }

  private func handleHotkeyEvent(_ event: NSEvent) {
    guard isCaptureHotkey(event) else {
      return
    }

    let now = Date()
    guard now.timeIntervalSince(lastHotkeyFireAt) > hotkeyDebounceWindowSeconds else {
      return
    }
    lastHotkeyFireAt = now

    triggerCapture(mode: "manual_hotkey")
  }

  private func isCaptureHotkey(_ event: NSEvent) -> Bool {
    guard event.keyCode == hotkeyKeyCodeC else {
      return false
    }

    let activeModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    return activeModifiers == hotkeyModifiers
  }

  private func resolveCapture(request: HostCaptureRequestMessage) throws -> CaptureResolution {
    do {
      let bridgeMessage = try transport.sendCaptureRequest(request, timeoutMs: request.payload.timeoutMs)

      switch bridgeMessage {
      case .captureResult(let captureResponse):
        lastTransportStatus = "safari_extension_ok"
        lastTransportErrorCode = nil

        if captureResponse.payload.protocolVersion != protocolVersion {
          return metadataFallback(
            code: "ERR_PROTOCOL_VERSION",
            message: "Protocol version mismatch. Expected \(protocolVersion).",
            details: nil
          )
        }

        return CaptureResolution(
          payload: captureResponse.payload.capture,
          extractionMethod: "browser_extension",
          transportStatus: lastTransportStatus,
          warning: nil
        )

      case .error(let errorMessage):
        return metadataFallback(
          code: errorMessage.payload.code,
          message: errorMessage.payload.message,
          details: errorMessage.payload.details
        )
      }
    } catch let transportError as SafariNativeMessagingTransportError {
      switch transportError {
      case .timedOut:
        return metadataFallback(
          code: "ERR_TIMEOUT",
          message: "Timed out waiting for extension response.",
          details: nil
        )
      default:
        return metadataFallback(
          code: "ERR_EXTENSION_UNAVAILABLE",
          message: transportError.localizedDescription,
          details: nil
        )
      }
    }
  }

  private func metadataFallback(
    code: String,
    message: String,
    details: [String: String]?
  ) -> CaptureResolution {
    let warning = "\(code): \(message)"
    let payload = createMetadataOnlyPayload(details: details, warning: warning)
    lastTransportStatus = "safari_extension_error:\(code)"
    lastTransportErrorCode = code

    return CaptureResolution(
      payload: payload,
      extractionMethod: "metadata_only",
      transportStatus: lastTransportStatus,
      warning: warning
    )
  }

  private func createMetadataOnlyPayload(details: [String: String]?, warning: String) -> BrowserContextPayload {
    let frontAppName = NSWorkspace.shared.frontmostApplication?.localizedName
    let title = details?["title"] ?? (frontAppName.map { "\($0) (metadata only)" } ?? "Safari (metadata only)")
    let url = details?["url"] ?? "about:blank"

    return BrowserContextPayload(
      source: "browser",
      browser: "safari",
      url: url,
      title: title,
      fullText: "",
      headings: [],
      links: [],
      metaDescription: nil,
      siteName: details?["site_name"],
      language: nil,
      author: nil,
      publishedTime: nil,
      selectionText: nil,
      extractionWarnings: [warning]
    )
  }

  private func createCaptureOutput(
    from payload: BrowserContextPayload,
    extractionMethod: String,
    requestID: String,
    capturedAt: String
  ) throws -> MarkdownCaptureOutput {
    let markdown = renderMarkdown(
      requestID: requestID,
      capturedAt: capturedAt,
      extractionMethod: extractionMethod,
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
    guard notificationsEnabled else {
      return
    }

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
    guard notificationsEnabled else {
      return
    }

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
      if let error {
        fputs("ContextGrabberHost notification authorization error: \(error.localizedDescription)\n", stderr)
      }
    }
  }

  private static func canUseUserNotifications() -> Bool {
    if Bundle.main.bundleIdentifier == nil {
      return false
    }

    let bundlePath = Bundle.main.bundleURL.path
    return !bundlePath.contains("/.build/")
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
      Button("Capture Now (⌃⌥⌘C)") {
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
