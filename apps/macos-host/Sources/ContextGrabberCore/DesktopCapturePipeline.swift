import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit
import Vision

public let minimumAccessibilityTextChars = 240
public let defaultAccessibilityTraversalDepth = 2
public let defaultAccessibilityTraversalMaxElements = 96
private let desktopOCRRetryAttempts = 2

private let defaultAccessibilityTextAttributes: [String] = [
  kAXSelectedTextAttribute as String,
  kAXValueAttribute as String,
  kAXDescriptionAttribute as String,
  kAXTitleAttribute as String,
  kAXHelpAttribute as String,
  "AXPlaceholderValue",
  "AXLabelValue",
]

private let defaultAccessibilityChildAttributes: [String] = [
  kAXChildrenAttribute as String,
  "AXVisibleChildren",
  "AXRows",
  "AXColumns",
  "AXContents",
]

private let denseEditorBundlePrefixes: [String] = [
  "com.apple.dt.xcode",
  "com.jetbrains.",
  "com.microsoft.vscode",
  "com.microsoft.vscodeinsiders",
  "org.gnu.emacs",
]

private let terminalBundleIdentifiers: Set<String> = [
  "com.apple.terminal",
  "com.googlecode.iterm2",
  "dev.warp.warp-stable",
]

public struct DesktopAccessibilityExtractionConfig: Sendable {
  public let minimumTextChars: Int
  public let textAttributes: [String]
  public let childAttributes: [String]
  public let traversalDepth: Int
  public let traversalMaxElements: Int

  public init(
    minimumTextChars: Int,
    textAttributes: [String],
    childAttributes: [String],
    traversalDepth: Int,
    traversalMaxElements: Int
  ) {
    self.minimumTextChars = minimumTextChars
    self.textAttributes = textAttributes
    self.childAttributes = childAttributes
    self.traversalDepth = traversalDepth
    self.traversalMaxElements = traversalMaxElements
  }
}

private func deduplicatedStrings(_ values: [String]) -> [String] {
  var seen = Set<String>()
  var result: [String] = []
  result.reserveCapacity(values.count)

  for value in values {
    if seen.contains(value) {
      continue
    }

    seen.insert(value)
    result.append(value)
  }

  return result
}

public struct CFEqualitySet {
  private var buckets: [CFHashCode: [CFTypeRef]] = [:]

  public init() {}

  public func contains(_ value: CFTypeRef) -> Bool {
    let hash = CFHash(value)
    guard let bucket = buckets[hash] else {
      return false
    }

    return bucket.contains { existing in
      return CFEqual(existing, value)
    }
  }

  @discardableResult
  public mutating func insert(_ value: CFTypeRef) -> Bool {
    let hash = CFHash(value)
    var bucket = buckets[hash] ?? []
    if bucket.contains(where: { existing in CFEqual(existing, value) }) {
      return false
    }

    bucket.append(value)
    buckets[hash] = bucket
    return true
  }
}

public func desktopAccessibilityExtractionConfig(
  bundleIdentifier: String?,
  appName: String?
) -> DesktopAccessibilityExtractionConfig {
  let normalizedBundleIdentifier = bundleIdentifier?.lowercased() ?? ""
  let normalizedAppName = appName?.lowercased() ?? ""
  var minimumTextChars = minimumAccessibilityTextChars
  var traversalDepth = defaultAccessibilityTraversalDepth
  var traversalMaxElements = defaultAccessibilityTraversalMaxElements
  var textAttributes = defaultAccessibilityTextAttributes

  let isDenseTextEditor = denseEditorBundlePrefixes.contains(where: {
    normalizedBundleIdentifier.hasPrefix($0)
  })
  let isTerminal =
    terminalBundleIdentifiers.contains(normalizedBundleIdentifier)
    || normalizedAppName.contains("terminal")
    || normalizedAppName.contains("iterm")
    || normalizedAppName.contains("warp")

  if isDenseTextEditor {
    minimumTextChars = 220
    traversalDepth = 3
    traversalMaxElements = 160
    textAttributes.append(contentsOf: ["AXDocument", "AXFilename", "AXURL", "AXRoleDescription"])
  }

  if isTerminal {
    minimumTextChars = 180
    traversalDepth = 3
    traversalMaxElements = max(traversalMaxElements, 128)
    textAttributes.append(contentsOf: ["AXDocument", "AXRoleDescription"])
  }

  return DesktopAccessibilityExtractionConfig(
    minimumTextChars: minimumTextChars,
    textAttributes: deduplicatedStrings(textAttributes),
    childAttributes: defaultAccessibilityChildAttributes,
    traversalDepth: traversalDepth,
    traversalMaxElements: traversalMaxElements
  )
}

public func desktopMinimumAccessibilityTextChars(context: DesktopCaptureContext) -> Int {
  return desktopAccessibilityExtractionConfig(
    bundleIdentifier: context.bundleIdentifier,
    appName: context.appName
  ).minimumTextChars
}

public struct DesktopCaptureContext: Sendable {
  public let appName: String?
  public let bundleIdentifier: String?

  public init(appName: String?, bundleIdentifier: String?) {
    self.appName = appName
    self.bundleIdentifier = bundleIdentifier
  }
}

public struct DesktopCaptureResolution: Sendable {
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

public struct OCRCaptureResult: Sendable {
  public let text: String
  public let confidence: Double?

  public init(text: String, confidence: Double?) {
    self.text = text
    self.confidence = confidence
  }
}

public struct DesktopPermissionReadiness: Sendable {
  public let accessibilityTrusted: Bool
  public let screenRecordingGranted: Bool?

  public init(accessibilityTrusted: Bool, screenRecordingGranted: Bool?) {
    self.accessibilityTrusted = accessibilityTrusted
    self.screenRecordingGranted = screenRecordingGranted
  }
}

public protocol DesktopAccessibilityExtracting {
  func extractFocusedText(frontmostProcessIdentifier: pid_t?) -> String?
}

public protocol DesktopOCRExtracting {
  func extractText(frontmostProcessIdentifier: pid_t?) async -> OCRCaptureResult?
}

public struct LiveDesktopAccessibilityExtractor: DesktopAccessibilityExtracting, Sendable {
  public init() {}

  public func extractFocusedText(frontmostProcessIdentifier: pid_t?) -> String? {
    return extractAccessibilityTextFromFocusedElement(
      frontmostProcessIdentifier: frontmostProcessIdentifier
    )
  }
}

public struct LiveDesktopOCRExtractor: DesktopOCRExtracting, Sendable {
  public init() {}

  public func extractText(frontmostProcessIdentifier: pid_t?) async -> OCRCaptureResult? {
    return await extractOCRTextFromFrontmostWindow(
      frontmostProcessIdentifier: frontmostProcessIdentifier
    )
  }
}

public struct DesktopCaptureDependencies: @unchecked Sendable {
  public let accessibilityExtractor: (pid_t?) -> String?
  public let ocrExtractor: (pid_t?) async -> OCRCaptureResult?

  public init(
    accessibilityExtractor: @escaping (pid_t?) -> String?,
    ocrExtractor: @escaping (pid_t?) async -> OCRCaptureResult?
  ) {
    self.accessibilityExtractor = accessibilityExtractor
    self.ocrExtractor = ocrExtractor
  }

  public static func live(
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

public enum DesktopPermissionPane: Sendable {
  case accessibility
  case screenRecording

  public var privacyAnchor: String {
    switch self {
    case .accessibility:
      return "Privacy_Accessibility"
    case .screenRecording:
      return "Privacy_ScreenCapture"
    }
  }

  public var displayName: String {
    switch self {
    case .accessibility:
      return "Accessibility"
    case .screenRecording:
      return "Screen Recording"
    }
  }
}

public func desktopPermissionSettingsURL(for pane: DesktopPermissionPane) -> URL? {
  return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.privacyAnchor)")
}

public func buildDesktopOriginURL(bundleIdentifier: String?) -> String {
  return "app://\(bundleIdentifier ?? "unknown")"
}

public func normalizeDesktopText(_ value: String?) -> String {
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

public final class SynchronousResultBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  public init() {}

  public func set(_ newValue: Value?) {
    lock.lock()
    value = newValue
    lock.unlock()
  }

  public func get() -> Value? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

public func copyAXAttributeValue(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute, &value)
  guard result == .success else {
    return nil
  }

  return value
}

public func extractAXStringValues(_ value: CFTypeRef?) -> [String] {
  guard let value else {
    return []
  }

  if let stringValue = value as? String {
    return [stringValue]
  }
  if let attributedValue = value as? NSAttributedString {
    return [attributedValue.string]
  }
  if let urlValue = value as? URL {
    return [urlValue.absoluteString]
  }
  if let urlStringValue = value as? NSURL, let absoluteString = urlStringValue.absoluteString {
    return [absoluteString]
  }
  if let values = value as? [Any] {
    return values.flatMap { extractAXStringValues($0 as CFTypeRef) }
  }

  return []
}

public func copyAXElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
  return asAXUIElement(copyAXAttributeValue(element, attribute))
}

public func copyAXElementArrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
  guard let value = copyAXAttributeValue(element, attribute), let values = value as? [Any] else {
    return []
  }

  return values.compactMap { asAXUIElement($0 as CFTypeRef) }
}

public func asAXUIElement(_ value: CFTypeRef?) -> AXUIElement? {
  guard let value else {
    return nil
  }

  let expectedType = AXUIElementGetTypeID()
  guard CFGetTypeID(value) == expectedType else {
    return nil
  }

  return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
}

public func collectAccessibilityTextFromElement(_ element: AXUIElement, attributes: [String]) -> String? {
  var segments: [String] = []
  var seen = Set<String>()
  for attribute in attributes {
    let stringValues = extractAXStringValues(
      copyAXAttributeValue(element, attribute as CFString)
    )
    for stringValue in stringValues {
      let normalized = normalizeDesktopText(stringValue)
      guard !normalized.isEmpty else {
        continue
      }
      if seen.contains(normalized) {
        continue
      }

      seen.insert(normalized)
      segments.append(normalized)
    }
  }

  if segments.isEmpty {
    return nil
  }

  return segments.joined(separator: "\n\n")
}

public func collectAccessibilityTextByTraversingElementTree(
  rootElement: AXUIElement,
  config: DesktopAccessibilityExtractionConfig
) -> String? {
  typealias QueuedElement = (element: AXUIElement, depth: Int)
  var queue: [QueuedElement] = [(rootElement, 0)]
  var queueIndex = 0

  var visited = CFEqualitySet()
  var segments: [String] = []
  var seenSegments = Set<String>()
  var visitedElements = 0

  while queueIndex < queue.count && visitedElements < config.traversalMaxElements {
    let queued = queue[queueIndex]
    queueIndex += 1

    if !visited.insert(queued.element) {
      continue
    }
    visitedElements += 1

    if let elementText = collectAccessibilityTextFromElement(
      queued.element,
      attributes: config.textAttributes
    ) {
      let normalized = normalizeDesktopText(elementText)
      if !normalized.isEmpty && !seenSegments.contains(normalized) {
        seenSegments.insert(normalized)
        segments.append(normalized)
      }
    }

    guard queued.depth < config.traversalDepth else {
      continue
    }

    for attribute in config.childAttributes {
      let childElements = copyAXElementArrayAttribute(queued.element, attribute as CFString)
      for childElement in childElements {
        if visited.contains(childElement) {
          continue
        }

        queue.append((childElement, queued.depth + 1))
      }
    }

    // Parent/title-linked elements often carry richer text when focused fields are sparse.
    if let parent = copyAXElementAttribute(queued.element, kAXParentAttribute as CFString) {
      if !visited.contains(parent) {
        queue.append((parent, queued.depth + 1))
      }
    }
    if let titleElement = copyAXElementAttribute(queued.element, "AXTitleUIElement" as CFString) {
      if !visited.contains(titleElement) {
        queue.append((titleElement, queued.depth + 1))
      }
    }
  }

  if segments.isEmpty {
    return nil
  }

  return segments.joined(separator: "\n\n")
}

public func extractAccessibilityTextFromFocusedElement(
  frontmostProcessIdentifier: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier
) -> String? {
  guard AXIsProcessTrusted() else {
    return nil
  }

  let frontmostApplication = frontmostProcessIdentifier.flatMap {
    NSRunningApplication(processIdentifier: $0)
  }
  let extractionConfig = desktopAccessibilityExtractionConfig(
    bundleIdentifier: frontmostApplication?.bundleIdentifier,
    appName: frontmostApplication?.localizedName
  )

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
    appendUnique(
      collectAccessibilityTextByTraversingElementTree(
        rootElement: focusedElement,
        config: extractionConfig
      )
    )
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
      appendUnique(
        collectAccessibilityTextByTraversingElementTree(
          rootElement: appFocusedElement,
          config: extractionConfig
        )
      )
    }

    var focusedWindowValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowValue
    ) == .success,
      let focusedWindowElement = asAXUIElement(focusedWindowValue)
    {
      appendUnique(
        collectAccessibilityTextByTraversingElementTree(
          rootElement: focusedWindowElement,
          config: extractionConfig
        )
      )
    }
  }

  if segments.isEmpty {
    return nil
  }

  return segments.joined(separator: "\n\n")
}

public func frontmostWindowIDFromWindowList(
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

public func shareableDesktopContent(
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

public func captureImageWithScreenCaptureKit(
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

public func captureFrontmostWindowImage(
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

public func extractOCRTextFromFrontmostWindow(
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

public func desktopPermissionReadiness(
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

public func resolveDesktopCapture(
  context: DesktopCaptureContext,
  accessibilityTextOverride: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_DESKTOP_AX_TEXT"],
  ocrTextOverride: String? = ProcessInfo.processInfo.environment["CONTEXT_GRABBER_DESKTOP_OCR_TEXT"],
  frontmostProcessIdentifier: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
  dependencies: DesktopCaptureDependencies = .live()
) async -> DesktopCaptureResolution {
  let appName = context.appName ?? "Desktop App"
  let minimumTextChars = desktopMinimumAccessibilityTextChars(context: context)
  let originURL = buildDesktopOriginURL(bundleIdentifier: context.bundleIdentifier)
  let accessibilityText = normalizeDesktopText(
    accessibilityTextOverride ?? dependencies.accessibilityExtractor(frontmostProcessIdentifier)
  )

  if accessibilityText.count >= minimumTextChars {
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
    "AX extraction below threshold (\(accessibilityText.count)/\(minimumTextChars) chars); used OCR fallback text."
  }

  let ocrText: String
  let ocrConfidence: Double?
  if let ocrTextOverride {
    ocrText = normalizeDesktopText(ocrTextOverride)
    ocrConfidence = nil
  } else {
    var latestConfidence: Double?
    var resolved = ""

    for _ in 0..<desktopOCRRetryAttempts {
      let extracted = await dependencies.ocrExtractor(frontmostProcessIdentifier)
      latestConfidence = extracted?.confidence
      let normalized = normalizeDesktopText(extracted?.text)
      if !normalized.isEmpty {
        resolved = normalized
        break
      }
    }

    ocrText = resolved
    ocrConfidence = latestConfidence
  }

  if !ocrText.isEmpty {
    let ocrWarning: String = if let ocrConfidence {
      "OCR confidence: \(String(format: "%.2f", ocrConfidence))."
    } else {
      "OCR confidence unavailable."
    }
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
      extractionWarnings: [axFallbackWarning, ocrWarning]
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
    "AX extraction below threshold (\(accessibilityText.count)/\(minimumTextChars) chars) and OCR extraction unavailable."
  }
  let fallbackWarnings: [String] = if accessibilityText.isEmpty {
    [fallbackWarning]
  } else {
    [axFallbackWarning, "OCR extraction unavailable."]
  }
  let fallbackExcerpt: String = if accessibilityText.isEmpty {
    [
      "No extractable text captured.",
      fallbackWarning,
      "Open Accessibility and Screen Recording settings from the menu and retry.",
    ].joined(separator: " ")
  } else {
    accessibilityText
  }
  let payload = BrowserContextPayload(
    source: "desktop",
    browser: "desktop",
    url: originURL,
    title: appName,
    fullText: fallbackExcerpt,
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

public func resolveDesktopCapture(
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
