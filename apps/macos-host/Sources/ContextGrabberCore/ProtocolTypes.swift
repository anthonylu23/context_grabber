import Foundation

public struct BrowserContextPayload: Codable, Sendable {
  public let source: String
  public let browser: String
  public let url: String
  public let title: String
  public let fullText: String
  public let headings: [Heading]
  public let links: [Link]
  public let metaDescription: String?
  public let siteName: String?
  public let language: String?
  public let author: String?
  public let publishedTime: String?
  public let selectionText: String?
  public let extractionWarnings: [String]?

  public struct Heading: Codable, Sendable {
    public let level: Int
    public let text: String

    public init(level: Int, text: String) {
      self.level = level
      self.text = text
    }
  }

  public struct Link: Codable, Sendable {
    public let text: String
    public let href: String

    public init(text: String, href: String) {
      self.text = text
      self.href = href
    }
  }

  public init(
    source: String,
    browser: String,
    url: String,
    title: String,
    fullText: String,
    headings: [Heading],
    links: [Link],
    metaDescription: String?,
    siteName: String?,
    language: String?,
    author: String?,
    publishedTime: String?,
    selectionText: String?,
    extractionWarnings: [String]?
  ) {
    self.source = source
    self.browser = browser
    self.url = url
    self.title = title
    self.fullText = fullText
    self.headings = headings
    self.links = links
    self.metaDescription = metaDescription
    self.siteName = siteName
    self.language = language
    self.author = author
    self.publishedTime = publishedTime
    self.selectionText = selectionText
    self.extractionWarnings = extractionWarnings
  }
}

public struct HostCaptureRequestPayload: Codable, Sendable {
  public let protocolVersion: String
  public let requestId: String
  public let mode: String
  public let requestedAt: String
  public let timeoutMs: Int
  public let includeSelectionText: Bool

  public init(
    protocolVersion: String,
    requestId: String,
    mode: String,
    requestedAt: String,
    timeoutMs: Int,
    includeSelectionText: Bool
  ) {
    self.protocolVersion = protocolVersion
    self.requestId = requestId
    self.mode = mode
    self.requestedAt = requestedAt
    self.timeoutMs = timeoutMs
    self.includeSelectionText = includeSelectionText
  }
}

public struct HostCaptureRequestMessage: Codable, Sendable {
  public let id: String
  public let type: String
  public let timestamp: String
  public let payload: HostCaptureRequestPayload

  public init(id: String, type: String, timestamp: String, payload: HostCaptureRequestPayload) {
    self.id = id
    self.type = type
    self.timestamp = timestamp
    self.payload = payload
  }
}

public struct ExtensionCaptureResponsePayload: Codable, Sendable {
  public let protocolVersion: String
  public let capture: BrowserContextPayload

  public init(protocolVersion: String, capture: BrowserContextPayload) {
    self.protocolVersion = protocolVersion
    self.capture = capture
  }
}

public struct ExtensionCaptureResponseMessage: Codable, Sendable {
  public let id: String
  public let type: String
  public let timestamp: String
  public let payload: ExtensionCaptureResponsePayload

  public init(id: String, type: String, timestamp: String, payload: ExtensionCaptureResponsePayload) {
    self.id = id
    self.type = type
    self.timestamp = timestamp
    self.payload = payload
  }
}

public struct ExtensionErrorPayload: Codable, Sendable {
  public let protocolVersion: String
  public let code: String
  public let message: String
  public let recoverable: Bool
  public let details: [String: String]?

  public init(
    protocolVersion: String,
    code: String,
    message: String,
    recoverable: Bool,
    details: [String: String]?
  ) {
    self.protocolVersion = protocolVersion
    self.code = code
    self.message = message
    self.recoverable = recoverable
    self.details = details
  }
}

public struct ExtensionErrorMessage: Codable, Sendable {
  public let id: String
  public let type: String
  public let timestamp: String
  public let payload: ExtensionErrorPayload

  public init(id: String, type: String, timestamp: String, payload: ExtensionErrorPayload) {
    self.id = id
    self.type = type
    self.timestamp = timestamp
    self.payload = payload
  }
}

public struct GenericEnvelope: Codable, Sendable {
  public let id: String
  public let type: String
  public let timestamp: String

  public init(id: String, type: String, timestamp: String) {
    self.id = id
    self.type = type
    self.timestamp = timestamp
  }
}

public enum ExtensionBridgeMessage: Sendable {
  case captureResult(ExtensionCaptureResponseMessage)
  case error(ExtensionErrorMessage)
}

public struct NativeMessagingPingResponse: Codable, Sendable {
  public let ok: Bool
  public let protocolVersion: String

  public init(ok: Bool, protocolVersion: String) {
    self.ok = ok
    self.protocolVersion = protocolVersion
  }
}
