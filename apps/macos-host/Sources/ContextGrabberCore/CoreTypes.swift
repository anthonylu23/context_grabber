import Foundation

public let protocolVersion = "1"
public let maxBrowserFullTextChars = 200_000
public let maxRawExcerptChars = 8_000

public struct MarkdownCaptureOutput: Sendable {
  public let requestID: String
  public let markdown: String
  public let fileURL: URL

  public init(requestID: String, markdown: String, fileURL: URL) {
    self.requestID = requestID
    self.markdown = markdown
    self.fileURL = fileURL
  }
}

public struct FrontmostAppInfo: Sendable {
  public let bundleIdentifier: String?
  public let appName: String?
  public let processIdentifier: pid_t?

  public init(bundleIdentifier: String?, appName: String?, processIdentifier: pid_t?) {
    self.bundleIdentifier = bundleIdentifier
    self.appName = appName
    self.processIdentifier = processIdentifier
  }
}

public func resolveEffectiveFrontmostApp(
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

public final class HostLogger: @unchecked Sendable {
  private let logURL: URL

  public init() {
    let baseURL = Self.appSupportBaseURL()
    let logsDirectory = baseURL.appendingPathComponent("logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    self.logURL = logsDirectory.appendingPathComponent("host.log", isDirectory: false)
  }

  public func info(_ message: String) {
    write(level: "INFO", message: message)
  }

  public func error(_ message: String) {
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

public func shouldPromptDesktopPermissionsPopup(
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

  let missingAccessibility = !readiness.accessibilityTrusted
  let missingScreenRecording = readiness.screenRecordingGranted == false
  return missingAccessibility || missingScreenRecording
}

public func desktopPermissionsPopupFallbackDescription(extractionMethod: String) -> String {
  switch extractionMethod {
  case "ocr":
    return "This capture fell back to OCR text extraction."
  case "metadata_only":
    return "This capture fell back to metadata-only."
  default:
    return "This capture used a desktop fallback path."
  }
}

public func checkmarkMenuOptionLabel(valueLabel: String, isSelected: Bool) -> String {
  return isSelected ? "✓ \(valueLabel)" : valueLabel
}
