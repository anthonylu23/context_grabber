import Foundation

typealias ExtensionDiagnosticsStatus = (label: String, transportStatus: String)

struct DiagnosticsSummaryContext {
  let frontAppDisplayName: String
  let safariLabel: String
  let chromeLabel: String
  let desktopAccessibilityLabel: String
  let desktopScreenLabel: String
  let lastCaptureLabel: String
  let lastErrorLabel: String
  let latencyLabel: String
  let storageWritable: Bool
  let historyPath: String
}

func resolveExtensionDiagnosticsStatus(
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

func diagnosticsTransportStatusForTarget(
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

func formatDiagnosticsSummary(_ context: DiagnosticsSummaryContext) -> String {
  return
    "Front app: \(context.frontAppDisplayName) | Safari: \(context.safariLabel) | Chrome: \(context.chromeLabel) | Desktop AX: \(context.desktopAccessibilityLabel) | Screen: \(context.desktopScreenLabel) | Last capture: \(context.lastCaptureLabel) | Last error: \(context.lastErrorLabel) | Latency: \(context.latencyLabel) | Storage writable: \(context.storageWritable ? "yes" : "no") | History: \(context.historyPath)"
}
