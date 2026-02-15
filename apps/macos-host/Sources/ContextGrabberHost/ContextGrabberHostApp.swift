import AppKit
import Foundation
import SwiftUI
import UserNotifications

private let protocolVersion = "1"
private let defaultCaptureTimeoutMs = 1_200
private let hotkeyKeyCodeC: UInt16 = 8
private let hotkeyModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
private let hotkeyDebounceWindowSeconds = 0.25
let maxBrowserFullTextChars = 200_000
let maxRawExcerptChars = 8_000
private let safariBundleIdentifiers: Set<String> = [
  "com.apple.Safari",
  "com.apple.SafariTechnologyPreview",
]
private let chromeBundleIdentifiers: Set<String> = [
  "com.google.Chrome",
  "com.google.Chrome.canary",
]

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

struct CaptureResolution {
  let payload: BrowserContextPayload
  let extractionMethod: String
  let transportStatus: String
  let warning: String?
  let errorCode: String?
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
    if chromeBundleIdentifiers.contains(frontmostBundleIdentifier) {
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

func createMetadataOnlyBrowserPayload(
  browser: String,
  details: [String: String]?,
  warning: String,
  frontAppName: String?
) -> BrowserContextPayload {
  let title = details?["title"] ?? (frontAppName.map { "\($0) (metadata only)" } ?? "\(browser.capitalized) (metadata only)")
  let url = details?["url"] ?? "about:blank"

  return BrowserContextPayload(
    source: "browser",
    browser: browser,
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

func createBrowserMetadataFallbackResolution(
  target: BrowserTarget,
  code: String,
  message: String,
  details: [String: String]?,
  frontAppName: String?
) -> CaptureResolution {
  let warning = "\(code): \(message)"
  return CaptureResolution(
    payload: createMetadataOnlyBrowserPayload(
      browser: target.browserLabel,
      details: details,
      warning: warning,
      frontAppName: frontAppName
    ),
    extractionMethod: "metadata_only",
    transportStatus: "\(target.transportStatusPrefix)_error:\(code)",
    warning: warning,
    errorCode: code
  )
}

func resolveBrowserCapture(
  target: BrowserTarget,
  bridgeResult: Result<ExtensionBridgeMessage, Error>,
  frontAppName: String?
) -> CaptureResolution {
  switch bridgeResult {
  case .success(let bridgeMessage):
    switch bridgeMessage {
    case .captureResult(let captureResponse):
      if captureResponse.payload.protocolVersion != protocolVersion {
        return createBrowserMetadataFallbackResolution(
          target: target,
          code: "ERR_PROTOCOL_VERSION",
          message: "Protocol version mismatch. Expected \(protocolVersion).",
          details: nil,
          frontAppName: frontAppName
        )
      }

      return CaptureResolution(
        payload: captureResponse.payload.capture,
        extractionMethod: "browser_extension",
        transportStatus: "\(target.transportStatusPrefix)_ok",
        warning: nil,
        errorCode: nil
      )

    case .error(let errorMessage):
      return createBrowserMetadataFallbackResolution(
        target: target,
        code: errorMessage.payload.code,
        message: errorMessage.payload.message,
        details: errorMessage.payload.details,
        frontAppName: frontAppName
      )
    }

  case .failure(let error):
    if let safariTransportError = error as? SafariNativeMessagingTransportError,
      case .timedOut = safariTransportError
    {
      return createBrowserMetadataFallbackResolution(
        target: target,
        code: "ERR_TIMEOUT",
        message: "Timed out waiting for extension response.",
        details: nil,
        frontAppName: frontAppName
      )
    }

    if let chromeTransportError = error as? ChromeNativeMessagingTransportError,
      case .timedOut = chromeTransportError
    {
      return createBrowserMetadataFallbackResolution(
        target: target,
        code: "ERR_TIMEOUT",
        message: "Timed out waiting for extension response.",
        details: nil,
        frontAppName: frontAppName
      )
    }

    return createBrowserMetadataFallbackResolution(
      target: target,
      code: "ERR_EXTENSION_UNAVAILABLE",
      message: error.localizedDescription,
      details: nil,
      frontAppName: frontAppName
    )
  }
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

  func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int) throws -> ExtensionBridgeMessage {
    let requestData = try jsonEncoder.encode(request)
    let processResult = try runNativeMessaging(arguments: [], stdinData: requestData, timeoutMs: timeoutMs)

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
  @Published private(set) var menuBarSymbolName: String = menuBarSymbolNameForIndicatorState(.neutral)
  @Published private(set) var lastCaptureLabel: String = "Last capture: never"
  @Published private(set) var recentCaptures: [CaptureHistoryEntry] = []
  @Published private(set) var outputDirectoryLabel: String = "Default"
  @Published private(set) var retentionMaxFileCount: Int = HostSettings.defaultRetentionMaxFileCount
  @Published private(set) var retentionMaxAgeDays: Int = HostSettings.defaultRetentionMaxAgeDays
  @Published private(set) var capturesPausedPlaceholder = false
  @Published private(set) var safariDiagnosticsLabel: String = "unknown"
  @Published private(set) var chromeDiagnosticsLabel: String = "unknown"
  @Published private(set) var desktopAccessibilityDiagnosticsLabel: String = "unknown"
  @Published private(set) var desktopScreenDiagnosticsLabel: String = "unknown"

  private let logger = HostLogger()
  private let safariTransport = SafariNativeMessagingTransport()
  private let chromeTransport = ChromeNativeMessagingTransport()
  private let hostProcessIdentifier = ProcessInfo.processInfo.processIdentifier
  private let notificationsEnabled: Bool
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
  private var captureInFlight = false
  private var indicatorResetTask: Task<Void, Never>?

  init() {
    settings = loadHostSettings()
    notificationsEnabled = Self.canUseUserNotifications()
    if notificationsEnabled {
      requestNotificationAuthorization()
    } else {
      logger.info("User notifications disabled for unbundled runtime (swift run).")
    }

    registerHotkeyMonitors()
    registerFrontmostAppObserver()
    applySettingsToPublishedState()
    refreshRecentCaptures()
    updateLastCaptureLabel()
  }

  func captureNow() {
    triggerCapture(mode: "manual_menu")
  }

  private func triggerCapture(mode: String) {
    if capturesPausedPlaceholder {
      statusLine = "Captures paused (placeholder)"
      return
    }

    if captureInFlight {
      statusLine = "Capture already in progress"
      return
    }

    captureInFlight = true
    statusLine = "Capture in progress..."
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

      let output = try createCaptureOutput(
        from: resolution.payload,
        extractionMethod: resolution.extractionMethod,
        requestID: requestID,
        capturedAt: timestamp
      )
      try writeMarkdown(output)
      applyRetentionPolicy()
      try copyToClipboard(output.markdown)
      refreshRecentCaptures()
      setMenuBarIndicator(.success, autoResetAfter: 1.5)

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
      setMenuBarIndicator(.failure, autoResetAfter: 2.0)
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
      let content = try String(contentsOf: latest.fileURL, encoding: .utf8)
      try copyToClipboard(content)
      statusLine = "Copied last capture"
      logger.info("Copied last capture from: \(latest.fileURL.path)")
    } catch {
      statusLine = "Unable to copy last capture"
      logger.error("Failed copying last capture: \(error.localizedDescription)")
    }
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

    updateSettings { current in
      current.outputDirectoryPath = selectedURL.path
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
    statusLine = capturesPausedPlaceholder ? "Captures paused (placeholder)" : "Captures resumed"
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

    let safariStatus = diagnosticsStatusForSafari()
    let chromeStatus = diagnosticsStatusForChrome()
    let desktopReadiness = desktopPermissionReadiness()
    let accessibilityLabel = desktopReadiness.accessibilityTrusted ? "granted" : "missing"
    let screenLabel = desktopReadiness.screenRecordingGranted.map { $0 ? "granted" : "missing" } ?? "unknown"
    safariDiagnosticsLabel = safariStatus.label
    chromeDiagnosticsLabel = chromeStatus.label
    desktopAccessibilityDiagnosticsLabel = accessibilityLabel
    desktopScreenDiagnosticsLabel = screenLabel

    switch target {
    case .chrome:
      lastTransportStatus = chromeStatus.transportStatus
    case .safari:
      lastTransportStatus = safariStatus.transportStatus
    case .unsupported:
      lastTransportStatus = "desktop_capture_ready"
    }

    let lastCaptureLabel = lastCaptureAt ?? "never"
    let lastErrorLabel = lastTransportErrorCode ?? "none"
    let latencyLabel = lastTransportLatencyMs.map { "\($0)ms" } ?? "n/a"

    let summary =
      "Front app: \(target.displayName) | Safari: \(safariStatus.label) | Chrome: \(chromeStatus.label) | Desktop AX: \(accessibilityLabel) | Screen: \(screenLabel) | Last capture: \(lastCaptureLabel) | Last error: \(lastErrorLabel) | Latency: \(latencyLabel) | Storage writable: \(writable ? "yes" : "no") | History: \(historyURL.path)"

    statusLine = summary
    logger.info("Diagnostics: \(summary)")
    if shouldShowDisconnectedIndicator(
      safariTransportStatus: safariStatus.transportStatus,
      chromeTransportStatus: chromeStatus.transportStatus
    ) {
      setMenuBarIndicator(.disconnected)
    } else {
      setMenuBarIndicator(.neutral)
    }
    if !desktopReadiness.accessibilityTrusted {
      logger.error("Accessibility permission is missing. Enable System Settings -> Privacy & Security -> Accessibility for ContextGrabberHost.")
      logger.info("Use menu action: Open Accessibility Settings")
    }
    if let screenGranted = desktopReadiness.screenRecordingGranted, !screenGranted {
      logger.error("Screen Recording permission is missing. Enable System Settings -> Privacy & Security -> Screen Recording for ContextGrabberHost.")
      logger.info("Use menu action: Open Screen Recording Settings")
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
        return try chromeTransport.sendCaptureRequest(request, timeoutMs: request.payload.timeoutMs)
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

  private func diagnosticsStatusForSafari() -> (label: String, transportStatus: String) {
    do {
      let ping = try safariTransport.ping(timeoutMs: 800)
      if ping.ok && ping.protocolVersion == protocolVersion {
        return ("reachable/protocol \(protocolVersion)", "safari_extension_ok")
      }
      if ping.ok {
        return ("reachable/protocol mismatch", "safari_extension_protocol_mismatch")
      }
      return ("unreachable", "safari_extension_unreachable")
    } catch {
      logger.error("Safari diagnostics ping failed: \(error.localizedDescription)")
      return ("unreachable", "safari_extension_unreachable")
    }
  }

  private func diagnosticsStatusForChrome() -> (label: String, transportStatus: String) {
    do {
      let ping = try chromeTransport.ping(timeoutMs: 800)
      if ping.ok && ping.protocolVersion == protocolVersion {
        return ("reachable/protocol \(protocolVersion)", "chrome_extension_ok")
      }
      if ping.ok {
        return ("reachable/protocol mismatch", "chrome_extension_protocol_mismatch")
      }
      return ("unreachable", "chrome_extension_unreachable")
    } catch {
      logger.error("Chrome diagnostics ping failed: \(error.localizedDescription)")
      return ("unreachable", "chrome_extension_unreachable")
    }
  }

  private func setMenuBarIndicator(
    _ state: MenuBarIndicatorState,
    autoResetAfter seconds: TimeInterval? = nil
  ) {
    indicatorResetTask?.cancel()
    menuBarSymbolName = menuBarSymbolNameForIndicatorState(state)

    guard let seconds else {
      return
    }

    indicatorResetTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      guard !Task.isCancelled else {
        return
      }
      self?.menuBarSymbolName = menuBarSymbolNameForIndicatorState(.neutral)
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
    let fileURL = resolvedHistoryDirectoryURL().appendingPathComponent(filename, isDirectory: false)

    return MarkdownCaptureOutput(requestID: requestID, markdown: markdown, fileURL: fileURL)
  }

  private func writeMarkdown(_ output: MarkdownCaptureOutput) throws {
    let historyURL = resolvedHistoryDirectoryURL()
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
    MenuBarExtra("Context Grabber", systemImage: model.menuBarSymbolName) {
      VStack(alignment: .leading, spacing: 6) {
        Text(model.lastCaptureLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 4)

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

        Button("Copy Last Capture") {
          model.copyLastCaptureToClipboard()
        }
        .disabled(model.recentCaptures.isEmpty)
        .frame(maxWidth: .infinity, alignment: .leading)

        Button("Open History Folder") {
          model.openRecentCaptures()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider()
          .padding(.vertical, 4)

        Button("Run Diagnostics") {
          model.runDiagnostics()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Menu("Diagnostics Status") {
          Text("Safari: \(model.safariDiagnosticsLabel)")
            .foregroundStyle(.secondary)
          Text("Chrome: \(model.chromeDiagnosticsLabel)")
            .foregroundStyle(.secondary)
          Text("Desktop AX: \(model.desktopAccessibilityDiagnosticsLabel)")
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

        Menu("Preferences") {
          Text("Output: \(model.outputDirectoryLabel)")
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Button("Use Default Output Directory") {
            model.useDefaultOutputDirectory()
          }

          Button("Choose Custom Output Directory...") {
            model.chooseCustomOutputDirectory()
          }

          Divider()
          Menu("Retention Max Files") {
            ForEach(retentionMaxFileCountOptions, id: \.self) { option in
              Button(retentionMenuOptionLabel(
                valueLabel: retentionMaxFileCountLabel(option),
                isSelected: model.retentionMaxFileCount == option
              )) {
                model.setRetentionMaxFileCountPreference(option)
              }
            }
          }

          Menu("Retention Max Age") {
            ForEach(retentionMaxAgeDaysOptions, id: \.self) { option in
              Button(retentionMenuOptionLabel(
                valueLabel: retentionMaxAgeDaysLabel(option),
                isSelected: model.retentionMaxAgeDays == option
              )) {
                model.setRetentionMaxAgeDaysPreference(option)
              }
            }
          }

          Divider()
          Button(model.capturesPausedPlaceholder ? "Resume Captures (Placeholder)" : "Pause Captures (Placeholder)") {
            model.toggleCapturePausedPlaceholder()
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

        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.top, 12)
      .padding(.bottom, 12)
      .padding(.horizontal, 8)
    }
    .menuBarExtraStyle(.window)
  }
}

private func retentionMenuOptionLabel(valueLabel: String, isSelected: Bool) -> String {
  return isSelected ? "✓ \(valueLabel)" : valueLabel
}
