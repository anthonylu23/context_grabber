import Foundation

// MARK: - Unified transport error

/// Unified error type for Safari and Chrome native messaging transports.
/// The `browser` field carries context about which transport raised the error.
public enum NativeMessagingTransportError: LocalizedError, Sendable {
  case repoRootNotFound(browser: String)
  case extensionPackageNotFound(browser: String)
  case launchFailed(browser: String, reason: String)
  case timedOut(browser: String)
  case processFailed(browser: String, exitCode: Int32, stderr: String)
  case emptyOutput(browser: String)
  case invalidJSON(browser: String, reason: String)

  public var errorDescription: String? {
    switch self {
    case .repoRootNotFound(let browser):
      return "Unable to locate repository root for \(browser) extension bridge."
    case .extensionPackageNotFound(let browser):
      return "\(browser) extension package was not found."
    case .launchFailed(let browser, let reason):
      return "Failed to launch \(browser) extension bridge: \(reason)"
    case .timedOut(let browser):
      return "Timed out waiting for \(browser) extension response."
    case .processFailed(let browser, let exitCode, let stderr):
      return "\(browser) extension bridge failed with exit code \(exitCode): \(stderr)"
    case .emptyOutput(let browser):
      return "\(browser) extension bridge returned no output."
    case .invalidJSON(let browser, let reason):
      return "\(browser) extension bridge returned invalid JSON: \(reason)"
    }
  }

  /// Whether this error represents a timeout.
  public var isTimeout: Bool {
    if case .timedOut = self { return true }
    return false
  }
}

// MARK: - Legacy type aliases (preserved for backward compatibility)

public typealias SafariNativeMessagingTransportError = NativeMessagingTransportError
public typealias ChromeNativeMessagingTransportError = NativeMessagingTransportError

// MARK: - Shared transport infrastructure

struct ProcessExecutionResult {
  let stdout: Data
  let stderr: Data
  let exitCode: Int32
}

/// Shared implementation for native-messaging transport operations.
/// Safari and Chrome transports delegate to this for process management,
/// JSON decoding, bun resolution, and repo root lookup.
final class NativeMessagingTransportCore {
  let browser: String
  let extensionPackageSubpath: String
  let repoMarkerSubpath: String
  let jsonEncoder = JSONEncoder()
  let jsonDecoder = JSONDecoder()
  let fileManager = FileManager.default

  init(browser: String, extensionPackageSubpath: String) {
    self.browser = browser
    self.extensionPackageSubpath = extensionPackageSubpath
    self.repoMarkerSubpath = "\(extensionPackageSubpath)/package.json"
  }

  // MARK: - Bridge message decoding

  func decodeBridgeMessage(_ data: Data) throws -> ExtensionBridgeMessage {
    guard !data.isEmpty else {
      throw NativeMessagingTransportError.emptyOutput(browser: browser)
    }

    let envelope: GenericEnvelope
    do {
      envelope = try jsonDecoder.decode(GenericEnvelope.self, from: data)
    } catch {
      throw NativeMessagingTransportError.invalidJSON(browser: browser, reason: error.localizedDescription)
    }

    switch envelope.type {
    case "extension.capture.result":
      do {
        let capture = try jsonDecoder.decode(ExtensionCaptureResponseMessage.self, from: data)
        return .captureResult(capture)
      } catch {
        throw NativeMessagingTransportError.invalidJSON(browser: browser, reason: error.localizedDescription)
      }
    case "extension.error":
      do {
        let errorMessage = try jsonDecoder.decode(ExtensionErrorMessage.self, from: data)
        return .error(errorMessage)
      } catch {
        throw NativeMessagingTransportError.invalidJSON(browser: browser, reason: error.localizedDescription)
      }
    default:
      throw NativeMessagingTransportError.invalidJSON(browser: browser, reason: "Unsupported message type: \(envelope.type)")
    }
  }

  // MARK: - Process execution

  func runNativeMessaging(arguments: [String], stdinData: Data?, timeoutMs: Int, additionalEnv: [String: String]? = nil) throws -> ProcessExecutionResult {
    let packagePath = try extensionPackagePath()
    let bunExecutablePath = try resolveBunExecutablePath()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: bunExecutablePath)
    process.currentDirectoryURL = packagePath
    let cliPath = packagePath.appendingPathComponent("src/native-messaging-cli.ts", isDirectory: false)
    process.arguments = [cliPath.path] + arguments

    if let additionalEnv, !additionalEnv.isEmpty {
      var env = ProcessInfo.processInfo.environment
      for (key, value) in additionalEnv {
        env[key] = value
      }
      process.environment = env
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdinPipe = Pipe()
    process.standardInput = stdinPipe
    let processExited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      processExited.signal()
    }

    do {
      try process.run()
    } catch {
      throw NativeMessagingTransportError.launchFailed(browser: browser, reason: error.localizedDescription)
    }

    let stdoutResult = SynchronousResultBox<Data>()
    let stderrResult = SynchronousResultBox<Data>()
    let stdoutReadDone = DispatchSemaphore(value: 0)
    let stderrReadDone = DispatchSemaphore(value: 0)

    DispatchQueue.global(qos: .utility).async {
      let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      stdoutResult.set(data)
      stdoutReadDone.signal()
    }
    DispatchQueue.global(qos: .utility).async {
      let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      stderrResult.set(data)
      stderrReadDone.signal()
    }

    if let stdinData {
      do {
        try stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
      } catch {
        if process.isRunning {
          process.terminate()
          _ = processExited.wait(timeout: .now() + .milliseconds(200))
        }
        throw NativeMessagingTransportError.launchFailed(browser: browser, reason: "Failed to write request payload: \(error.localizedDescription)")
      }
    }
    stdinPipe.fileHandleForWriting.closeFile()

    let waitResult = processExited.wait(timeout: .now() + .milliseconds(max(1, timeoutMs)))
    if waitResult == .timedOut {
      process.terminate()
      _ = processExited.wait(timeout: .now() + .milliseconds(200))
      throw NativeMessagingTransportError.timedOut(browser: browser)
    }

    _ = stdoutReadDone.wait(timeout: .now() + .milliseconds(500))
    _ = stderrReadDone.wait(timeout: .now() + .milliseconds(500))
    let stdoutData = stdoutResult.get() ?? stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrResult.get() ?? stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessExecutionResult(stdout: stdoutData, stderr: stderrData, exitCode: process.terminationStatus)
  }

  // MARK: - Path resolution

  func extensionPackagePath() throws -> URL {
    let repoRoot = try resolveRepoRoot()
    let packagePath = repoRoot.appendingPathComponent(extensionPackageSubpath, isDirectory: true)
    let packageManifest = packagePath.appendingPathComponent("package.json", isDirectory: false)

    guard fileManager.fileExists(atPath: packageManifest.path) else {
      throw NativeMessagingTransportError.extensionPackageNotFound(browser: browser)
    }

    return packagePath
  }

  func resolveRepoRoot() throws -> URL {
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

    throw NativeMessagingTransportError.repoRootNotFound(browser: browser)
  }

  func findRepoRoot(startingAt startURL: URL, maxDepth: Int) -> URL? {
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

  func hasRepoMarker(at rootURL: URL) -> Bool {
    let marker = rootURL.appendingPathComponent(repoMarkerSubpath, isDirectory: false)
    return fileManager.fileExists(atPath: marker.path)
  }

  func resolveBunExecutablePath() throws -> String {
    if let explicitPath = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_BUN_BIN"], !explicitPath.isEmpty {
      if fileManager.isExecutableFile(atPath: explicitPath) {
        return explicitPath
      }
      throw NativeMessagingTransportError.launchFailed(
        browser: browser,
        reason: "CONTEXT_GRABBER_BUN_BIN is set but not executable: \(explicitPath)"
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

    throw NativeMessagingTransportError.launchFailed(
      browser: browser,
      reason: "Unable to locate bun executable. Set CONTEXT_GRABBER_BUN_BIN to the bun binary path."
    )
  }
}

// MARK: - Safari transport

public final class SafariNativeMessagingTransport: @unchecked Sendable {
  private let core = NativeMessagingTransportCore(browser: "Safari", extensionPackageSubpath: "packages/extension-safari")

  public init() {}

  public func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int) throws -> ExtensionBridgeMessage {
    let requestData = try core.jsonEncoder.encode(request)
    let processResult = try core.runNativeMessaging(arguments: [], stdinData: requestData, timeoutMs: timeoutMs)

    if !processResult.stdout.isEmpty, let decodedMessage = try? core.decodeBridgeMessage(processResult.stdout) {
      return decodedMessage
    }

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw NativeMessagingTransportError.processFailed(browser: "Safari", exitCode: processResult.exitCode, stderr: stderr)
    }

    return try core.decodeBridgeMessage(processResult.stdout)
  }

  public func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
    let processResult = try core.runNativeMessaging(arguments: ["--ping"], stdinData: nil, timeoutMs: timeoutMs)

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw NativeMessagingTransportError.processFailed(browser: "Safari", exitCode: processResult.exitCode, stderr: stderr)
    }

    guard !processResult.stdout.isEmpty else {
      throw NativeMessagingTransportError.emptyOutput(browser: "Safari")
    }

    do {
      return try core.jsonDecoder.decode(NativeMessagingPingResponse.self, from: processResult.stdout)
    } catch {
      throw NativeMessagingTransportError.invalidJSON(browser: "Safari", reason: error.localizedDescription)
    }
  }
}

// MARK: - Chrome transport

public final class ChromeNativeMessagingTransport: @unchecked Sendable {
  private let core = NativeMessagingTransportCore(browser: "Chrome", extensionPackageSubpath: "packages/extension-chrome")

  public init() {}

  public func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int, chromeAppName: String? = nil) throws -> ExtensionBridgeMessage {
    let requestData = try core.jsonEncoder.encode(request)
    var additionalEnv: [String: String]?
    if let chromeAppName {
      additionalEnv = ["CONTEXT_GRABBER_CHROME_APP_NAME": chromeAppName]
    }
    let processResult = try core.runNativeMessaging(arguments: [], stdinData: requestData, timeoutMs: timeoutMs, additionalEnv: additionalEnv)

    if !processResult.stdout.isEmpty, let decodedMessage = try? core.decodeBridgeMessage(processResult.stdout) {
      return decodedMessage
    }

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw NativeMessagingTransportError.processFailed(browser: "Chrome", exitCode: processResult.exitCode, stderr: stderr)
    }

    return try core.decodeBridgeMessage(processResult.stdout)
  }

  public func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
    let processResult = try core.runNativeMessaging(arguments: ["--ping"], stdinData: nil, timeoutMs: timeoutMs)

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw NativeMessagingTransportError.processFailed(browser: "Chrome", exitCode: processResult.exitCode, stderr: stderr)
    }

    guard !processResult.stdout.isEmpty else {
      throw NativeMessagingTransportError.emptyOutput(browser: "Chrome")
    }

    do {
      return try core.jsonDecoder.decode(NativeMessagingPingResponse.self, from: processResult.stdout)
    } catch {
      throw NativeMessagingTransportError.invalidJSON(browser: "Chrome", reason: error.localizedDescription)
    }
  }
}
