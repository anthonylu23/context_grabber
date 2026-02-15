import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import Vision

let minimumAccessibilityTextChars = 400

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

protocol DesktopAccessibilityExtracting {
  func extractFocusedText(frontmostProcessIdentifier: pid_t?) -> String?
}

protocol DesktopOCRExtracting {
  func extractText(frontmostProcessIdentifier: pid_t?) async -> OCRCaptureResult?
}

struct LiveDesktopAccessibilityExtractor: DesktopAccessibilityExtracting {
  func extractFocusedText(frontmostProcessIdentifier: pid_t?) -> String? {
    return extractAccessibilityTextFromFocusedElement(
      frontmostProcessIdentifier: frontmostProcessIdentifier
    )
  }
}

struct LiveDesktopOCRExtractor: DesktopOCRExtracting {
  func extractText(frontmostProcessIdentifier: pid_t?) async -> OCRCaptureResult? {
    return await extractOCRTextFromFrontmostWindow(
      frontmostProcessIdentifier: frontmostProcessIdentifier
    )
  }
}

struct DesktopCaptureDependencies {
  let accessibilityExtractor: (pid_t?) -> String?
  let ocrExtractor: (pid_t?) async -> OCRCaptureResult?

  static func live(
    accessibility: any DesktopAccessibilityExtracting = LiveDesktopAccessibilityExtractor(),
    ocr: any DesktopOCRExtracting = LiveDesktopOCRExtractor()
  ) -> DesktopCaptureDependencies {
    return DesktopCaptureDependencies(
      accessibilityExtractor: { processIdentifier in
        accessibility.extractFocusedText(frontmostProcessIdentifier: processIdentifier)
      },
      ocrExtractor: { processIdentifier in
        await ocr.extractText(frontmostProcessIdentifier: processIdentifier)
      }
    )
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
  onScreenWindowsOnly: Bool = true,
  timeoutSeconds: TimeInterval = 1.5
) async -> SCShareableContent? {
  await withCheckedContinuation { (continuation: CheckedContinuation<SCShareableContent?, Never>) in
    DispatchQueue.global(qos: .userInitiated).async {
      let semaphore = DispatchSemaphore(value: 0)
      let resultBox = SynchronousResultBox<SCShareableContent>()

      SCShareableContent.getExcludingDesktopWindows(
        excludeDesktopWindows,
        onScreenWindowsOnly: onScreenWindowsOnly
      ) { shareableContent, _ in
        resultBox.set(shareableContent)
        semaphore.signal()
      }

      if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
        continuation.resume(returning: nil)
        return
      }

      continuation.resume(returning: resultBox.get())
    }
  }
}

func captureImageWithScreenCaptureKit(
  contentFilter: SCContentFilter,
  pixelWidth: Int,
  pixelHeight: Int,
  timeoutSeconds: TimeInterval = 1.5
) async -> CGImage? {
  let configuration = SCStreamConfiguration()
  configuration.width = max(1, pixelWidth)
  configuration.height = max(1, pixelHeight)
  configuration.showsCursor = false

  return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
    DispatchQueue.global(qos: .userInitiated).async {
      let semaphore = DispatchSemaphore(value: 0)
      let resultBox = SynchronousResultBox<CGImage>()

      SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) {
        image,
        _
        in
        resultBox.set(image)
        semaphore.signal()
      }

      if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
        continuation.resume(returning: nil)
        return
      }

      continuation.resume(returning: resultBox.get())
    }
  }
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
  frontmostProcessIdentifier: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
  dependencies: DesktopCaptureDependencies = .live()
) async -> DesktopCaptureResolution {
  let appName = context.appName ?? "Desktop App"
  let originURL = buildDesktopOriginURL(bundleIdentifier: context.bundleIdentifier)
  let accessibilityText = normalizeDesktopText(
    accessibilityTextOverride ?? dependencies.accessibilityExtractor(frontmostProcessIdentifier)
  )

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

  let extractedOcr = await dependencies.ocrExtractor(frontmostProcessIdentifier)
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

func resolveDesktopCapture(
  context: DesktopCaptureContext,
  accessibilityTextOverride: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_DESKTOP_AX_TEXT"],
  ocrTextOverride: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_DESKTOP_OCR_TEXT"],
  accessibilityExtractor: @escaping () -> String?,
  ocrExtractor: @escaping () async -> OCRCaptureResult?
) async -> DesktopCaptureResolution {
  return await resolveDesktopCapture(
    context: context,
    accessibilityTextOverride: accessibilityTextOverride,
    ocrTextOverride: ocrTextOverride,
    frontmostProcessIdentifier: nil,
    dependencies: DesktopCaptureDependencies(
      accessibilityExtractor: { _ in accessibilityExtractor() },
      ocrExtractor: { _ in await ocrExtractor() }
    )
  )
}
