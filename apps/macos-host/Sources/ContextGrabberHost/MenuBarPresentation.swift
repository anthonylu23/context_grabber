import Foundation

enum MenuBarIndicatorState {
  case idle
  case capturing
  case success
  case error
  case disconnected
}

enum CaptureFeedbackKind {
  case success
  case failure
}

struct CaptureFeedbackState: Identifiable {
  let id: UUID
  let kind: CaptureFeedbackKind
  let title: String
  let detail: String
  let sourceLabel: String?
  let targetLabel: String?
  let extractionMethod: String?
  let warning: String?
  let fileURL: URL?
  let fileName: String?
  let tokenCount: Int?
  let shownAt: Date
  let autoDismissAfter: TimeInterval
}

struct CaptureHistoryEntry: Identifiable {
  let fileURL: URL
  let title: String
  let capturedAt: Date?

  var id: String {
    return fileURL.path
  }

  var timestampLabel: String {
    guard let capturedAt else {
      return "Unknown time"
    }
    return menuTimestampFormatter.string(from: capturedAt)
  }

  var menuLabel: String {
    return "\(timestampLabel) - \(title)"
  }
}

private let menuTimestampFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "MMM d, HH:mm"
  return formatter
}()

struct MenuBarIcon {
  let name: String
  let isSystemSymbol: Bool
}

func menuBarIconForIndicatorState(_ state: MenuBarIndicatorState) -> MenuBarIcon {
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

func formatCaptureFeedbackTitle(kind: CaptureFeedbackKind) -> String {
  switch kind {
  case .success:
    return "Capture saved"
  case .failure:
    return "Capture failed"
  }
}

func formatCaptureSuccessFeedbackDetail(
  sourceLabel: String,
  targetLabel: String,
  extractionMethod: String,
  transportStatus: String,
  warning: String?
) -> String {
  var detail = "\(sourceLabel): \(targetLabel) | method: \(extractionMethod) | transport: \(transportStatus)"
  if let warning, !warning.isEmpty {
    detail += " | warning: \(warning)"
  }
  return detail
}

func formatCaptureFailureFeedbackDetail(_ errorDescription: String) -> String {
  return "Error: \(errorDescription)"
}

func formatTokenEstimateLabel(_ tokenCount: Int?) -> String? {
  guard let tokenCount else {
    return nil
  }

  let formatter = NumberFormatter()
  formatter.numberStyle = .decimal
  formatter.groupingSeparator = ","
  let formatted = formatter.string(from: NSNumber(value: tokenCount)) ?? "\(tokenCount)"
  return "~\(formatted) tokens"
}

func formatAppVersionLabel(shortVersion: String?, buildVersion: String?) -> String {
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

func shouldShowDisconnectedIndicator(
  safariTransportStatus: String,
  chromeTransportStatus: String
) -> Bool {
  let connectedSuffix = "_ok"
  let safariConnected = safariTransportStatus.hasSuffix(connectedSuffix)
  let chromeConnected = chromeTransportStatus.hasSuffix(connectedSuffix)
  return !(safariConnected || chromeConnected)
}

func steadyMenuBarIndicatorState(
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

func formatRelativeLastCaptureLabel(
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
