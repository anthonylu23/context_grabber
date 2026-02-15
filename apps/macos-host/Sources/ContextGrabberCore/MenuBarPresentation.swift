import Foundation

public enum MenuBarIndicatorState: Sendable {
  case idle
  case capturing
  case success
  case error
  case disconnected
}

public enum CaptureFeedbackKind: Sendable {
  case success
  case failure
}

public struct CaptureFeedbackState: Identifiable, Sendable {
  public let id: UUID
  public let kind: CaptureFeedbackKind
  public let title: String
  public let detail: String
  public let sourceLabel: String?
  public let targetLabel: String?
  public let extractionMethod: String?
  public let warning: String?
  public let fileURL: URL?
  public let fileName: String?
  public let tokenCount: Int?
  public let shownAt: Date
  public let autoDismissAfter: TimeInterval

  public init(
    id: UUID,
    kind: CaptureFeedbackKind,
    title: String,
    detail: String,
    sourceLabel: String?,
    targetLabel: String?,
    extractionMethod: String?,
    warning: String?,
    fileURL: URL?,
    fileName: String?,
    tokenCount: Int?,
    shownAt: Date,
    autoDismissAfter: TimeInterval
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.sourceLabel = sourceLabel
    self.targetLabel = targetLabel
    self.extractionMethod = extractionMethod
    self.warning = warning
    self.fileURL = fileURL
    self.fileName = fileName
    self.tokenCount = tokenCount
    self.shownAt = shownAt
    self.autoDismissAfter = autoDismissAfter
  }
}

public struct CaptureHistoryEntry: Identifiable, Sendable {
  public let fileURL: URL
  public let title: String
  public let capturedAt: Date?

  public var id: String {
    return fileURL.path
  }

  public var timestampLabel: String {
    guard let capturedAt else {
      return "Unknown time"
    }
    return menuTimestampFormatter.string(from: capturedAt)
  }

  public var menuLabel: String {
    return "\(timestampLabel) - \(title)"
  }

  public init(fileURL: URL, title: String, capturedAt: Date?) {
    self.fileURL = fileURL
    self.title = title
    self.capturedAt = capturedAt
  }
}

private let menuTimestampFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "MMM d, HH:mm"
  return formatter
}()

public struct MenuBarIcon: Sendable {
  public let name: String
  public let isSystemSymbol: Bool

  public init(name: String, isSystemSymbol: Bool) {
    self.name = name
    self.isSystemSymbol = isSystemSymbol
  }
}

public func menuBarIconForIndicatorState(_ state: MenuBarIndicatorState) -> MenuBarIcon {
  switch state {
  case .idle:
    return MenuBarIcon(name: "\u{1F90F}", isSystemSymbol: false)
  case .capturing:
    return MenuBarIcon(name: "arrow.triangle.2.circlepath.circle.fill", isSystemSymbol: true)
  case .success:
    return MenuBarIcon(name: "checkmark.circle.fill", isSystemSymbol: true)
  case .error:
    return MenuBarIcon(name: "exclamationmark.triangle.fill", isSystemSymbol: true)
  case .disconnected:
    return MenuBarIcon(name: "smallcircle.filled.circle", isSystemSymbol: true)
  }
}

public func formatCaptureFeedbackTitle(kind: CaptureFeedbackKind) -> String {
  switch kind {
  case .success:
    return "Capture saved"
  case .failure:
    return "Capture failed"
  }
}

public func formatCaptureSuccessFeedbackDetail(
  sourceLabel: String,
  targetLabel: String,
  extractionMethod: String,
  transportStatus: String,
  warning _: String?
) -> String {
  return "\(sourceLabel): \(targetLabel) | method: \(extractionMethod) | transport: \(transportStatus)"
}

public func formatCaptureFailureFeedbackDetail(_ errorDescription: String) -> String {
  return "Error: \(errorDescription)"
}

public func formatTokenEstimateLabel(_ tokenCount: Int?) -> String? {
  guard let tokenCount else {
    return nil
  }

  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.groupingSeparator = ","
  let formatted = formatter.string(from: NSNumber(value: tokenCount)) ?? "\(tokenCount)"
  return "~\(formatted) tokens"
}

public func formatAppVersionLabel(shortVersion: String?, buildVersion: String?) -> String {
  let short = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
  let build = buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

  if let short, !short.isEmpty, let build, !build.isEmpty {
    return "Version \(short) (build \(build))"
  }

  if let short, !short.isEmpty {
    return "Version \(short)"
  }

  if let build, !build.isEmpty {
    return "Build \(build)"
  }

  return "Version dev"
}

public func shouldShowDisconnectedIndicator(
  safariTransportStatus: String,
  chromeTransportStatus: String
) -> Bool {
  let connectedSuffix = "_ok"
  let safariConnected = safariTransportStatus.hasSuffix(connectedSuffix)
  let chromeConnected = chromeTransportStatus.hasSuffix(connectedSuffix)
  return !(safariConnected || chromeConnected)
}

public func steadyMenuBarIndicatorState(
  safariDiagnosticsTransportStatus: String,
  chromeDiagnosticsTransportStatus: String,
  latestTransportStatus: String
) -> MenuBarIndicatorState {
  var safariStatus = safariDiagnosticsTransportStatus
  var chromeStatus = chromeDiagnosticsTransportStatus

  if latestTransportStatus.hasPrefix("safari_extension_") {
    safariStatus = latestTransportStatus
  } else if latestTransportStatus.hasPrefix("chrome_extension_") {
    chromeStatus = latestTransportStatus
  }

  if safariStatus == "unknown" && chromeStatus == "unknown" {
    return .idle
  }

  if shouldShowDisconnectedIndicator(
    safariTransportStatus: safariStatus,
    chromeTransportStatus: chromeStatus
  ) {
    return .disconnected
  }

  return .idle
}

public func formatRelativeLastCaptureLabel(
  isoTimestamp: String?,
  now: Date = Date()
) -> String {
  guard let isoTimestamp else {
    return "Last capture: never"
  }

  let formatter = ISO8601DateFormatter()
  guard let date = formatter.date(from: isoTimestamp) else {
    return "Last capture: unknown"
  }

  let delta = max(0, Int(now.timeIntervalSince(date)))
  if delta < 45 {
    return "Last capture: just now"
  }
  if delta < 3600 {
    return "Last capture: \(max(1, delta / 60))m ago"
  }
  if delta < 86_400 {
    return "Last capture: \(max(1, delta / 3600))h ago"
  }
  return "Last capture: \(max(1, delta / 86_400))d ago"
}
