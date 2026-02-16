import Foundation

public struct CaptureResolution: Sendable {
  public let payload: BrowserContextPayload
  public let extractionMethod: String
  public let transportStatus: String
  public let warning: String?
  public let errorCode: String?

  public init(
    payload: BrowserContextPayload,
    extractionMethod: String,
    transportStatus: String,
    warning: String?,
    errorCode: String?
  ) {
    self.payload = payload
    self.extractionMethod = extractionMethod
    self.transportStatus = transportStatus
    self.warning = warning
    self.errorCode = errorCode
  }
}

public func createMetadataOnlyBrowserPayload(
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

public func createBrowserMetadataFallbackResolution(
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

public func resolveBrowserCapture(
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
    if let transportError = error as? NativeMessagingTransportError,
      transportError.isTimeout
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
