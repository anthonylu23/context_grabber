import Foundation

public enum SafariNativeMessagingTransportError: LocalizedError, Sendable {
  case repoRootNotFound
  case extensionPackageNotFound
  case launchFailed(String)
  case timedOut
  case processFailed(exitCode: Int32, stderr: String)
  case emptyOutput
  case invalidJSON(String)

  public var errorDescription: String? {
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

public enum ChromeNativeMessagingTransportError: LocalizedError, Sendable {
  case repoRootNotFound
  case extensionPackageNotFound
  case launchFailed(String)
  case timedOut
  case processFailed(exitCode: Int32, stderr: String)
  case emptyOutput
  case invalidJSON(String)

  public var errorDescription: String? {
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

struct ProcessExecutionResult {
  let stdout: Data
  let stderr: Data
  let exitCode: Int32
}

public final class SafariNativeMessagingTransport: @unchecked Sendable {
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let fileManager = FileManager.default

  public init() {}

  public func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int) throws -> ExtensionBridgeMessage {
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

  public func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
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
    let processExited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      processExited.signal()
    }

    do {
      try process.run()
    } catch {
      throw SafariNativeMessagingTransportError.launchFailed(error.localizedDescription)
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
        throw SafariNativeMessagingTransportError.launchFailed("Failed to write request payload: \(error.localizedDescription)")
      }
    }
    stdinPipe.fileHandleForWriting.closeFile()

    let waitResult = processExited.wait(timeout: .now() + .milliseconds(max(1, timeoutMs)))
    if waitResult == .timedOut {
      process.terminate()
      _ = processExited.wait(timeout: .now() + .milliseconds(200))
      throw SafariNativeMessagingTransportError.timedOut
    }

    _ = stdoutReadDone.wait(timeout: .now() + .milliseconds(500))
    _ = stderrReadDone.wait(timeout: .now() + .milliseconds(500))
    let stdoutData = stdoutResult.get() ?? stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrResult.get() ?? stderrPipe.fileHandleForReading.readDataToEndOfFile()

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

public final class ChromeNativeMessagingTransport: @unchecked Sendable {
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let fileManager = FileManager.default

  public init() {}

  public func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int, chromeAppName: String? = nil) throws -> ExtensionBridgeMessage {
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

  public func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
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
    let processExited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in
      processExited.signal()
    }

    do {
      try process.run()
    } catch {
      throw ChromeNativeMessagingTransportError.launchFailed(error.localizedDescription)
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
        throw ChromeNativeMessagingTransportError.launchFailed("Failed to write request payload: \(error.localizedDescription)")
      }
    }
    stdinPipe.fileHandleForWriting.closeFile()

    let waitResult = processExited.wait(timeout: .now() + .milliseconds(max(1, timeoutMs)))
    if waitResult == .timedOut {
      process.terminate()
      _ = processExited.wait(timeout: .now() + .milliseconds(200))
      throw ChromeNativeMessagingTransportError.timedOut
    }

    _ = stdoutReadDone.wait(timeout: .now() + .milliseconds(500))
    _ = stderrReadDone.wait(timeout: .now() + .milliseconds(500))
    let stdoutData = stdoutResult.get() ?? stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrResult.get() ?? stderrPipe.fileHandleForReading.readDataToEndOfFile()

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
