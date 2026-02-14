import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import SwiftUI
import UserNotifications
import Vision

private let protocolVersion = "1"
private let defaultCaptureTimeoutMs = 1_200
private let hotkeyKeyCodeC: UInt16 = 8
private let hotkeyModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
private let hotkeyDebounceWindowSeconds = 0.25
let maxBrowserFullTextChars = 200_000
let maxRawExcerptChars = 8_000
let minimumAccessibilityTextChars = 400
private let safariBundleIdentifiers: Set<String> = [
  "com.apple.Safari",
  "com.apple.SafariTechnologyPreview",
]
private let chromeBundleIdentifiers: Set<String> = [
  "com.google.Chrome",
  "com.google.Chrome.canary",
]

struct BrowserContextPayload: Codable {
  let source: String
  let browser: String
  let url: String
  let title: String
  let fullText: String
  let headings: [Heading]
  let links: [Link]
  let metaDescription: String?
  let siteName: String?
  let language: String?
  let author: String?
  let publishedTime: String?
  let selectionText: String?
  let extractionWarnings: [String]?

  struct Heading: Codable {
    let level: Int
    let text: String
  }

  struct Link: Codable {
    let text: String
    let href: String
  }
}

struct HostCaptureRequestPayload: Codable {
  let protocolVersion: String
  let requestId: String
  let mode: String
  let requestedAt: String
  let timeoutMs: Int
  let includeSelectionText: Bool
}

struct HostCaptureRequestMessage: Codable {
  let id: String
  let type: String
  let timestamp: String
  let payload: HostCaptureRequestPayload
}

struct ExtensionCaptureResponsePayload: Codable {
  let protocolVersion: String
  let capture: BrowserContextPayload
}

struct ExtensionCaptureResponseMessage: Codable {
  let id: String
  let type: String
  let timestamp: String
  let payload: ExtensionCaptureResponsePayload
}

struct ExtensionErrorPayload: Codable {
  let protocolVersion: String
  let code: String
  let message: String
  let recoverable: Bool
  let details: [String: String]?
}

struct ExtensionErrorMessage: Codable {
  let id: String
  let type: String
  let timestamp: String
  let payload: ExtensionErrorPayload
}

private struct GenericEnvelope: Codable {
  let id: String
  let type: String
  let timestamp: String
}

enum ExtensionBridgeMessage {
  case captureResult(ExtensionCaptureResponseMessage)
  case error(ExtensionErrorMessage)
}

struct NativeMessagingPingResponse: Codable {
  let ok: Bool
  let protocolVersion: String
}

struct MarkdownCaptureOutput {
  let requestID: String
  let markdown: String
  let fileURL: URL
}

struct CaptureResolution {
  let payload: BrowserContextPayload
  let extractionMethod: String
  let transportStatus: String
  let warning: String?
  let errorCode: String?
}

enum BrowserTarget {
  case safari
  case chrome
  case unsupported(appName: String?, bundleIdentifier: String?)

  var browserLabel: String {
    switch self {
    case .safari:
      return "safari"
    case .chrome:
      return "chrome"
    case .unsupported(_, let bundleIdentifier):
      if let bundleIdentifier, bundleIdentifier.contains("Chrome") {
        return "chrome"
      }
      if let bundleIdentifier, bundleIdentifier.contains("Safari") {
        return "safari"
      }
      return "unknown"
    }
  }

  var transportStatusPrefix: String {
    switch self {
    case .safari:
      return "safari_extension"
    case .chrome:
      return "chrome_extension"
    case .unsupported:
      return "desktop_capture"
    }
  }

  var displayName: String {
    switch self {
    case .safari:
      return "Safari"
    case .chrome:
      return "Chrome"
    case .unsupported(let appName, _):
      return appName ?? "Unknown App"
    }
  }
}

func detectBrowserTarget(
  frontmostBundleIdentifier: String?,
  frontmostAppName: String?,
  overrideValue: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_BROWSER_TARGET"]
) -> BrowserTarget {
  if let overrideValue {
    let normalized = overrideValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "safari" {
      return .safari
    }
    if normalized == "chrome" {
      return .chrome
    }
  }

  if let frontmostBundleIdentifier {
    if safariBundleIdentifiers.contains(frontmostBundleIdentifier) {
      return .safari
    }
    if chromeBundleIdentifiers.contains(frontmostBundleIdentifier) {
      return .chrome
    }
  }

  return .unsupported(appName: frontmostAppName, bundleIdentifier: frontmostBundleIdentifier)
}

struct FrontmostAppInfo {
  let bundleIdentifier: String?
  let appName: String?
  let processIdentifier: pid_t?
}

func resolveEffectiveFrontmostApp(
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

func createMetadataOnlyBrowserPayload(
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

struct DesktopCaptureContext {
  let appName: String?
  let bundleIdentifier: String?
}

struct DesktopCaptureResolution {
  let payload: BrowserContextPayload
  let extractionMethod: String
  let transportStatus: String
  let warning: String?
  let errorCode: String?
}

struct OCRCaptureResult {
  let text: String
  let confidence: Double?
}

struct DesktopPermissionReadiness {
  let accessibilityTrusted: Bool
  let screenRecordingGranted: Bool?
}

final class SynchronousResultBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  func set(_ newValue: Value?) {
    lock.lock()
    value = newValue
    lock.unlock()
  }

  func get() -> Value? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

enum DesktopPermissionPane {
  case accessibility
  case screenRecording

  var privacyAnchor: String {
    switch self {
    case .accessibility:
      return "Privacy_Accessibility"
    case .screenRecording:
      return "Privacy_ScreenCapture"
    }
  }

  var displayName: String {
    switch self {
    case .accessibility:
      return "Accessibility"
    case .screenRecording:
      return "Screen Recording"
    }
  }
}

func desktopPermissionSettingsURL(for pane: DesktopPermissionPane) -> URL? {
  return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.privacyAnchor)")
}

func buildDesktopOriginURL(bundleIdentifier: String?) -> String {
  return "app://\(bundleIdentifier ?? "unknown")"
}

func normalizeDesktopText(_ value: String?) -> String {
  guard let value else {
    return ""
  }

  return value
    .replacingOccurrences(of: "\r\n", with: "\n")
    .replacingOccurrences(of: "\r", with: "\n")
    .replacingOccurrences(of: "[ \t]+\n", with: "\n", options: .regularExpression)
    .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

func copyAXStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute, &value)
  guard result == .success, let value else {
    return nil
  }

  if let stringValue = value as? String {
    return stringValue
  }
  if let attributedValue = value as? NSAttributedString {
    return attributedValue.string
  }

  return nil
}

func asAXUIElement(_ value: CFTypeRef?) -> AXUIElement? {
  guard let value else {
    return nil
  }

  let expectedType = AXUIElementGetTypeID()
  guard CFGetTypeID(value) == expectedType else {
    return nil
  }

  return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
}

func collectAccessibilityTextFromElement(_ element: AXUIElement) -> String? {
  let attributes: [CFString] = [
    kAXSelectedTextAttribute as CFString,
    kAXValueAttribute as CFString,
    kAXDescriptionAttribute as CFString,
    kAXTitleAttribute as CFString,
    kAXHelpAttribute as CFString,
  ]

  var segments: [String] = []
  var seen = Set<String>()
  for attribute in attributes {
    guard let value = copyAXStringAttribute(element, attribute) else {
      continue
    }

    let normalized = normalizeDesktopText(value)
    guard !normalized.isEmpty else {
      continue
    }
    if seen.contains(normalized) {
      continue
    }

    seen.insert(normalized)
    segments.append(normalized)
  }

  if segments.isEmpty {
    return nil
  }

  return segments.joined(separator: "\n\n")
}

func extractAccessibilityTextFromFocusedElement(
  frontmostProcessIdentifier: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier
) -> String? {
  guard AXIsProcessTrusted() else {
    return nil
  }

  var segments: [String] = []
  var seen = Set<String>()

  let appendUnique = { (text: String?) in
    guard let text else {
      return
    }
    let normalized = normalizeDesktopText(text)
    guard !normalized.isEmpty else {
      return
    }
    if seen.contains(normalized) {
      return
    }

    seen.insert(normalized)
    segments.append(normalized)
  }

  let systemWide = AXUIElementCreateSystemWide()
  var focusedValue: CFTypeRef?
  if AXUIElementCopyAttributeValue(
    systemWide,
    kAXFocusedUIElementAttribute as CFString,
    &focusedValue
  ) == .success,
    let focusedElement = asAXUIElement(focusedValue)
  {
    appendUnique(collectAccessibilityTextFromElement(focusedElement))
  }

  if let frontmostProcessIdentifier {
    let appElement = AXUIElementCreateApplication(frontmostProcessIdentifier)

    var appFocusedValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedUIElementAttribute as CFString,
      &appFocusedValue
    ) == .success,
      let appFocusedElement = asAXUIElement(appFocusedValue)
    {
      appendUnique(collectAccessibilityTextFromElement(appFocusedElement))
    }

    var focusedWindowValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowValue
    ) == .success,
      let focusedWindowElement = asAXUIElement(focusedWindowValue)
    {
      appendUnique(collectAccessibilityTextFromElement(focusedWindowElement))
    }
  }

  if segments.isEmpty {
    return nil
  }

  return segments.joined(separator: "\n\n")
}

func frontmostWindowIDFromWindowList(
  _ windowList: [[String: Any]],
  frontmostProcessIdentifier: pid_t?
) -> CGWindowID? {
  for window in windowList {
    if let frontmostProcessIdentifier,
      let ownerPid = window[kCGWindowOwnerPID as String] as? Int,
      pid_t(ownerPid) != frontmostProcessIdentifier
    {
      continue
    }

    let layer = (window[kCGWindowLayer as String] as? Int) ?? 0
    if layer != 0 {
      continue
    }

    if let windowID = window[kCGWindowNumber as String] as? UInt32 {
      return windowID
    }
    if let windowID = window[kCGWindowNumber as String] as? Int, windowID >= 0 {
      return UInt32(windowID)
    }
  }

  return nil
}

func shareableDesktopContent(
  excludeDesktopWindows: Bool = true,
  onScreenWindowsOnly: Bool = true
) async -> SCShareableContent? {
  let resultBox = SynchronousResultBox<SCShareableContent>()
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    SCShareableContent.getExcludingDesktopWindows(
      excludeDesktopWindows,
      onScreenWindowsOnly: onScreenWindowsOnly
    ) { shareableContent, _ in
      resultBox.set(shareableContent)
      continuation.resume()
    }
  }
  return resultBox.get()
}

func captureImageWithScreenCaptureKit(
  contentFilter: SCContentFilter,
  pixelWidth: Int,
  pixelHeight: Int
) async -> CGImage? {
  let configuration = SCStreamConfiguration()
  configuration.width = max(1, pixelWidth)
  configuration.height = max(1, pixelHeight)
  configuration.showsCursor = false

  let resultBox = SynchronousResultBox<CGImage>()
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, _ in
      resultBox.set(image)
      continuation.resume()
    }
  }
  return resultBox.get()
}

func captureFrontmostWindowImage(
  frontmostProcessIdentifier: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier
) async -> CGImage? {
  let windowList = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
  ) as? [[String: Any]]
  let frontmostWindowID = windowList.flatMap {
    frontmostWindowIDFromWindowList($0, frontmostProcessIdentifier: frontmostProcessIdentifier)
  }

  guard let shareableContent = await shareableDesktopContent(
    excludeDesktopWindows: true,
    onScreenWindowsOnly: true
  ) else {
    return nil
  }

  if let targetWindow = shareableContent.windows.first(where: { window in
    if let frontmostWindowID, window.windowID == frontmostWindowID {
      return true
    }
    if let frontmostProcessIdentifier,
      window.owningApplication?.processID == frontmostProcessIdentifier,
      window.windowLayer == 0
    {
      return true
    }
    return false
  }) {
    let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
    let pointScale = max(1.0, Double(filter.pointPixelScale))
    let pixelWidth = Int((targetWindow.frame.width * pointScale).rounded(.up))
    let pixelHeight = Int((targetWindow.frame.height * pointScale).rounded(.up))

    if let image = await captureImageWithScreenCaptureKit(
      contentFilter: filter,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    ) {
      return image
    }
  }

  if let display = shareableContent.displays.first {
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let pixelWidth = max(1, Int(display.width))
    let pixelHeight = max(1, Int(display.height))

    if let image = await captureImageWithScreenCaptureKit(
      contentFilter: filter,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    ) {
      return image
    }
  }

  return nil
}

func extractOCRTextFromFrontmostWindow(
  frontmostProcessIdentifier: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier
) async -> OCRCaptureResult? {
  guard let image = await captureFrontmostWindowImage(frontmostProcessIdentifier: frontmostProcessIdentifier)
  else {
    return nil
  }

  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.usesLanguageCorrection = true

  let handler = VNImageRequestHandler(cgImage: image, options: [:])
  do {
    try handler.perform([request])
  } catch {
    return nil
  }

  guard let observations = request.results, !observations.isEmpty else {
    return nil
  }

  var textSegments: [String] = []
  var confidenceSum: Double = 0
  var confidenceCount = 0

  for observation in observations {
    guard let candidate = observation.topCandidates(1).first else {
      continue
    }

    let normalized = normalizeDesktopText(candidate.string)
    guard !normalized.isEmpty else {
      continue
    }

    textSegments.append(normalized)
    confidenceSum += Double(candidate.confidence)
    confidenceCount += 1
  }

  let text = normalizeDesktopText(textSegments.joined(separator: "\n"))
  guard !text.isEmpty else {
    return nil
  }

  let averageConfidence = confidenceCount > 0 ? (confidenceSum / Double(confidenceCount)) : nil
  return OCRCaptureResult(text: text, confidence: averageConfidence)
}

func desktopPermissionReadiness(
  isAccessibilityTrusted: () -> Bool = { AXIsProcessTrusted() },
  screenRecordingGranted: () -> Bool? = {
    if #available(macOS 10.15, *) {
      return CGPreflightScreenCaptureAccess()
    }
    return nil
  }
) -> DesktopPermissionReadiness {
  return DesktopPermissionReadiness(
    accessibilityTrusted: isAccessibilityTrusted(),
    screenRecordingGranted: screenRecordingGranted()
  )
}

func resolveDesktopCapture(
  context: DesktopCaptureContext,
  accessibilityTextOverride: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_DESKTOP_AX_TEXT"],
  ocrTextOverride: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_DESKTOP_OCR_TEXT"],
  accessibilityExtractor: () -> String? = { extractAccessibilityTextFromFocusedElement() },
  ocrExtractor: () async -> OCRCaptureResult? = { await extractOCRTextFromFrontmostWindow() }
) async -> DesktopCaptureResolution {
  let appName = context.appName ?? "Desktop App"
  let originURL = buildDesktopOriginURL(bundleIdentifier: context.bundleIdentifier)
  let accessibilityText = normalizeDesktopText(accessibilityTextOverride ?? accessibilityExtractor())

  if accessibilityText.count >= minimumAccessibilityTextChars {
    let payload = BrowserContextPayload(
      source: "desktop",
      browser: "desktop",
      url: originURL,
      title: appName,
      fullText: accessibilityText,
      headings: [],
      links: [],
      metaDescription: nil,
      siteName: appName,
      language: nil,
      author: nil,
      publishedTime: nil,
      selectionText: nil,
      extractionWarnings: nil
    )

    return DesktopCaptureResolution(
      payload: payload,
      extractionMethod: "accessibility",
      transportStatus: "desktop_capture_accessibility",
      warning: nil,
      errorCode: nil
    )
  }

  let axFallbackWarning: String = if accessibilityText.isEmpty {
    "AX extraction unavailable; used OCR fallback text."
  } else {
    "AX extraction below threshold (\(accessibilityText.count) chars); used OCR fallback text."
  }

  let extractedOcr = await ocrExtractor()
  let ocrText = normalizeDesktopText(ocrTextOverride ?? extractedOcr?.text)
  if !ocrText.isEmpty {
    let payload = BrowserContextPayload(
      source: "desktop",
      browser: "desktop",
      url: originURL,
      title: appName,
      fullText: ocrText,
      headings: [],
      links: [],
      metaDescription: nil,
      siteName: appName,
      language: nil,
      author: nil,
      publishedTime: nil,
      selectionText: nil,
      extractionWarnings: [axFallbackWarning]
    )

    return DesktopCaptureResolution(
      payload: payload,
      extractionMethod: "ocr",
      transportStatus: "desktop_capture_ocr",
      warning: axFallbackWarning,
      errorCode: nil
    )
  }

  let fallbackWarning: String = if accessibilityText.isEmpty {
    "AX and OCR extraction unavailable."
  } else {
    "AX extraction below threshold (\(accessibilityText.count) chars) and OCR extraction unavailable."
  }
  let fallbackWarnings: [String] = if accessibilityText.isEmpty {
    [fallbackWarning]
  } else {
    [axFallbackWarning, "OCR extraction unavailable."]
  }
  let payload = BrowserContextPayload(
    source: "desktop",
    browser: "desktop",
    url: originURL,
    title: appName,
    fullText: accessibilityText,
    headings: [],
    links: [],
    metaDescription: nil,
    siteName: appName,
    language: nil,
    author: nil,
    publishedTime: nil,
    selectionText: nil,
    extractionWarnings: fallbackWarnings
  )

  return DesktopCaptureResolution(
    payload: payload,
    extractionMethod: "metadata_only",
    transportStatus: "desktop_capture_metadata_only",
    warning: fallbackWarning,
    errorCode: "ERR_EXTENSION_UNAVAILABLE"
  )
}

func createBrowserMetadataFallbackResolution(
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

func resolveBrowserCapture(
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
    if let safariTransportError = error as? SafariNativeMessagingTransportError,
      case .timedOut = safariTransportError
    {
      return createBrowserMetadataFallbackResolution(
        target: target,
        code: "ERR_TIMEOUT",
        message: "Timed out waiting for extension response.",
        details: nil,
        frontAppName: frontAppName
      )
    }

    if let chromeTransportError = error as? ChromeNativeMessagingTransportError,
      case .timedOut = chromeTransportError
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

enum SafariNativeMessagingTransportError: LocalizedError {
  case repoRootNotFound
  case extensionPackageNotFound
  case launchFailed(String)
  case timedOut
  case processFailed(exitCode: Int32, stderr: String)
  case emptyOutput
  case invalidJSON(String)

  var errorDescription: String? {
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

private struct ProcessExecutionResult {
  let stdout: Data
  let stderr: Data
  let exitCode: Int32
}

final class SafariNativeMessagingTransport {
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let fileManager = FileManager.default

  func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int) throws -> ExtensionBridgeMessage {
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

  func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
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

    do {
      try process.run()
    } catch {
      throw SafariNativeMessagingTransportError.launchFailed(error.localizedDescription)
    }

    if let stdinData {
      stdinPipe.fileHandleForWriting.write(stdinData)
    }
    stdinPipe.fileHandleForWriting.closeFile()

    let timeoutDate = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
    while process.isRunning && Date() < timeoutDate {
      _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    if process.isRunning {
      process.terminate()
      throw SafariNativeMessagingTransportError.timedOut
    }

    process.waitUntilExit()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

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

enum ChromeNativeMessagingTransportError: LocalizedError {
  case repoRootNotFound
  case extensionPackageNotFound
  case launchFailed(String)
  case timedOut
  case processFailed(exitCode: Int32, stderr: String)
  case emptyOutput
  case invalidJSON(String)

  var errorDescription: String? {
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

final class ChromeNativeMessagingTransport {
  private let jsonEncoder = JSONEncoder()
  private let jsonDecoder = JSONDecoder()
  private let fileManager = FileManager.default

  func sendCaptureRequest(_ request: HostCaptureRequestMessage, timeoutMs: Int) throws -> ExtensionBridgeMessage {
    let requestData = try jsonEncoder.encode(request)
    let processResult = try runNativeMessaging(arguments: [], stdinData: requestData, timeoutMs: timeoutMs)

    if !processResult.stdout.isEmpty, let decodedMessage = try? decodeBridgeMessage(processResult.stdout) {
      return decodedMessage
    }

    if processResult.exitCode != 0 {
      let stderr = String(data: processResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw ChromeNativeMessagingTransportError.processFailed(exitCode: processResult.exitCode, stderr: stderr)
    }

    return try decodeBridgeMessage(processResult.stdout)
  }

  func ping(timeoutMs: Int = 800) throws -> NativeMessagingPingResponse {
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

    do {
      try process.run()
    } catch {
      throw ChromeNativeMessagingTransportError.launchFailed(error.localizedDescription)
    }

    if let stdinData {
      stdinPipe.fileHandleForWriting.write(stdinData)
    }
    stdinPipe.fileHandleForWriting.closeFile()

    let timeoutDate = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
    while process.isRunning && Date() < timeoutDate {
      _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    if process.isRunning {
      process.terminate()
      throw ChromeNativeMessagingTransportError.timedOut
    }

    process.waitUntilExit()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

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

final class HostLogger {
  private let logURL: URL

  init() {
    let baseURL = Self.appSupportBaseURL()
    let logsDirectory = baseURL.appendingPathComponent("logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    self.logURL = logsDirectory.appendingPathComponent("host.log", isDirectory: false)
  }

  func info(_ message: String) {
    write(level: "INFO", message: message)
  }

  func error(_ message: String) {
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

private final class HotkeyMonitorRegistration {
  private let globalMonitor: Any?
  private let localMonitor: Any?

  init(handler: @escaping (NSEvent) -> Void) {
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      handler(event)
    }

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handler(event)
      return event
    }
  }

  deinit {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
    }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
    }
  }
}

private final class AppActivationObserverRegistration {
  private let token: NSObjectProtocol

  init(handler: @escaping @Sendable (NSRunningApplication) -> Void) {
    token = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: nil
    ) { notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
        return
      }
      handler(app)
    }
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(token)
  }
}

@MainActor
final class ContextGrabberModel: ObservableObject {
  @Published var statusLine: String = "Ready"

  private let logger = HostLogger()
  private let safariTransport = SafariNativeMessagingTransport()
  private let chromeTransport = ChromeNativeMessagingTransport()
  private let hostProcessIdentifier = ProcessInfo.processInfo.processIdentifier
  private let notificationsEnabled: Bool
  private var hotkeyMonitorRegistration: HotkeyMonitorRegistration?
  private var appActivationObserverRegistration: AppActivationObserverRegistration?
  private var lastNonHostFrontmostApp: FrontmostAppInfo?
  private var lastKnownBrowserFrontmostApp: FrontmostAppInfo?
  private var lastHotkeyFireAt: Date = .distantPast
  private var lastCaptureAt: String?
  private var lastTransportErrorCode: String?
  private var lastTransportLatencyMs: Int?
  private var lastTransportStatus: String = "unknown"
  private var captureInFlight = false

  init() {
    notificationsEnabled = Self.canUseUserNotifications()
    if notificationsEnabled {
      requestNotificationAuthorization()
    } else {
      logger.info("User notifications disabled for unbundled runtime (swift run).")
    }

    registerHotkeyMonitors()
    registerFrontmostAppObserver()
  }

  func captureNow() {
    triggerCapture(mode: "manual_menu")
  }

  private func triggerCapture(mode: String) {
    if captureInFlight {
      statusLine = "Capture already in progress"
      return
    }

    captureInFlight = true
    statusLine = "Capture in progress..."
    Task { @MainActor [weak self] in
      await self?.performCapture(mode: mode)
    }
  }

  private func performCapture(mode: String) async {
    defer { captureInFlight = false }

    do {
      let requestID = UUID().uuidString.lowercased()
      let timestamp = isoTimestamp()

      let request = HostCaptureRequestMessage(
        id: requestID,
        type: "host.capture.request",
        timestamp: timestamp,
        payload: HostCaptureRequestPayload(
          protocolVersion: protocolVersion,
          requestId: requestID,
          mode: mode,
          requestedAt: timestamp,
          timeoutMs: defaultCaptureTimeoutMs,
          includeSelectionText: true
        )
      )

      let transportStart = Date()
      let resolution = try await resolveCapture(request: request)
      lastTransportLatencyMs = Int(Date().timeIntervalSince(transportStart) * 1000.0)
      lastCaptureAt = timestamp

      let output = try createCaptureOutput(
        from: resolution.payload,
        extractionMethod: resolution.extractionMethod,
        requestID: requestID,
        capturedAt: timestamp
      )
      try writeMarkdown(output)
      try copyToClipboard(output.markdown)

      let triggerLabel = mode == "manual_hotkey" ? "hotkey" : "menu"
      let warningCount = resolution.payload.extractionWarnings?.count ?? 0
      statusLine =
        "Captured \(triggerLabel) via \(resolution.extractionMethod) (\(output.requestID.prefix(8))) | \(resolution.transportStatus) | warnings: \(warningCount)"
      logger.info(
        "Capture complete: \(output.fileURL.path) | mode=\(mode) | transport=\(resolution.transportStatus) | latency_ms=\(lastTransportLatencyMs ?? -1)"
      )

      let subtitle = resolution.warning == nil
        ? output.fileURL.lastPathComponent
        : "\(output.fileURL.lastPathComponent) | \(resolution.warning ?? "")"
      postUserNotification(title: "Context Captured", subtitle: subtitle)
    } catch {
      statusLine = "Capture failed"
      logger.error("Capture failed: \(error.localizedDescription)")
      postUserNotification(title: "Capture Failed", subtitle: error.localizedDescription)
    }
  }

  func openRecentCaptures() {
    let historyURL = Self.historyDirectoryURL()
    do {
      try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
      NSWorkspace.shared.open(historyURL)
      statusLine = "Opened history folder"
      logger.info("Opened history folder: \(historyURL.path)")
    } catch {
      statusLine = "Unable to open history folder"
      logger.error("Failed to open history folder: \(error.localizedDescription)")
    }
  }

  func openAccessibilitySettings() {
    openDesktopPermissionSettings(.accessibility)
  }

  func openScreenRecordingSettings() {
    openDesktopPermissionSettings(.screenRecording)
  }

  func runDiagnostics() {
    let historyURL = Self.historyDirectoryURL()
    let writable = FileManager.default.isWritableFile(atPath: Self.appSupportBaseURL().path)
    let frontmostApp = effectiveFrontmostAppInfo()
    let target = detectBrowserTarget(
      frontmostBundleIdentifier: frontmostApp.bundleIdentifier,
      frontmostAppName: frontmostApp.appName
    )

    let safariStatus = diagnosticsStatusForSafari()
    let chromeStatus = diagnosticsStatusForChrome()
    let desktopReadiness = desktopPermissionReadiness()
    let accessibilityLabel = desktopReadiness.accessibilityTrusted ? "granted" : "missing"
    let screenLabel = desktopReadiness.screenRecordingGranted.map { $0 ? "granted" : "missing" } ?? "unknown"

    switch target {
    case .chrome:
      lastTransportStatus = chromeStatus.transportStatus
    case .safari:
      lastTransportStatus = safariStatus.transportStatus
    case .unsupported:
      lastTransportStatus = "desktop_capture_ready"
    }

    let lastCaptureLabel = lastCaptureAt ?? "never"
    let lastErrorLabel = lastTransportErrorCode ?? "none"
    let latencyLabel = lastTransportLatencyMs.map { "\($0)ms" } ?? "n/a"

    let summary =
      "Front app: \(target.displayName) | Safari: \(safariStatus.label) | Chrome: \(chromeStatus.label) | Desktop AX: \(accessibilityLabel) | Screen: \(screenLabel) | Last capture: \(lastCaptureLabel) | Last error: \(lastErrorLabel) | Latency: \(latencyLabel) | Storage writable: \(writable ? "yes" : "no") | History: \(historyURL.path)"

    statusLine = summary
    logger.info("Diagnostics: \(summary)")
    if !desktopReadiness.accessibilityTrusted {
      logger.error("Accessibility permission is missing. Enable System Settings -> Privacy & Security -> Accessibility for ContextGrabberHost.")
      logger.info("Use menu action: Open Accessibility Settings")
    }
    if let screenGranted = desktopReadiness.screenRecordingGranted, !screenGranted {
      logger.error("Screen Recording permission is missing. Enable System Settings -> Privacy & Security -> Screen Recording for ContextGrabberHost.")
      logger.info("Use menu action: Open Screen Recording Settings")
    }
  }

  private func registerHotkeyMonitors() {
    hotkeyMonitorRegistration = HotkeyMonitorRegistration { [weak self] event in
      Task { @MainActor [weak self] in
        self?.handleHotkeyEvent(event)
      }
    }
  }

  private func registerFrontmostAppObserver() {
    appActivationObserverRegistration = AppActivationObserverRegistration { [weak self] app in
      Task { @MainActor [weak self] in
        self?.recordNonHostFrontmostApp(app)
      }
    }

    recordNonHostFrontmostApp(NSWorkspace.shared.frontmostApplication)
  }

  private func recordNonHostFrontmostApp(_ app: NSRunningApplication?) {
    guard let app else {
      return
    }
    guard app.processIdentifier != hostProcessIdentifier else {
      return
    }

    let frontmostApp = FrontmostAppInfo(
      bundleIdentifier: app.bundleIdentifier,
      appName: app.localizedName,
      processIdentifier: app.processIdentifier
    )
    lastNonHostFrontmostApp = frontmostApp

    let target = detectBrowserTarget(
      frontmostBundleIdentifier: frontmostApp.bundleIdentifier,
      frontmostAppName: frontmostApp.appName
    )
    if case .safari = target {
      lastKnownBrowserFrontmostApp = frontmostApp
    } else if case .chrome = target {
      lastKnownBrowserFrontmostApp = frontmostApp
    }
  }

  private func effectiveFrontmostAppInfo() -> (bundleIdentifier: String?, appName: String?) {
    let current = NSWorkspace.shared.frontmostApplication
    let effective = resolveEffectiveFrontmostApp(
      current: FrontmostAppInfo(
        bundleIdentifier: current?.bundleIdentifier,
        appName: current?.localizedName,
        processIdentifier: current?.processIdentifier
      ),
      lastNonHost: lastNonHostFrontmostApp,
      lastKnownBrowser: lastKnownBrowserFrontmostApp,
      hostProcessIdentifier: hostProcessIdentifier
    )
    return (effective.bundleIdentifier, effective.appName)
  }

  private func handleHotkeyEvent(_ event: NSEvent) {
    guard isCaptureHotkey(event) else {
      return
    }

    let now = Date()
    guard now.timeIntervalSince(lastHotkeyFireAt) > hotkeyDebounceWindowSeconds else {
      return
    }
    lastHotkeyFireAt = now

    triggerCapture(mode: "manual_hotkey")
  }

  private func isCaptureHotkey(_ event: NSEvent) -> Bool {
    guard event.keyCode == hotkeyKeyCodeC else {
      return false
    }

    let activeModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
    return activeModifiers == hotkeyModifiers
  }

  private func resolveCapture(request: HostCaptureRequestMessage) async throws -> CaptureResolution {
    let frontmostApp = effectiveFrontmostAppInfo()
    let target = detectBrowserTarget(
      frontmostBundleIdentifier: frontmostApp.bundleIdentifier,
      frontmostAppName: frontmostApp.appName
    )

    if case .unsupported(let appName, let bundleIdentifier) = target {
      let desktopResolution = await resolveDesktopCapture(
        context: DesktopCaptureContext(
          appName: appName,
          bundleIdentifier: bundleIdentifier
        )
      )
      lastTransportStatus = desktopResolution.transportStatus
      lastTransportErrorCode = desktopResolution.errorCode
      return CaptureResolution(
        payload: desktopResolution.payload,
        extractionMethod: desktopResolution.extractionMethod,
        transportStatus: desktopResolution.transportStatus,
        warning: desktopResolution.warning,
        errorCode: desktopResolution.errorCode
      )
    }

    let bridgeResult: Result<ExtensionBridgeMessage, Error> = Result {
      switch target {
      case .safari:
        return try safariTransport.sendCaptureRequest(request, timeoutMs: request.payload.timeoutMs)
      case .chrome:
        return try chromeTransport.sendCaptureRequest(request, timeoutMs: request.payload.timeoutMs)
      case .unsupported:
        throw NSError(
          domain: "ContextGrabberHost",
          code: 1003,
          userInfo: [NSLocalizedDescriptionKey: "Unsupported browser target."]
        )
      }
    }

    let resolution = resolveBrowserCapture(
      target: target,
      bridgeResult: bridgeResult,
      frontAppName: frontmostApp.appName
    )
    lastTransportStatus = resolution.transportStatus
    lastTransportErrorCode = resolution.errorCode
    return resolution
  }

  private func diagnosticsStatusForSafari() -> (label: String, transportStatus: String) {
    do {
      let ping = try safariTransport.ping(timeoutMs: 800)
      if ping.ok && ping.protocolVersion == protocolVersion {
        return ("reachable/protocol \(protocolVersion)", "safari_extension_ok")
      }
      if ping.ok {
        return ("reachable/protocol mismatch", "safari_extension_protocol_mismatch")
      }
      return ("unreachable", "safari_extension_unreachable")
    } catch {
      logger.error("Safari diagnostics ping failed: \(error.localizedDescription)")
      return ("unreachable", "safari_extension_unreachable")
    }
  }

  private func diagnosticsStatusForChrome() -> (label: String, transportStatus: String) {
    do {
      let ping = try chromeTransport.ping(timeoutMs: 800)
      if ping.ok && ping.protocolVersion == protocolVersion {
        return ("reachable/protocol \(protocolVersion)", "chrome_extension_ok")
      }
      if ping.ok {
        return ("reachable/protocol mismatch", "chrome_extension_protocol_mismatch")
      }
      return ("unreachable", "chrome_extension_unreachable")
    } catch {
      logger.error("Chrome diagnostics ping failed: \(error.localizedDescription)")
      return ("unreachable", "chrome_extension_unreachable")
    }
  }

  private func openDesktopPermissionSettings(_ pane: DesktopPermissionPane) {
    guard let url = desktopPermissionSettingsURL(for: pane) else {
      statusLine = "Invalid \(pane.displayName) settings URL"
      logger.error("Invalid settings URL for pane: \(pane.displayName)")
      return
    }

    if NSWorkspace.shared.open(url) {
      statusLine = "Opened \(pane.displayName) settings"
      logger.info("Opened settings pane: \(pane.displayName)")
    } else {
      statusLine = "Unable to open \(pane.displayName) settings"
      logger.error("Failed to open settings pane: \(pane.displayName)")
    }
  }

  private func createCaptureOutput(
    from payload: BrowserContextPayload,
    extractionMethod: String,
    requestID: String,
    capturedAt: String
  ) throws -> MarkdownCaptureOutput {
    let markdown = renderMarkdown(
      requestID: requestID,
      capturedAt: capturedAt,
      extractionMethod: extractionMethod,
      payload: payload
    )

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
    let filePrefix = dateFormatter.string(from: Date())

    let filename = "\(filePrefix)-\(requestID.prefix(8)).md"
    let fileURL = Self.historyDirectoryURL().appendingPathComponent(filename, isDirectory: false)

    return MarkdownCaptureOutput(requestID: requestID, markdown: markdown, fileURL: fileURL)
  }

  private func writeMarkdown(_ output: MarkdownCaptureOutput) throws {
    let historyURL = Self.historyDirectoryURL()
    try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: true)
    try output.markdown.write(to: output.fileURL, atomically: true, encoding: .utf8)
  }

  private func copyToClipboard(_ text: String) throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let wrote = pasteboard.setString(text, forType: .string)
    if !wrote {
      throw NSError(
        domain: "ContextGrabberHost",
        code: 1002,
        userInfo: [NSLocalizedDescriptionKey: "Failed to write capture to clipboard."]
      )
    }
  }

  private func postUserNotification(title: String, subtitle: String) {
    guard notificationsEnabled else {
      return
    }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = subtitle

    let request = UNNotificationRequest(
      identifier: UUID().uuidString.lowercased(),
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        fputs("ContextGrabberHost notification error: \(error.localizedDescription)\n", stderr)
      }
    }
  }

  private func requestNotificationAuthorization() {
    guard notificationsEnabled else {
      return
    }

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
      if let error {
        fputs("ContextGrabberHost notification authorization error: \(error.localizedDescription)\n", stderr)
      }
    }
  }

  private static func canUseUserNotifications() -> Bool {
    if Bundle.main.bundleIdentifier == nil {
      return false
    }

    let bundlePath = Bundle.main.bundleURL.path
    return !bundlePath.contains("/.build/")
  }

  private static func appSupportBaseURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appendingPathComponent("ContextGrabber", isDirectory: true)
  }

  private static func historyDirectoryURL() -> URL {
    return appSupportBaseURL().appendingPathComponent("history", isDirectory: true)
  }
}

@main
struct ContextGrabberHostApp: App {
  @StateObject private var model = ContextGrabberModel()

  var body: some Scene {
    MenuBarExtra("Context Grabber", systemImage: "text.viewfinder") {
      Button("Capture Now (⌃⌥⌘C)") {
        model.captureNow()
      }

      Button("Open Recent Captures") {
        model.openRecentCaptures()
      }

      Button("Run Diagnostics") {
        model.runDiagnostics()
      }

      Button("Open Accessibility Settings") {
        model.openAccessibilitySettings()
      }

      Button("Open Screen Recording Settings") {
        model.openScreenRecordingSettings()
      }

      Divider()
      Text(model.statusLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)

      Divider()
      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
    }
    .menuBarExtraStyle(.window)
  }
}

private func isoTimestamp() -> String {
  return ISO8601DateFormatter().string(from: Date())
}

func renderMarkdown(
  requestID: String,
  capturedAt: String,
  extractionMethod: String,
  payload: BrowserContextPayload
) -> String {
  let isDesktopSource = payload.source == "desktop"
  let normalizedText = payload.fullText.replacingOccurrences(of: "\r\n", with: "\n")
  let trimmedText = String(normalizedText.prefix(maxBrowserFullTextChars))
  let truncated = normalizedText.count > maxBrowserFullTextChars

  let summary = buildSummary(from: trimmedText)
  let keyPoints = buildKeyPoints(from: trimmedText)
  let chunks = buildChunks(from: trimmedText)
  let rawExcerpt = String(trimmedText.prefix(maxRawExcerptChars))

  let warnings = (payload.extractionWarnings ?? [])
    + (truncated ? ["Capture truncated at \(maxBrowserFullTextChars) chars."] : [])
  let tokenEstimate = max(1, Int(ceil(Double(trimmedText.count) / 4.0)))

  var lines: [String] = []
  lines.append("---")
  lines.append("id: \(yamlQuoted(requestID))")
  lines.append("captured_at: \(yamlQuoted(capturedAt))")
  lines.append("source_type: \(yamlQuoted(isDesktopSource ? "desktop_app" : "webpage"))")
  lines.append("origin: \(yamlQuoted(payload.url))")
  lines.append("title: \(yamlQuoted(payload.title))")
  lines.append(
    "app_or_site: \(yamlQuoted(isDesktopSource ? (payload.siteName ?? payload.title) : (payload.siteName ?? hostFromURL(payload.url) ?? payload.browser)))"
  )
  lines.append("extraction_method: \(yamlQuoted(extractionMethod))")
  lines.append("confidence: 0.92")
  lines.append("truncated: \(truncated ? "true" : "false")")
  lines.append("token_estimate: \(tokenEstimate)")
  lines.append("warnings:")

  if warnings.isEmpty {
    lines.append("  - \(yamlQuoted(""))")
  } else {
    warnings.forEach { warning in
      lines.append("  - \(yamlQuoted(warning))")
    }
  }

  lines.append("---")
  lines.append("")
  lines.append("## Summary")
  lines.append(summary)
  lines.append("")
  lines.append("## Key Points")
  if keyPoints.isEmpty {
    lines.append("- (none)")
  } else {
    keyPoints.forEach { point in
      lines.append("- \(point)")
    }
  }

  lines.append("")
  lines.append("## Content Chunks")
  if chunks.isEmpty {
    lines.append("(none)")
  } else {
    chunks.enumerated().forEach { index, chunk in
      lines.append("### chunk-\(String(format: "%03d", index + 1))")
      lines.append(chunk)
      lines.append("")
    }
  }

  lines.append("## Raw Excerpt")
  lines.append("```text")
  lines.append(rawExcerpt)
  lines.append("```")
  lines.append("")
  lines.append("## Links & Metadata")
  lines.append("### Links")
  if payload.links.isEmpty {
    lines.append("- (none)")
  } else {
    payload.links.forEach { link in
      lines.append("- [\(link.text)](\(link.href))")
    }
  }

  lines.append("")
  lines.append("### Metadata")
  if isDesktopSource {
    lines.append("- source: desktop")
    lines.append("- app_name: \(payload.title)")
    lines.append("- app_bundle_id: \(desktopBundleIdentifierFromOrigin(payload.url) ?? "unknown")")
  } else {
    lines.append("- browser: \(payload.browser)")
    lines.append("- url: \(payload.url)")
    if let language = payload.language {
      lines.append("- language: \(language)")
    }
    if let author = payload.author {
      lines.append("- author: \(author)")
    }
  }

  lines.append("")
  return lines.joined(separator: "\n")
}

func buildSummary(from text: String) -> String {
  let sentences = splitSentences(text)
  if sentences.isEmpty {
    return ""
  }

  return sentences.prefix(6).joined(separator: "\n")
}

func buildKeyPoints(from text: String) -> [String] {
  let sentences = splitSentences(text)
  return Array(sentences.prefix(8))
}

func buildChunks(from text: String) -> [String] {
  let paragraphs = text
    .components(separatedBy: "\n\n")
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }

  var chunks: [String] = []
  var currentChunk: [String] = []
  var currentTokens = 0

  for paragraph in paragraphs {
    let paragraphTokens = max(1, Int(ceil(Double(paragraph.count) / 4.0)))
    if currentTokens > 0 && currentTokens + paragraphTokens > 1500 {
      chunks.append(currentChunk.joined(separator: "\n\n"))
      currentChunk = []
      currentTokens = 0
    }

    currentChunk.append(paragraph)
    currentTokens += paragraphTokens
  }

  if !currentChunk.isEmpty {
    chunks.append(currentChunk.joined(separator: "\n\n"))
  }

  return chunks
}

func splitSentences(_ text: String) -> [String] {
  let parts = text.split(separator: ".")
  return parts
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .map { "\($0)." }
}

func hostFromURL(_ urlString: String) -> String? {
  guard let url = URL(string: urlString) else {
    return nil
  }

  return url.host
}

func desktopBundleIdentifierFromOrigin(_ origin: String) -> String? {
  guard let url = URL(string: origin) else {
    return nil
  }

  guard url.scheme == "app" else {
    return nil
  }

  return url.host
}

func yamlQuoted(_ value: String) -> String {
  let escaped = value
    .replacingOccurrences(of: "\\", with: "\\\\")
    .replacingOccurrences(of: "\"", with: "\\\"")
    .replacingOccurrences(of: "\n", with: "\\n")

  return "\"\(escaped)\""
}
