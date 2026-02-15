import AppKit
import Foundation
import SwiftUI

let protocolVersion = "1"
private let advancedSettingsWindowID = "advanced-settings"
private let defaultCaptureTimeoutMs = 1_200
// Hotkey rebinding is deferred to Milestone G; keep fixed chord for now.
private let hotkeyKeyCodeC: UInt16 = 8
private let hotkeyModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
private let hotkeyDebounceWindowSeconds = 0.25
let maxBrowserFullTextChars = 200_000
let maxRawExcerptChars = 8_000
private let safariBundleIdentifiers: Set<String> = [
  "com.apple.Safari",
  "com.apple.SafariTechnologyPreview",
]
private let chromiumBundleIdentifiers: [String: String] = [
  "com.google.Chrome": "Google Chrome",
  "com.google.Chrome.canary": "Google Chrome Canary",
  "company.thebrowser.Browser": "Arc",
  "com.brave.Browser": "Brave Browser",
  "com.brave.Browser.beta": "Brave Browser Beta",
  "com.brave.Browser.nightly": "Brave Browser Nightly",
  "com.microsoft.edgemac": "Microsoft Edge",
  "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
  "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
  "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
  "com.vivaldi.Vivaldi": "Vivaldi",
  "com.operasoftware.Opera": "Opera",
  "com.operasoftware.OperaGX": "Opera GX",
]

/// Returns the AppleScript application name for a Chromium-based browser bundle identifier.
/// Falls back to "Google Chrome" if the bundle identifier is not recognized.
func chromiumAppName(forBundleIdentifier bundleIdentifier: String?) -> String {
  guard let bundleIdentifier else { return "Google Chrome" }
  return chromiumBundleIdentifiers[bundleIdentifier] ?? "Google Chrome"
}

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

func shouldPromptDesktopPermissionsPopup(
  payload: BrowserContextPayload,
  extractionMethod: String,
  readiness: DesktopPermissionReadiness = desktopPermissionReadiness()
) -> Bool {
  guard payload.source == "desktop" else {
    return false
  }

  guard extractionMethod == "metadata_only" || extractionMethod == "ocr" else {
    return false
  }

  // Only prompt when a permission is actually missing.
  // Falling back to OCR or metadata_only is normal for apps that don't
  // expose enough AX text (e.g. Finder, games) — that's not a permissions issue.
  let missingAccessibility = !readiness.accessibilityTrusted
  let missingScreenRecording = readiness.screenRecordingGranted == false
  return missingAccessibility || missingScreenRecording
}

func desktopPermissionsPopupFallbackDescription(extractionMethod: String) -> String {
  switch extractionMethod {
  case "ocr":
    return "This capture fell back to OCR text extraction."
  case "metadata_only":
    return "This capture fell back to metadata-only."
  default:
    return "This capture used a desktop fallback path."
  }
}

struct MarkdownCaptureOutput {
  let requestID: String
  let markdown: String
  let fileURL: URL
}

enum BrowserTarget {
  case safari
  case chrome
  case unsupported(appName: String?, bundleIdentifier: String?)

  var browserLabel: String {
    switch self {
    case .safari:
      return "safari"
    case .chrome:
      return "chrome"
    case .unsupported(_, let bundleIdentifier):
      if let bundleIdentifier, bundleIdentifier.contains("Chrome") {
        return "chrome"
      }
      if let bundleIdentifier, bundleIdentifier.contains("Safari") {
        return "safari"
      }
      return "unknown"
    }
  }

  var transportStatusPrefix: String {
    switch self {
    case .safari:
      return "safari_extension"
    case .chrome:
      return "chrome_extension"
    case .unsupported:
      return "desktop_capture"
    }
  }

  var displayName: String {
    switch self {
    case .safari:
      return "Safari"
    case .chrome:
      return "Chrome"
    case .unsupported(let appName, _):
      return appName ?? "Unknown App"
    }
  }
}

func detectBrowserTarget(
  frontmostBundleIdentifier: String?,
  frontmostAppName: String?,
  overrideValue: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_BROWSER_TARGET"]
) -> BrowserTarget {
  if let overrideValue {
    let normalized = overrideValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "safari" {
      return .safari
    }
    if normalized == "chrome" {
      return .chrome
    }
  }

  if let frontmostBundleIdentifier {
    if safariBundleIdentifiers.contains(frontmostBundleIdentifier) {
      return .safari
    }
    if chromiumBundleIdentifiers[frontmostBundleIdentifier] != nil {
      return .chrome
    }
  }

  return .unsupported(appName: frontmostAppName, bundleIdentifier: frontmostBundleIdentifier)
}

struct FrontmostAppInfo {
  let bundleIdentifier: String?
  let appName: String?
  let processIdentifier: pid_t?
}

func resolveEffectiveFrontmostApp(
  current: FrontmostAppInfo,
  lastNonHost: FrontmostAppInfo?,
  lastKnownBrowser: FrontmostAppInfo?,
  hostProcessIdentifier: pid_t
) -> FrontmostAppInfo {
  if current.processIdentifier == hostProcessIdentifier {
    if let lastKnownBrowser {
      return lastKnownBrowser
    }
    if let lastNonHost {
      return lastNonHost
    }
  }

  return current
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

enum ChromeNativeMessagingTransportError: LocalizedError {
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
      return "Unable to locate repository root for Chrome extension bridge."
    case .extensionPackageNotFound:
      return "Chrome extension package was not found."
    case .launchFailed(let reason):
      return "Failed to launch Chrome extension bridge: \(reason)"
    case .timedOut:
      return "Timed out waiting for extension response."
    case .processFailed(let exitCode, let stderr):
      return "Chrome extension bridge failed with exit code \(exitCode): \(stderr)"
    case .emptyOutput:
      return "Chrome extension bridge returned no output."
    case .invalidJSON(let reason):
      return "Chrome extension bridge returned invalid JSON: \(reason)"
    }
  }
}

final class ChromeNativeMessagingTransport {
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let fileManager = FileManager.default

  func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int, chromeAppName: String? = nil) throws -> ExtensionBridgeMessage {
    let requestData = try jsonEncoder.encode(request)
    let processResult = try runNativeMessaging(arguments: [], stdinData: requestData, timeoutMs: timeoutMs, chromeAppName: chromeAppName)

    if !processResult.stdout.isEmpty, let decodedMessage = try? decodeBridgeMessage(processResult.stdout) {
      return decodedMessage
    }

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw ChromeNativeMessagingTransportError.processFailed(exitCode: processResult.exitCode, stderr: stderr)
    }

    return try decodeBridgeMessage(processResult.stdout)
  }

  func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
    let processResult = try runNativeMessaging(arguments: ["--ping"], stdinData: nil, timeoutMs: timeoutMs)

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw ChromeNativeMessagingTransportError.processFailed(exitCode: processResult.exitCode, stderr: stderr)
    }

    guard !processResult.stdout.isEmpty else {
      throw ChromeNativeMessagingTransportError.emptyOutput
    }

    do {
      return try jsonDecoder.decode(NativeMessagingPingResponse.self, from: processResult.stdout)
    } catch {
      throw ChromeNativeMessagingTransportError.invalidJSON(error.localizedDescription)
    }
  }

  private func decodeBridgeMessage(_ data: Data) throws -> ExtensionBridgeMessage {
    guard !data.isEmpty else {
      throw ChromeNativeMessagingTransportError.emptyOutput
    }

    let envelope: GenericEnvelope
    do {
      envelope = try jsonDecoder.decode(GenericEnvelope.self, from: data)
    } catch {
      throw ChromeNativeMessagingTransportError.invalidJSON(error.localizedDescription)
    }

    switch envelope.type {
    case "extension.capture.result":
      do {
        let capture = try jsonDecoder.decode(ExtensionCaptureResponseMessage.self, from: data)
        return .captureResult(capture)
      } catch {
        throw ChromeNativeMessagingTransportError.invalidJSON(error.localizedDescription)
      }
    case "extension.error":
      do {
        let errorMessage = try jsonDecoder.decode(ExtensionErrorMessage.self, from: data)
        return .error(errorMessage)
      } catch {
        throw ChromeNativeMessagingTransportError.invalidJSON(error.localizedDescription)
      }
    default:
      throw ChromeNativeMessagingTransportError.invalidJSON("Unsupported message type: \(envelope.type)")
    }
  }

  private func runNativeMessaging(arguments: [String], stdinData: Data?, timeoutMs: Int, chromeAppName: String? = nil) throws -> ProcessExecutionResult {
    let packagePath = try extensionPackagePath()
    let bunExecutablePath = try resolveBunExecutablePath()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: bunExecutablePath)
    process.currentDirectoryURL = packagePath
    let cliPath = packagePath.appendingPathComponent("src/native-messaging-cli.ts", isDirectory: false)
    process.arguments = [cliPath.path] + arguments

    if let chromeAppName {
      var env = ProcessInfo.processInfo.environment
      env["CONTEXT_GRABBER_CHROME_APP_NAME"] = chromeAppName
      process.environment = env
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdinPipe = Pipe()
    process.standardInput = stdinPipe

    do {
      try process.run()
    } catch {
      throw ChromeNativeMessagingTransportError.launchFailed(error.localizedDescription)
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
      throw ChromeNativeMessagingTransportError.timedOut
    }

    process.waitUntilExit()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessExecutionResult(stdout: stdoutData, stderr: stderrData, exitCode: process.terminationStatus)
  }

  private func extensionPackagePath() throws -> URL {
    let repoRoot = try resolveRepoRoot()
    let packagePath = repoRoot.appendingPathComponent("packages/extension-chrome", isDirectory: true)
    let packageManifest = packagePath.appendingPathComponent("package.json", isDirectory: false)

    guard fileManager.fileExists(atPath: packageManifest.path) else {
      throw ChromeNativeMessagingTransportError.extensionPackageNotFound
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

    throw ChromeNativeMessagingTransportError.repoRootNotFound
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
    let marker = rootURL.appendingPathComponent("packages/extension-chrome/package.json", isDirectory: false)
    return fileManager.fileExists(atPath: marker.path)
  }

  private func resolveBunExecutablePath() throws -> String {
    if let explicitPath = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_BUN_BIN"], !explicitPath.isEmpty {
      if fileManager.isExecutableFile(atPath: explicitPath) {
        return explicitPath
      }
      throw ChromeNativeMessagingTransportError.launchFailed(
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

    throw ChromeNativeMessagingTransportError.launchFailed(
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

private final class AppActivationObserverRegistration {
  private let token: NSObjectProtocol

  init(handler: @escaping @Sendable (NSRunningApplication) -> Void) {
    token = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: nil
    ) { notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
        return
      }
      handler(app)
    }
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(token)
  }
}

@MainActor
final class ContextGrabberModel: ObservableObject {
  @Published var statusLine: String = "Ready"
  @Published private(set) var indicatorState: MenuBarIndicatorState = .idle
  @Published private(set) var menuBarIcon: MenuBarIcon = menuBarIconForIndicatorState(.idle)
  @Published private(set) var feedbackState: CaptureFeedbackState?
  @Published private(set) var appVersionLabel: String = "Version dev"
  @Published private(set) var lastCaptureLabel: String = "Last capture: never"
  @Published private(set) var recentCaptures: [CaptureHistoryEntry] = []
  @Published private(set) var outputDirectoryLabel: String = "Default"
  @Published private(set) var usingDefaultOutputDirectory: Bool = true
  @Published private(set) var retentionMaxFileCount: Int = HostSettings.defaultRetentionMaxFileCount
  @Published private(set) var retentionMaxAgeDays: Int = HostSettings.defaultRetentionMaxAgeDays
  @Published private(set) var capturesPausedPlaceholder = false
  @Published private(set) var clipboardCopyMode: ClipboardCopyMode =
    HostSettings.defaultClipboardCopyMode
  @Published private(set) var outputFormatPreset: OutputFormatPreset =
    HostSettings.defaultOutputFormatPreset
  @Published private(set) var includeProductContextLine: Bool =
    HostSettings.defaultIncludeProductContextLine
  @Published private(set) var summarizationMode: SummarizationMode =
    HostSettings.defaultSummarizationMode
  @Published private(set) var summarizationProvider: SummarizationProvider?
  @Published private(set) var summarizationModel: String?
  @Published private(set) var summaryTokenBudget: Int = HostSettings.defaultSummaryTokenBudget
  @Published private(set) var safariDiagnosticsLabel: String = "unknown"
  @Published private(set) var chromeDiagnosticsLabel: String = "unknown"
  @Published private(set) var desktopAccessibilityDiagnosticsLabel: String = "unknown"
  @Published private(set) var desktopScreenDiagnosticsLabel: String = "unknown"

  private let logger = HostLogger()
  private let fileManager = FileManager.default
  private let safariTransport = SafariNativeMessagingTransport()
  private let chromeTransport = ChromeNativeMessagingTransport()
  private let captureResultPopup = CaptureResultPopupController()
  private let hostProcessIdentifier = ProcessInfo.processInfo.processIdentifier
  private var settings: HostSettings
  private var hotkeyMonitorRegistration: HotkeyMonitorRegistration?
  private var appActivationObserverRegistration: AppActivationObserverRegistration?
  private var lastNonHostFrontmostApp: FrontmostAppInfo?
  private var lastKnownBrowserFrontmostApp: FrontmostAppInfo?
  private var lastHotkeyFireAt: Date = .distantPast
  private var lastCaptureAt: String?
  private var lastTransportErrorCode: String?
  private var lastTransportLatencyMs: Int?
  private var lastTransportStatus: String = "unknown"
  private var safariDiagnosticsTransportStatus = "unknown"
  private var chromeDiagnosticsTransportStatus = "unknown"
  private var captureInFlight = false
  private var indicatorResetTask: Task<Void, Never>?
  private var indicatorResetToken = UUID()
  private var feedbackDismissTask: Task<Void, Never>?

  init() {
    settings = loadHostSettings()
    registerHotkeyMonitors()
    registerFrontmostAppObserver()
    appVersionLabel = resolveAppVersionLabel()
    applySettingsToPublishedState()
    refreshRecentCaptures()
    updateLastCaptureLabel()
  }

  func captureNow() {
    triggerCapture(mode: "manual_menu")
  }

  private func triggerCapture(mode: String) {
    if capturesPausedPlaceholder {
      statusLine = "Captures paused"
      return
    }

    if captureInFlight {
      statusLine = "Capture already in progress"
      return
    }

    captureInFlight = true
    statusLine = "Capture in progress..."
    clearCaptureFeedback()
    setMenuBarIndicator(.capturing)
    Task { @MainActor [weak self] in
      await self?.performCapture(mode: mode)
    }
  }

  private func performCapture(mode: String) async {
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
      let resolution = try await resolveCapture(request: request)
      lastTransportLatencyMs = Int(Date().timeIntervalSince(transportStart) * 1000.0)
      lastCaptureAt = timestamp
      updateLastCaptureLabel()

      let output = try await createCaptureOutput(
        from: resolution.payload,
        extractionMethod: resolution.extractionMethod,
        requestID: requestID,
        capturedAt: timestamp
      )
      try writeMarkdown(output)
      applyRetentionPolicy()
      var captureWarning = resolution.warning
      var clipboardCopyFailed = false
      do {
        try copyCaptureOutputToClipboard(output)
      } catch {
        clipboardCopyFailed = true
        let clipboardWarning = "Clipboard copy failed: \(error.localizedDescription)"
        if let existingWarning = captureWarning, !existingWarning.isEmpty {
          captureWarning = "\(existingWarning) | \(clipboardWarning)"
        } else {
          captureWarning = clipboardWarning
        }
        logger.error(
          "Capture saved but clipboard copy failed: \(error.localizedDescription) | file=\(output.fileURL.path)"
        )
      }
      refreshRecentCaptures()

      let tokenCount = max(1, Int(ceil(Double(output.markdown.count) / 4.0)))
      let sourceLabel = payloadSourceLabel(for: resolution.payload)
      let targetLabel = payloadTargetLabel(for: resolution.payload)
      presentCaptureFeedback(
        kind: .success,
        detail: formatCaptureSuccessFeedbackDetail(
          sourceLabel: sourceLabel,
          targetLabel: targetLabel,
          extractionMethod: resolution.extractionMethod,
          transportStatus: resolution.transportStatus,
          warning: captureWarning
        ),
        sourceLabel: sourceLabel,
        targetLabel: targetLabel,
        extractionMethod: resolution.extractionMethod,
        warning: captureWarning,
        fileURL: output.fileURL,
        fileName: output.fileURL.lastPathComponent,
        tokenCount: tokenCount,
        autoDismissAfter: 4.0
      )
      setMenuBarIndicator(.success, autoResetAfter: 1.5)
      if shouldPromptDesktopPermissionsPopup(
        payload: resolution.payload,
        extractionMethod: resolution.extractionMethod
      ) {
        presentDesktopPermissionsPopup(extractionMethod: resolution.extractionMethod)
      }

      let triggerLabel = mode == "manual_hotkey" ? "hotkey" : "menu"
      let warningCount = (resolution.payload.extractionWarnings?.count ?? 0) + (clipboardCopyFailed ? 1 : 0)
      statusLine =
        "Captured \(triggerLabel) via \(resolution.extractionMethod) (\(output.requestID.prefix(8))) | \(resolution.transportStatus) | warnings: \(warningCount)"
      logger.info(
        "Capture complete: \(output.fileURL.path) | mode=\(mode) | transport=\(resolution.transportStatus) | latency_ms=\(lastTransportLatencyMs ?? -1)"
      )
    } catch {
      statusLine = "Capture failed"
      logger.error("Capture failed: \(error.localizedDescription)")
      presentCaptureFeedback(
        kind: .failure,
        detail: formatCaptureFailureFeedbackDetail(error.localizedDescription),
        sourceLabel: nil,
        targetLabel: nil,
        extractionMethod: nil,
        warning: nil,
        fileURL: nil,
        fileName: nil,
        autoDismissAfter: 4.0
      )
      setMenuBarIndicator(.error, autoResetAfter: 2.0)
    }
  }

  func openRecentCaptures() {
    let historyURL = resolvedHistoryDirectoryURL()
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

  func openCaptureFile(_ fileURL: URL) {
    if NSWorkspace.shared.open(fileURL) {
      statusLine = "Opened \(fileURL.lastPathComponent)"
      logger.info("Opened capture file: \(fileURL.path)")
      return
    }

    statusLine = "Unable to open capture file"
    logger.error("Failed to open capture file: \(fileURL.path)")
  }

  func copyLastCaptureToClipboard() {
    guard let latest = recentCaptures.first else {
      statusLine = "No recent capture to copy"
      return
    }

    do {
      try copyCaptureFileToClipboard(latest.fileURL)
      statusLine = "Copied last capture (\(clipboardCopyModeLabel(clipboardCopyMode)))"
      logger.info("Copied last capture from: \(latest.fileURL.path)")
    } catch {
      statusLine = "Unable to copy last capture"
      logger.error("Failed copying last capture: \(error.localizedDescription)")
    }
  }

  func copyFeedbackCaptureToClipboard() {
    guard let fileURL = feedbackState?.fileURL else {
      statusLine = "No feedback capture available to copy"
      return
    }

    do {
      try copyCaptureFileToClipboard(fileURL)
      statusLine = "Copied capture (\(clipboardCopyModeLabel(clipboardCopyMode)))"
      logger.info("Copied capture from popup: \(fileURL.path)")
    } catch {
      statusLine = "Unable to copy capture from popup"
      logger.error("Failed copying capture from popup: \(error.localizedDescription)")
    }
  }

  func openFeedbackCaptureFile() {
    guard let fileURL = feedbackState?.fileURL else {
      statusLine = "No feedback capture available to open"
      return
    }
    openCaptureFile(fileURL)
  }

  func dismissCaptureFeedback() {
    clearCaptureFeedback()
  }

  func chooseCustomOutputDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Use Folder"
    panel.message = "Choose a folder for saved captures."

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
      return
    }

    let normalizedURL = selectedURL.standardizedFileURL
    if let validationError = outputDirectoryValidationError(normalizedURL) {
      statusLine = validationError
      logger.error("Custom output directory rejected: \(normalizedURL.path)")
      return
    }

    updateSettings { current in
      current.outputDirectoryPath = normalizedURL.path
    }
    refreshRecentCaptures()
    statusLine = "Output directory updated"
  }

  func useDefaultOutputDirectory() {
    updateSettings { current in
      current.outputDirectoryPath = nil
    }
    refreshRecentCaptures()
    statusLine = "Using default output directory"
  }

  func setRetentionMaxFileCountPreference(_ count: Int) {
    updateSettings { current in
      current.retentionMaxFileCount = count
    }
    applyRetentionPolicy()
    refreshRecentCaptures()
    statusLine = "Retention max files: \(retentionMaxFileCountLabel(count))"
  }

  func setRetentionMaxAgeDaysPreference(_ days: Int) {
    updateSettings { current in
      current.retentionMaxAgeDays = days
    }
    applyRetentionPolicy()
    refreshRecentCaptures()
    statusLine = "Retention max age: \(retentionMaxAgeDaysLabel(days))"
  }

  func toggleCapturePausedPlaceholder() {
    updateSettings { current in
      current.capturesPausedPlaceholder.toggle()
    }
    statusLine = capturesPausedPlaceholder ? "Captures paused" : "Captures resumed"
  }

  func setClipboardCopyModePreference(_ mode: ClipboardCopyMode) {
    updateSettings { current in
      current.clipboardCopyMode = mode
    }
    statusLine = "Clipboard copy mode: \(clipboardCopyModeLabel(mode))"
  }

  func setOutputFormatPresetPreference(_ preset: OutputFormatPreset) {
    updateSettings { current in
      current.outputFormatPreset = preset
    }
    statusLine = "Output format: \(outputFormatPresetLabel(preset))"
  }

  func setIncludeProductContextLinePreference(_ include: Bool) {
    updateSettings { current in
      current.includeProductContextLine = include
    }
    statusLine = include ? "Product context included in output" : "Product context removed from output"
  }

  func setSummarizationModePreference(_ mode: SummarizationMode) {
    if mode == .llm, settings.summarizationProvider == nil {
      statusLine = "Select an LLM provider before enabling LLM summarization"
      return
    }
    updateSettings { current in
      current.summarizationMode = mode
    }
    statusLine = "Summarization mode: \(summarizationModeLabel(mode))"
  }

  func setSummarizationProviderPreference(_ provider: SummarizationProvider?) {
    updateSettings { current in
      current.summarizationProvider = provider
      if let provider {
        if current.summarizationModel == nil {
          current.summarizationModel = summarizationProviderDefaultModel(provider)
        }
      } else if current.summarizationMode == .llm {
        current.summarizationMode = .heuristic
      }
    }
    statusLine = "Summarization provider: \(summarizationProviderLabel(provider))"
  }

  func setSummarizationModelPreference(_ model: String?) {
    updateSettings { current in
      current.summarizationModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    statusLine = "Summarization model: \(summarizationModelLabel(model))"
  }

  func setSummaryTokenBudgetPreference(_ budget: Int) {
    updateSettings { current in
      current.summaryTokenBudget = sanitizeSummaryTokenBudget(
        budget,
        fallback: HostSettings.defaultSummaryTokenBudget
      )
    }
    statusLine = "Summary budget: ~\(summaryTokenBudget) tokens"
  }

  func openAccessibilitySettings() {
    openDesktopPermissionSettings(.accessibility)
  }

  func openScreenRecordingSettings() {
    openDesktopPermissionSettings(.screenRecording)
  }

  func runDiagnostics() {
    let historyURL = resolvedHistoryDirectoryURL()
    let writable = isDirectoryWritable(historyURL)
    let frontmostApp = effectiveFrontmostAppInfo()
    let target = detectBrowserTarget(
      frontmostBundleIdentifier: frontmostApp.bundleIdentifier,
      frontmostAppName: frontmostApp.appName
    )

    let safariStatus = resolveExtensionDiagnosticsStatus(
      ping: { try safariTransport.ping(timeoutMs: 800) },
      transportStatusPrefix: "safari_extension"
    ) { [logger] error in
      logger.error("Safari diagnostics ping failed: \(error.localizedDescription)")
    }
    let chromeStatus = resolveExtensionDiagnosticsStatus(
      ping: { try chromeTransport.ping(timeoutMs: 800) },
      transportStatusPrefix: "chrome_extension"
    ) { [logger] error in
      logger.error("Chrome diagnostics ping failed: \(error.localizedDescription)")
    }
    let desktopReadiness = desktopPermissionReadiness()
    let accessibilityLabel = desktopReadiness.accessibilityTrusted ? "granted" : "missing"
    let screenLabel = desktopReadiness.screenRecordingGranted.map { $0 ? "granted" : "missing" } ?? "unknown"
    safariDiagnosticsLabel = safariStatus.label
    chromeDiagnosticsLabel = chromeStatus.label
    safariDiagnosticsTransportStatus = safariStatus.transportStatus
    chromeDiagnosticsTransportStatus = chromeStatus.transportStatus
    desktopAccessibilityDiagnosticsLabel = accessibilityLabel
    desktopScreenDiagnosticsLabel = screenLabel

    lastTransportStatus = diagnosticsTransportStatusForTarget(
      target,
      safariStatus: safariStatus,
      chromeStatus: chromeStatus
    )

    let lastCaptureLabel = lastCaptureAt ?? "never"
    let lastErrorLabel = lastTransportErrorCode ?? "none"
    let latencyLabel = lastTransportLatencyMs.map { "\($0)ms" } ?? "n/a"

    let summary = formatDiagnosticsSummary(
      DiagnosticsSummaryContext(
        frontAppDisplayName: target.displayName,
        safariLabel: safariStatus.label,
        chromeLabel: chromeStatus.label,
        desktopAccessibilityLabel: accessibilityLabel,
        desktopScreenLabel: screenLabel,
        lastCaptureLabel: lastCaptureLabel,
        lastErrorLabel: lastErrorLabel,
        latencyLabel: latencyLabel,
        storageWritable: writable,
        historyPath: historyURL.path
      )
    )

    statusLine = summary
    logger.info("Diagnostics: \(summary)")
    refreshSteadyMenuBarIndicatorIfNeeded()
    if !desktopReadiness.accessibilityTrusted {
      logger.error("Accessibility permission is missing. Enable System Settings -> Privacy & Security -> Accessibility for ContextGrabberHost.")
      logger.info("Use menu action: Open Accessibility Settings")
    }
    if let screenGranted = desktopReadiness.screenRecordingGranted, !screenGranted {
      logger.error("Screen Recording permission is missing. Enable System Settings -> Privacy & Security -> Screen Recording for ContextGrabberHost.")
      logger.info("Use menu action: Open Screen Recording Settings")
    }
  }

  func openCodebaseHandbook() {
    guard let repoRoot = resolveRepoRoot(),
      let docsURL = handbookDocumentURL(repoRoot: repoRoot)
    else {
      statusLine = "Unable to locate codebase handbook"
      logger.error("Could not resolve docs/codebase/README.md from current runtime.")
      return
    }

    if NSWorkspace.shared.open(docsURL) {
      statusLine = "Opened codebase handbook"
      logger.info("Opened handbook: \(docsURL.path)")
    } else {
      statusLine = "Unable to open handbook"
      logger.error("Failed to open handbook: \(docsURL.path)")
    }
  }

  private func registerHotkeyMonitors() {
    hotkeyMonitorRegistration = HotkeyMonitorRegistration { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handleHotkeyEvent(event)
      }
    }
  }

  private func registerFrontmostAppObserver() {
    appActivationObserverRegistration = AppActivationObserverRegistration { [weak self] app in
      Task { @MainActor [weak self] in
        self?.recordNonHostFrontmostApp(app)
      }
    }

    recordNonHostFrontmostApp(NSWorkspace.shared.frontmostApplication)
  }

  private func recordNonHostFrontmostApp(_ app: NSRunningApplication?) {
    guard let app else {
      return
    }
    guard app.processIdentifier != hostProcessIdentifier else {
      return
    }

    let frontmostApp = FrontmostAppInfo(
      bundleIdentifier: app.bundleIdentifier,
      appName: app.localizedName,
      processIdentifier: app.processIdentifier
    )
    lastNonHostFrontmostApp = frontmostApp

    let target = detectBrowserTarget(
      frontmostBundleIdentifier: frontmostApp.bundleIdentifier,
      frontmostAppName: frontmostApp.appName
    )
    if case .safari = target {
      lastKnownBrowserFrontmostApp = frontmostApp
    } else if case .chrome = target {
      lastKnownBrowserFrontmostApp = frontmostApp
    }
  }

  private func effectiveFrontmostAppInfo() -> (bundleIdentifier: String?, appName: String?) {
    let current = NSWorkspace.shared.frontmostApplication
    let effective = resolveEffectiveFrontmostApp(
      current: FrontmostAppInfo(
        bundleIdentifier: current?.bundleIdentifier,
        appName: current?.localizedName,
        processIdentifier: current?.processIdentifier
      ),
      lastNonHost: lastNonHostFrontmostApp,
      lastKnownBrowser: lastKnownBrowserFrontmostApp,
      hostProcessIdentifier: hostProcessIdentifier
    )
    return (effective.bundleIdentifier, effective.appName)
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

  private func resolveCapture(request: HostCaptureRequestMessage) async throws -> CaptureResolution {
    let frontmostApp = effectiveFrontmostAppInfo()
    let target = detectBrowserTarget(
      frontmostBundleIdentifier: frontmostApp.bundleIdentifier,
      frontmostAppName: frontmostApp.appName
    )

    if case .unsupported(let appName, let bundleIdentifier) = target {
      let desktopResolution = await resolveDesktopCapture(
        context: DesktopCaptureContext(
          appName: appName,
          bundleIdentifier: bundleIdentifier
        )
      )
      lastTransportStatus = desktopResolution.transportStatus
      lastTransportErrorCode = desktopResolution.errorCode
      return CaptureResolution(
        payload: desktopResolution.payload,
        extractionMethod: desktopResolution.extractionMethod,
        transportStatus: desktopResolution.transportStatus,
        warning: desktopResolution.warning,
        errorCode: desktopResolution.errorCode
      )
    }

    let bridgeResult: Result<ExtensionBridgeMessage, Error> = Result {
      switch target {
      case .safari:
        return try safariTransport.sendCaptureRequest(request, timeoutMs: request.payload.timeoutMs)
      case .chrome:
        let appName = chromiumAppName(forBundleIdentifier: frontmostApp.bundleIdentifier)
        return try chromeTransport.sendCaptureRequest(request, timeoutMs: request.payload.timeoutMs, chromeAppName: appName)
      case .unsupported:
        throw NSError(
          domain: "ContextGrabberHost",
          code: 1003,
          userInfo: [NSLocalizedDescriptionKey: "Unsupported browser target."]
        )
      }
    }

    let resolution = resolveBrowserCapture(
      target: target,
      bridgeResult: bridgeResult,
      frontAppName: frontmostApp.appName
    )
    lastTransportStatus = resolution.transportStatus
    lastTransportErrorCode = resolution.errorCode
    return resolution
  }

  private func setMenuBarIndicator(
    _ state: MenuBarIndicatorState,
    autoResetAfter seconds: TimeInterval? = nil
  ) {
    indicatorResetTask?.cancel()
    indicatorResetToken = UUID()
    indicatorState = state
    menuBarIcon = menuBarIconForIndicatorState(state)

    guard let seconds else {
      return
    }

    let expectedResetToken = indicatorResetToken
    indicatorResetTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      guard !Task.isCancelled else {
        return
      }
      guard let self, self.indicatorResetToken == expectedResetToken else {
        return
      }
      self.setMenuBarIndicator(self.resolveSteadyMenuBarIndicatorState())
    }
  }

  private func resolveSteadyMenuBarIndicatorState() -> MenuBarIndicatorState {
    return steadyMenuBarIndicatorState(
      safariDiagnosticsTransportStatus: safariDiagnosticsTransportStatus,
      chromeDiagnosticsTransportStatus: chromeDiagnosticsTransportStatus,
      latestTransportStatus: lastTransportStatus
    )
  }

  private func refreshSteadyMenuBarIndicatorIfNeeded() {
    switch indicatorState {
    case .capturing, .success, .error:
      return
    case .idle, .disconnected:
      setMenuBarIndicator(resolveSteadyMenuBarIndicatorState())
    }
  }

  private func payloadTargetLabel(for payload: BrowserContextPayload) -> String {
    let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !title.isEmpty {
      return title
    }
    return payload.url
  }

  private func payloadSourceLabel(for payload: BrowserContextPayload) -> String {
    if payload.source == "desktop" {
      return "Desktop"
    }
    if payload.browser.isEmpty {
      return "Browser"
    }
    return payload.browser.capitalized
  }

  private func clearCaptureFeedback() {
    feedbackDismissTask?.cancel()
    feedbackState = nil
    captureResultPopup.hide()
  }

  private func presentCaptureFeedback(
    kind: CaptureFeedbackKind,
    detail: String,
    sourceLabel: String?,
    targetLabel: String?,
    extractionMethod: String?,
    warning: String?,
    fileURL: URL?,
    fileName: String?,
    tokenCount: Int? = nil,
    autoDismissAfter: TimeInterval
  ) {
    let state = CaptureFeedbackState(
      id: UUID(),
      kind: kind,
      title: formatCaptureFeedbackTitle(kind: kind),
      detail: detail,
      sourceLabel: sourceLabel,
      targetLabel: targetLabel,
      extractionMethod: extractionMethod,
      warning: warning,
      fileURL: fileURL,
      fileName: fileName,
      tokenCount: tokenCount,
      shownAt: Date(),
      autoDismissAfter: autoDismissAfter
    )

    feedbackDismissTask?.cancel()
    feedbackState = state
    captureResultPopup.show(
      state: state,
      onCopy: fileURL == nil ? nil : { [weak self] in
        self?.copyFeedbackCaptureToClipboard()
      },
      onOpen: fileURL == nil ? nil : { [weak self] in
        self?.openFeedbackCaptureFile()
      },
      onDismiss: { [weak self] in
        self?.dismissCaptureFeedback()
      }
    )
    let expectedID = state.id

    feedbackDismissTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(state.autoDismissAfter * 1_000_000_000))
      guard !Task.isCancelled else {
        return
      }
      guard let self, self.feedbackState?.id == expectedID else {
        return
      }
      self.feedbackState = nil
      self.captureResultPopup.hide()
    }
  }

  private func updateLastCaptureLabel() {
    lastCaptureLabel = formatRelativeLastCaptureLabel(isoTimestamp: lastCaptureAt)
  }

  private func updateSettings(_ change: (inout HostSettings) -> Void) {
    change(&settings)
    saveHostSettings(settings)
    applySettingsToPublishedState()
  }

  private func applySettingsToPublishedState() {
    retentionMaxFileCount = settings.retentionMaxFileCount
    retentionMaxAgeDays = settings.retentionMaxAgeDays
    capturesPausedPlaceholder = settings.capturesPausedPlaceholder
    clipboardCopyMode = settings.clipboardCopyMode
    outputFormatPreset = settings.outputFormatPreset
    includeProductContextLine = settings.includeProductContextLine
    summarizationMode = settings.summarizationMode
    summarizationProvider = settings.summarizationProvider
    summarizationModel = settings.summarizationModel
    summaryTokenBudget = settings.summaryTokenBudget
    usingDefaultOutputDirectory = settings.outputDirectoryURL == nil
    outputDirectoryLabel = settings.outputDirectoryURL?.path ?? "Default"
  }

  private func resolvedHistoryDirectoryURL() -> URL {
    if let outputDirectoryURL = settings.outputDirectoryURL {
      return outputDirectoryURL
    }
    return Self.historyDirectoryURL()
  }

  private func ensureHistoryDirectoryExists(_ historyURL: URL) -> Bool {
    do {
      try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
      return true
    } catch {
      logger.error("Failed creating history directory: \(historyURL.path) | \(error.localizedDescription)")
      return false
    }
  }

  private func applyRetentionPolicy() {
    let historyURL = resolvedHistoryDirectoryURL()
    guard ensureHistoryDirectoryExists(historyURL) else {
      return
    }

    let files = (try? FileManager.default.contentsOfDirectory(
      at: historyURL,
      includingPropertiesForKeys: nil
    )) ?? []

    let markdownFiles = filterHostGeneratedCaptureFiles(files)
    guard !markdownFiles.isEmpty else {
      return
    }

    let policy = HostRetentionPolicy(
      maxFileCount: retentionMaxFileCount,
      maxFileAgeDays: retentionMaxAgeDays
    )

    let candidates = retentionPruneCandidates(
      files: markdownFiles,
      policy: policy
    ) { fileURL in
      let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
      return attributes?[.modificationDate] as? Date
    }

    for fileURL in candidates {
      do {
        try FileManager.default.removeItem(at: fileURL)
      } catch {
        logger.error("Failed pruning history file: \(fileURL.path) | \(error.localizedDescription)")
      }
    }
  }

  private func refreshRecentCaptures(limit: Int = 5) {
    recentCaptures = Self.loadRecentCaptureEntries(
      historyURL: resolvedHistoryDirectoryURL(),
      limit: limit
    )
    if lastCaptureAt == nil, let capturedAt = recentCaptures.first?.capturedAt {
      lastCaptureAt = ISO8601DateFormatter().string(from: capturedAt)
      updateLastCaptureLabel()
    }
  }

  private static func loadRecentCaptureEntries(
    historyURL: URL,
    limit: Int,
    fileManager: FileManager = .default
  ) -> [CaptureHistoryEntry] {
    let files = (try? fileManager.contentsOfDirectory(
      at: historyURL,
      includingPropertiesForKeys: nil
    )) ?? []

    return recentHostCaptureFiles(files, limit: limit)
      .map { fileURL in
        let title = captureTitleFromMarkdown(at: fileURL)
          ?? fileURL.deletingPathExtension().lastPathComponent
        return CaptureHistoryEntry(
          fileURL: fileURL,
          title: title,
          capturedAt: captureDateFromFilename(fileURL.lastPathComponent)
        )
      }
  }

  private static func captureTitleFromMarkdown(at fileURL: URL) -> String? {
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return nil
    }

    for line in content.split(separator: "\n", omittingEmptySubsequences: false).prefix(40) {
      let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
      guard rawLine.hasPrefix("title:") else {
        continue
      }
      let value = rawLine.dropFirst("title:".count).trimmingCharacters(in: .whitespacesAndNewlines)
      return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    return nil
  }

  private static func captureDateFromFilename(_ filename: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"

    let stem = filename.split(separator: "-").prefix(2).joined(separator: "-")
    guard !stem.isEmpty else {
      return nil
    }
    return formatter.date(from: stem)
  }

  private func openDesktopPermissionSettings(_ pane: DesktopPermissionPane) {
    guard let url = desktopPermissionSettingsURL(for: pane) else {
      statusLine = "Invalid \(pane.displayName) settings URL"
      logger.error("Invalid settings URL for pane: \(pane.displayName)")
      return
    }

    if NSWorkspace.shared.open(url) {
      statusLine = "Opened \(pane.displayName) settings"
      logger.info("Opened settings pane: \(pane.displayName)")
    } else {
      statusLine = "Unable to open \(pane.displayName) settings"
      logger.error("Failed to open settings pane: \(pane.displayName)")
    }
  }

  private func presentDesktopPermissionsPopup(extractionMethod: String) {
    let readiness = desktopPermissionReadiness()
    let accessibilityLabel = readiness.accessibilityTrusted ? "granted" : "missing"
    let screenLabel = readiness.screenRecordingGranted.map { $0 ? "granted" : "missing" } ?? "unknown"
    let fallbackDescription = desktopPermissionsPopupFallbackDescription(
      extractionMethod: extractionMethod
    )

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Desktop capture needs permissions"
    alert.informativeText = """
    \(fallbackDescription)
    Approve Accessibility and Screen Recording for Context Grabber, then retry.

    Accessibility: \(accessibilityLabel)
    Screen Recording: \(screenLabel)
    """
    alert.addButton(withTitle: "Open Accessibility Settings")
    alert.addButton(withTitle: "Open Screen Recording Settings")
    alert.addButton(withTitle: "Dismiss")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      openDesktopPermissionSettings(.accessibility)
    case .alertSecondButtonReturn:
      openDesktopPermissionSettings(.screenRecording)
    default:
      break
    }
  }

  private func createCaptureOutput(
    from payload: BrowserContextPayload,
    extractionMethod: String,
    requestID: String,
    capturedAt: String
  ) async throws -> MarkdownCaptureOutput {
    let summarySections = await resolveSummarizationSections(
      payload: payload,
      settings: settings,
      outputPreset: settings.outputFormatPreset
    )
    let markdown = renderMarkdown(
      requestID: requestID,
      capturedAt: capturedAt,
      extractionMethod: extractionMethod,
      payload: payload,
      outputPreset: settings.outputFormatPreset,
      includeProductContextLine: settings.includeProductContextLine,
      summaryOverride: summarySections.summary,
      keyPointsOverride: summarySections.keyPoints,
      additionalWarnings: summarySections.warnings,
      summaryTokenBudget: settings.summaryTokenBudget
    )

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
    let filePrefix = dateFormatter.string(from: Date())

    let filename = "\(filePrefix)-\(requestID.prefix(8)).md"
    let fileURL = resolvedHistoryDirectoryURL().appendingPathComponent(filename, isDirectory: false)

    return MarkdownCaptureOutput(requestID: requestID, markdown: markdown, fileURL: fileURL)
  }

  private func writeMarkdown(_ output: MarkdownCaptureOutput) throws {
    let historyURL = resolvedHistoryDirectoryURL()
    try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
    try output.markdown.write(to: output.fileURL, atomically: true, encoding: .utf8)
  }

  private func copyCaptureOutputToClipboard(_ output: MarkdownCaptureOutput) throws {
    switch settings.clipboardCopyMode {
    case .markdownFile:
      try copyFileToClipboard(output.fileURL)
    case .text:
      try copyTextToClipboard(output.markdown)
    }
  }

  private func copyCaptureFileToClipboard(_ fileURL: URL) throws {
    switch settings.clipboardCopyMode {
    case .markdownFile:
      try copyFileToClipboard(fileURL)
    case .text:
      let content = try String(contentsOf: fileURL, encoding: .utf8)
      try copyTextToClipboard(content)
    }
  }

  private func copyTextToClipboard(_ text: String) throws {
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

  private func copyFileToClipboard(_ fileURL: URL) throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let wrote = pasteboard.writeObjects([fileURL as NSURL])
    if !wrote {
      throw NSError(
        domain: "ContextGrabberHost",
        code: 1003,
        userInfo: [NSLocalizedDescriptionKey: "Failed to write capture file to clipboard."]
      )
    }
  }

  private func resolveAppVersionLabel(bundle: Bundle = .main) -> String {
    let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return formatAppVersionLabel(shortVersion: shortVersion, buildVersion: buildVersion)
  }

  private func resolveRepoRoot(maxDepth: Int = 12) -> URL? {
    if let envRoot = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_REPO_ROOT"], !envRoot.isEmpty {
      let explicitRoot = URL(fileURLWithPath: envRoot, isDirectory: true)
      if hasRepoMarker(at: explicitRoot), handbookDocumentURL(repoRoot: explicitRoot) != nil {
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

      if let resolvedRoot = findRepoRoot(startingAt: candidate, maxDepth: maxDepth) {
        return resolvedRoot
      }
    }

    return nil
  }

  private func findRepoRoot(startingAt startURL: URL, maxDepth: Int) -> URL? {
    var current = startURL
    for _ in 0..<maxDepth {
      if hasRepoMarker(at: current), handbookDocumentURL(repoRoot: current) != nil {
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
    let marker = rootURL.appendingPathComponent("packages/shared-types/package.json", isDirectory: false)
    return fileManager.fileExists(atPath: marker.path)
  }

  private func handbookDocumentURL(repoRoot: URL) -> URL? {
    let docsURL = repoRoot.appendingPathComponent("docs/codebase/README.md", isDirectory: false)
    if fileManager.fileExists(atPath: docsURL.path) {
      return docsURL
    }
    return nil
  }

  private static func documentsBaseURL() -> URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Documents", isDirectory: true)
    return base.appendingPathComponent("ContextGrabber", isDirectory: true)
  }

  private static func historyDirectoryURL() -> URL {
    return documentsBaseURL().appendingPathComponent("history", isDirectory: true)
  }
}

@main
struct ContextGrabberHostApp: App {
  @StateObject private var model = ContextGrabberModel()
  @Environment(\.openWindow) private var openWindow

  var body: some Scene {
    MenuBarExtra {
      VStack(alignment: .leading, spacing: 6) {
        Text("Context Grabber 🤏")
          .font(.headline)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 2)

        Text(model.lastCaptureLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 4)

        if let feedback = model.feedbackState {
          captureFeedbackView(feedback)
        }

        Divider()
          .padding(.vertical, 4)

        Button("Capture Now (⌃⌥⌘C)") {
          model.captureNow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()
          .padding(.vertical, 4)

        Menu("Recent Captures") {
          if model.recentCaptures.isEmpty {
            Text("No captures yet")
              .foregroundStyle(.secondary)
          } else {
            ForEach(model.recentCaptures) { entry in
              Button(entry.menuLabel) {
                model.openCaptureFile(entry.fileURL)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button("Copy Last Capture To Clipboard") {
          model.copyLastCaptureToClipboard()
        }
        .disabled(model.recentCaptures.isEmpty)
        .frame(maxWidth: .infinity, alignment: .leading)

        Button("Open Capture History Folder") {
          model.openRecentCaptures()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()
          .padding(.vertical, 4)

        Menu("System Readiness") {
          Text("Safari Extension: \(model.safariDiagnosticsLabel)")
            .foregroundStyle(.secondary)
          Text("Chrome Extension: \(model.chromeDiagnosticsLabel)")
            .foregroundStyle(.secondary)
          Text("Desktop Accessibility: \(model.desktopAccessibilityDiagnosticsLabel)")
            .foregroundStyle(.secondary)
          Text("Screen Recording: \(model.desktopScreenDiagnosticsLabel)")
            .foregroundStyle(.secondary)

          Divider()
          Button("Refresh Diagnostics") {
            model.runDiagnostics()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button("Open Accessibility Settings") {
          model.openAccessibilitySettings()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button("Open Screen Recording Settings") {
          model.openScreenRecordingSettings()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()
          .padding(.vertical, 4)

        Menu("Settings") {
          Menu("Output Directory") {
            Button(checkmarkMenuOptionLabel(
              valueLabel: "Default Output Directory",
              isSelected: model.usingDefaultOutputDirectory
            )) {
              model.useDefaultOutputDirectory()
            }
            Button(checkmarkMenuOptionLabel(
              valueLabel: "Custom Output Directory",
              isSelected: !model.usingDefaultOutputDirectory
            )) {
              model.chooseCustomOutputDirectory()
            }
          }

          Menu("Clipboard Copy Mode") {
            ForEach(ClipboardCopyMode.allCases, id: \.self) { mode in
              Button(checkmarkMenuOptionLabel(
                valueLabel: clipboardCopyModeLabel(mode),
                isSelected: model.clipboardCopyMode == mode
              )) {
                model.setClipboardCopyModePreference(mode)
              }
            }
          }

          Menu("Output Format") {
            ForEach(OutputFormatPreset.allCases, id: \.self) { preset in
              Button(checkmarkMenuOptionLabel(
                valueLabel: outputFormatPresetLabel(preset),
                isSelected: model.outputFormatPreset == preset
              )) {
                model.setOutputFormatPresetPreference(preset)
              }
            }
          }

          Menu("Product Context Line") {
            Button(checkmarkMenuOptionLabel(
              valueLabel: "On",
              isSelected: model.includeProductContextLine
            )) {
              model.setIncludeProductContextLinePreference(true)
            }
            Button(checkmarkMenuOptionLabel(
              valueLabel: "Off",
              isSelected: !model.includeProductContextLine
            )) {
              model.setIncludeProductContextLinePreference(false)
            }
          }

          Divider()
          Button(model.capturesPausedPlaceholder ? "Resume Captures" : "Pause Captures") {
            model.toggleCapturePausedPlaceholder()
          }

          Divider()
          Button("Advanced Settings...") {
            openWindow(id: advancedSettingsWindowID)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()
          .padding(.vertical, 4)

        Text(model.statusLine)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .frame(maxWidth: .infinity, alignment: .leading)

        Divider()
          .padding(.vertical, 4)

        Menu("About") {
          Text("Context Grabber")
            .font(.headline)
          Text(model.appVersionLabel)
            .foregroundStyle(.secondary)
          Text("Protocol \(protocolVersion)")
            .foregroundStyle(.secondary)

          Divider()
          Button("Open Project on GitHub") {
            NSWorkspace.shared.open(URL(string: "https://github.com/anthonylu23/context_grabber")!)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()
          .padding(.vertical, 4)

        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.top, 12)
      .padding(.bottom, 12)
      .padding(.horizontal, 8)
    } label: {
      if model.menuBarIcon.isSystemSymbol {
        Label("Context Grabber", systemImage: model.menuBarIcon.name)
      } else {
        Text(model.menuBarIcon.name)
      }
    }
    .menuBarExtraStyle(.window)

    WindowGroup("Advanced Settings", id: advancedSettingsWindowID) {
      AdvancedSettingsView(model: model)
    }
    .defaultSize(width: 560, height: 620)
  }

  @ViewBuilder
  private func captureFeedbackView(_ feedback: CaptureFeedbackState) -> some View {
    let accent = feedback.kind == .success ? Color.green : Color.orange
    let symbol = feedback.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"

    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: symbol)
          .foregroundStyle(accent)
        VStack(alignment: .leading, spacing: 2) {
          Text(feedback.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(feedback.detail)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(3)
          if let fileName = feedback.fileName {
            Text(fileName)
              .font(.caption2)
              .foregroundStyle(accent)
              .lineLimit(1)
          }
          if let tokenLabel = formatTokenEstimateLabel(feedback.tokenCount) {
            Text(tokenLabel)
              .font(.caption2)
              .foregroundStyle(accent)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }

      HStack(spacing: 6) {
        Button("Copy") {
          model.copyFeedbackCaptureToClipboard()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.mini)
        .disabled(feedback.fileURL == nil)

        Button("Open") {
          model.openFeedbackCaptureFile()
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(feedback.fileURL == nil)

        Button("Dismiss") {
          model.dismissCaptureFeedback()
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)

        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(accent.opacity(0.12))
    )
  }

  private static func menuBarNSImage(named name: String) -> NSImage {
    guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
          let image = NSImage(contentsOf: url)
    else {
      return NSImage()
    }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
  }
}

func checkmarkMenuOptionLabel(valueLabel: String, isSelected: Bool) -> String {
  return isSelected ? "✓ \(valueLabel)" : valueLabel
}
