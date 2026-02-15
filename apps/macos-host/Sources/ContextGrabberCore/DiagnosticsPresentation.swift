import Foundation

public typealias ExtensionDiagnosticsStatus = (label: String, transportStatus: String)

public struct DiagnosticsSummaryContext: Sendable {
  public let frontAppDisplayName: String
  public let safariLabel: String
  public let chromeLabel: String
  public let desktopAccessibilityLabel: String
  public let desktopScreenLabel: String
  public let lastCaptureLabel: String
  public let lastErrorLabel: String
  public let latencyLabel: String
  public let storageWritable: Bool
  public let historyPath: String

  public init(
    frontAppDisplayName: String,
    safariLabel: String,
    chromeLabel: String,
    desktopAccessibilityLabel: String,
    desktopScreenLabel: String,
    lastCaptureLabel: String,
    lastErrorLabel: String,
    latencyLabel: String,
    storageWritable: Bool,
    historyPath: String
  ) {
    self.frontAppDisplayName = frontAppDisplayName
    self.safariLabel = safariLabel
    self.chromeLabel = chromeLabel
    self.desktopAccessibilityLabel = desktopAccessibilityLabel
    self.desktopScreenLabel = desktopScreenLabel
    self.lastCaptureLabel = lastCaptureLabel
    self.lastErrorLabel = lastErrorLabel
    self.latencyLabel = latencyLabel
    self.storageWritable = storageWritable
    self.historyPath = historyPath
  }
}

public func resolveExtensionDiagnosticsStatus(
  ping: () throws -> NativeMessagingPingResponse,
  transportStatusPrefix: String,
  expectedProtocolVersion: String = protocolVersion,
  onFailure: ((Error) -> Void)? = nil
) -> ExtensionDiagnosticsStatus {
  do {
    let response = try ping()
    if response.ok && response.protocolVersion == expectedProtocolVersion {
      return ("reachable/protocol \(expectedProtocolVersion)", "\(transportStatusPrefix)_ok")
    }
    if response.ok {
      return ("reachable/protocol mismatch", "\(transportStatusPrefix)_protocol_mismatch")
    }
    return ("unreachable", "\(transportStatusPrefix)_unreachable")
  } catch {
    onFailure?(error)
    return ("unreachable", "\(transportStatusPrefix)_unreachable")
  }
}

public func diagnosticsTransportStatusForTarget(
  _ target: BrowserTarget,
  safariStatus: ExtensionDiagnosticsStatus,
  chromeStatus: ExtensionDiagnosticsStatus
) -> String {
  switch target {
  case .chrome:
    return chromeStatus.transportStatus
  case .safari:
    return safariStatus.transportStatus
  case .unsupported:
    return "desktop_capture_ready"
  }
}

public func formatDiagnosticsSummary(_ context: DiagnosticsSummaryContext) -> String {
  return
    "Front app: \(context.frontAppDisplayName) | Safari: \(context.safariLabel) | Chrome: \(context.chromeLabel) | Desktop AX: \(context.desktopAccessibilityLabel) | Screen: \(context.desktopScreenLabel) | Last capture: \(context.lastCaptureLabel) | Last error: \(context.lastErrorLabel) | Latency: \(context.latencyLabel) | Storage writable: \(context.storageWritable ? "yes" : "no") | History: \(context.historyPath)"
}
