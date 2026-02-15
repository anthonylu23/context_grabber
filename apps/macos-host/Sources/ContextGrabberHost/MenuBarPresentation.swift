import Foundation

enum MenuBarIndicatorState {
  case neutral
  case success
  case failure
  case disconnected
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

func menuBarSymbolNameForIndicatorState(_ state: MenuBarIndicatorState) -> String {
  switch state {
  case .neutral:
    return "text.viewfinder"
  case .success:
    return "checkmark.circle.fill"
  case .failure:
    return "exclamationmark.triangle.fill"
  case .disconnected:
    return "smallcircle.filled.circle"
  }
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
