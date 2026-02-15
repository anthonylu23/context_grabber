import XCTest
@testable import ContextGrabberHost

final class CapturePipelineTests: XCTestCase {
  private struct StubAccessibilityExtractor: DesktopAccessibilityExtracting {
    let text: String?

    func extractFocusedText(frontmostProcessIdentifier _: pid_t?) -> String? {
      return text
    }
  }

  private struct StubOCRExtractor: DesktopOCRExtracting {
    let result: OCRCaptureResult?

    func extractText(frontmostProcessIdentifier _: pid_t?) async -> OCRCaptureResult? {
      return result
    }
  }

  func testDetectBrowserTargetSelectsChromeAndSafari() {
    let safariTarget = detectBrowserTarget(
      frontmostBundleIdentifier: "com.apple.Safari",
      frontmostAppName: "Safari",
      overrideValue: nil
    )
    if case .safari = safariTarget {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected Safari target.")
    }

    let chromeTarget = detectBrowserTarget(
      frontmostBundleIdentifier: "com.google.Chrome",
      frontmostAppName: "Google Chrome",
      overrideValue: nil
    )
    if case .chrome = chromeTarget {
      XCTAssertTrue(true)
    } else {
      XCTFail("Expected Chrome target.")
    }
  }

  func testDetectBrowserTargetUnsupportedUsesUnknownBrowserLabel() {
    let target = detectBrowserTarget(
      frontmostBundleIdentifier: "com.example.Terminal",
      frontmostAppName: "Terminal",
      overrideValue: nil
    )

    if case .unsupported = target {
      XCTAssertEqual(target.browserLabel, "unknown")
      XCTAssertEqual(target.transportStatusPrefix, "desktop_capture")
    } else {
      XCTFail("Expected unsupported target.")
    }
  }

  func testDesktopPermissionSettingsURLUsesExpectedPrivacyAnchors() {
    XCTAssertEqual(
      desktopPermissionSettingsURL(for: .accessibility)?.absoluteString,
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )
    XCTAssertEqual(
      desktopPermissionSettingsURL(for: .screenRecording)?.absoluteString,
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
  }

  func testMenuBarSymbolNameMapping() {
    XCTAssertEqual(menuBarSymbolNameForIndicatorState(.neutral), "text.viewfinder")
    XCTAssertEqual(menuBarSymbolNameForIndicatorState(.success), "checkmark.circle.fill")
    XCTAssertEqual(menuBarSymbolNameForIndicatorState(.failure), "exclamationmark.triangle.fill")
    XCTAssertEqual(menuBarSymbolNameForIndicatorState(.disconnected), "smallcircle.filled.circle")
  }

  func testDisconnectedIndicatorRequiresBothChannelsNotConnected() {
    XCTAssertEqual(
      shouldShowDisconnectedIndicator(
        safariTransportStatus: "safari_extension_unreachable",
        chromeTransportStatus: "chrome_extension_unreachable"
      ),
      true
    )

    XCTAssertEqual(
      shouldShowDisconnectedIndicator(
        safariTransportStatus: "safari_extension_ok",
        chromeTransportStatus: "chrome_extension_unreachable"
      ),
      false
    )
  }

  func testFormatRelativeLastCaptureLabel() {
    XCTAssertEqual(formatRelativeLastCaptureLabel(isoTimestamp: nil), "Last capture: never")

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let formatter = ISO8601DateFormatter()
    let thirtySecondsAgo = formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000 - 30))
    let fiveMinutesAgo = formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000 - 300))
    let threeHoursAgo = formatter.string(from: Date(timeIntervalSince1970: 1_700_000_000 - 10_800))

    XCTAssertEqual(
      formatRelativeLastCaptureLabel(isoTimestamp: thirtySecondsAgo, now: now),
      "Last capture: just now"
    )
    XCTAssertEqual(
      formatRelativeLastCaptureLabel(isoTimestamp: fiveMinutesAgo, now: now),
      "Last capture: 5m ago"
    )
    XCTAssertEqual(
      formatRelativeLastCaptureLabel(isoTimestamp: threeHoursAgo, now: now),
      "Last capture: 3h ago"
    )
    XCTAssertEqual(
      formatRelativeLastCaptureLabel(isoTimestamp: "invalid", now: now),
      "Last capture: unknown"
    )
  }

  func testFrontmostWindowIDFromWindowListPrefersFrontmostAppLayerZeroWindow() {
    let windowList: [[String: Any]] = [
      [
        kCGWindowNumber as String: UInt32(44),
        kCGWindowOwnerPID as String: 999,
        kCGWindowLayer as String: 0,
      ],
      [
        kCGWindowNumber as String: UInt32(81),
        kCGWindowOwnerPID as String: 1234,
        kCGWindowLayer as String: 0,
      ],
      [
        kCGWindowNumber as String: UInt32(82),
        kCGWindowOwnerPID as String: 1234,
        kCGWindowLayer as String: 1,
      ],
    ]

    let selected = frontmostWindowIDFromWindowList(windowList, frontmostProcessIdentifier: 1234)
    XCTAssertEqual(selected, UInt32(81))
  }

  func testResolveEffectiveFrontmostAppPrefersLastNonHostWhenHostIsFrontmost() {
    let current = FrontmostAppInfo(
      bundleIdentifier: "com.example.ContextGrabberHost",
      appName: "Context Grabber",
      processIdentifier: 4321
    )
    let lastNonHost = FrontmostAppInfo(
      bundleIdentifier: "com.apple.Safari",
      appName: "Safari",
      processIdentifier: 9876
    )

    let resolved = resolveEffectiveFrontmostApp(
      current: current,
      lastNonHost: lastNonHost,
      lastKnownBrowser: nil,
      hostProcessIdentifier: 4321
    )

    XCTAssertEqual(resolved.bundleIdentifier, "com.apple.Safari")
    XCTAssertEqual(resolved.appName, "Safari")
  }

  func testResolveEffectiveFrontmostAppKeepsCurrentWhenNotHost() {
    let current = FrontmostAppInfo(
      bundleIdentifier: "com.apple.Safari",
      appName: "Safari",
      processIdentifier: 1111
    )
    let lastNonHost = FrontmostAppInfo(
      bundleIdentifier: "com.google.Chrome",
      appName: "Google Chrome",
      processIdentifier: 2222
    )

    let resolved = resolveEffectiveFrontmostApp(
      current: current,
      lastNonHost: lastNonHost,
      lastKnownBrowser: nil,
      hostProcessIdentifier: 9999
    )

    XCTAssertEqual(resolved.bundleIdentifier, "com.apple.Safari")
    XCTAssertEqual(resolved.appName, "Safari")
  }

  func testResolveEffectiveFrontmostAppPrefersLastKnownBrowserWhenHostIsFrontmost() {
    let current = FrontmostAppInfo(
      bundleIdentifier: "com.example.ContextGrabberHost",
      appName: "Context Grabber",
      processIdentifier: 4321
    )
    let lastNonHost = FrontmostAppInfo(
      bundleIdentifier: "com.apple.finder",
      appName: "Finder",
      processIdentifier: 1234
    )
    let lastKnownBrowser = FrontmostAppInfo(
      bundleIdentifier: "com.apple.Safari",
      appName: "Safari",
      processIdentifier: 5678
    )

    let resolved = resolveEffectiveFrontmostApp(
      current: current,
      lastNonHost: lastNonHost,
      lastKnownBrowser: lastKnownBrowser,
      hostProcessIdentifier: 4321
    )

    XCTAssertEqual(resolved.bundleIdentifier, "com.apple.Safari")
    XCTAssertEqual(resolved.appName, "Safari")
  }

  func testRenderMarkdownTruncatesLongContentAndAddsWarning() {
    let payload = BrowserContextPayload(
      source: "browser",
      browser: "safari",
      url: "https://example.com/long",
      title: "Long Capture",
      fullText: String(repeating: "x", count: maxBrowserFullTextChars + 64),
      headings: [],
      links: [],
      metaDescription: nil,
      siteName: "Example",
      language: "en",
      author: "Context Grabber",
      publishedTime: nil,
      selectionText: nil,
      extractionWarnings: []
    )

    let markdown = renderMarkdown(
      requestID: "req-long-1",
      capturedAt: "2026-02-14T00:00:00.000Z",
      extractionMethod: "browser_extension",
      payload: payload
    )

    XCTAssertTrue(markdown.contains("truncated: true"))
    XCTAssertTrue(markdown.contains("Capture truncated at \(maxBrowserFullTextChars) chars."))
  }

  func testMetadataOnlyFallbackPayloadAndMarkdown() {
    let warning = "ERR_EXTENSION_UNAVAILABLE: Frontmost app is not supported."
    let payload = createMetadataOnlyBrowserPayload(
      browser: "chrome",
      details: nil,
      warning: warning,
      frontAppName: "Google Chrome"
    )

    XCTAssertEqual(payload.browser, "chrome")
    XCTAssertEqual(payload.url, "about:blank")
    XCTAssertEqual(payload.title, "Google Chrome (metadata only)")
    XCTAssertEqual(payload.fullText, "")
    XCTAssertEqual(payload.extractionWarnings, [warning])

    let markdown = renderMarkdown(
      requestID: "req-fallback-1",
      capturedAt: "2026-02-14T00:00:00.000Z",
      extractionMethod: "metadata_only",
      payload: payload
    )

    XCTAssertTrue(markdown.contains("extraction_method: \"metadata_only\""))
    XCTAssertTrue(markdown.contains(warning))
  }

  func testResolveDesktopCaptureUsesAccessibilityTextWhenProvided() async {
    let accessibilityText = String(repeating: "a", count: minimumAccessibilityTextChars + 8)
    let resolution = await resolveDesktopCapture(
      context: DesktopCaptureContext(appName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
      accessibilityTextOverride: accessibilityText,
      ocrTextOverride: "OCR text",
      accessibilityExtractor: { nil },
      ocrExtractor: { nil }
    )

    XCTAssertEqual(resolution.extractionMethod, "accessibility")
    XCTAssertEqual(resolution.transportStatus, "desktop_capture_accessibility")
    XCTAssertEqual(resolution.payload.source, "desktop")
    XCTAssertEqual(resolution.payload.fullText, accessibilityText)
    XCTAssertNil(resolution.warning)
    XCTAssertNil(resolution.errorCode)
  }

  func testResolveDesktopCaptureUsesOcrFallbackWhenAxUnavailable() async {
    let resolution = await resolveDesktopCapture(
      context: DesktopCaptureContext(appName: "Preview", bundleIdentifier: "com.apple.Preview"),
      accessibilityTextOverride: nil,
      ocrTextOverride: "OCR text",
      accessibilityExtractor: { nil },
      ocrExtractor: { nil }
    )

    XCTAssertEqual(resolution.extractionMethod, "ocr")
    XCTAssertEqual(resolution.transportStatus, "desktop_capture_ocr")
    XCTAssertEqual(resolution.payload.fullText, "OCR text")
    XCTAssertTrue((resolution.payload.extractionWarnings ?? []).contains("AX extraction unavailable; used OCR fallback text."))
    XCTAssertNil(resolution.errorCode)
  }

  func testResolveDesktopCaptureReturnsMetadataOnlyWhenAxAndOcrUnavailable() async {
    let resolution = await resolveDesktopCapture(
      context: DesktopCaptureContext(appName: "Figma", bundleIdentifier: "com.figma.Desktop"),
      accessibilityTextOverride: nil,
      ocrTextOverride: nil,
      accessibilityExtractor: { nil },
      ocrExtractor: { nil }
    )

    XCTAssertEqual(resolution.extractionMethod, "metadata_only")
    XCTAssertEqual(resolution.transportStatus, "desktop_capture_metadata_only")
    XCTAssertEqual(resolution.warning, "AX and OCR extraction unavailable.")
    XCTAssertEqual(resolution.errorCode, "ERR_EXTENSION_UNAVAILABLE")
  }

  func testResolveDesktopCaptureMetadataWarningWhenAxBelowThresholdAndOcrUnavailable() async {
    let accessibilityText = String(repeating: "a", count: minimumAccessibilityTextChars - 1)
    let resolution = await resolveDesktopCapture(
      context: DesktopCaptureContext(appName: "Notes", bundleIdentifier: "com.apple.Notes"),
      accessibilityTextOverride: accessibilityText,
      ocrTextOverride: nil,
      accessibilityExtractor: { nil },
      ocrExtractor: { nil }
    )

    XCTAssertEqual(resolution.extractionMethod, "metadata_only")
    XCTAssertEqual(
      resolution.warning,
      "AX extraction below threshold (\(minimumAccessibilityTextChars - 1) chars) and OCR extraction unavailable."
    )
    XCTAssertEqual(
      resolution.payload.extractionWarnings,
      [
        "AX extraction below threshold (\(minimumAccessibilityTextChars - 1) chars); used OCR fallback text.",
        "OCR extraction unavailable.",
      ]
    )
    XCTAssertEqual(resolution.payload.fullText, accessibilityText)
  }

  func testResolveDesktopCaptureUsesServiceDependencies() async {
    let dependencies = DesktopCaptureDependencies.live(
      accessibility: StubAccessibilityExtractor(text: nil),
      ocr: StubOCRExtractor(result: OCRCaptureResult(text: "OCR from service", confidence: 0.88))
    )

    let resolution = await resolveDesktopCapture(
      context: DesktopCaptureContext(appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit"),
      accessibilityTextOverride: nil,
      ocrTextOverride: nil,
      frontmostProcessIdentifier: nil,
      dependencies: dependencies
    )

    XCTAssertEqual(resolution.extractionMethod, "ocr")
    XCTAssertEqual(resolution.transportStatus, "desktop_capture_ocr")
    XCTAssertEqual(resolution.payload.fullText, "OCR from service")
    XCTAssertNil(resolution.errorCode)
  }

  func testDesktopPermissionReadinessUsesInjectedProviders() {
    let readiness = desktopPermissionReadiness(
      isAccessibilityTrusted: { false },
      screenRecordingGranted: { true }
    )

    XCTAssertEqual(readiness.accessibilityTrusted, false)
    XCTAssertEqual(readiness.screenRecordingGranted, true)
  }

  func testResolveBrowserCaptureMapsTimeoutToMetadataFallback() {
    let resolution = resolveBrowserCapture(
      target: .safari,
      bridgeResult: .failure(SafariNativeMessagingTransportError.timedOut),
      frontAppName: "Safari"
    )

    XCTAssertEqual(resolution.extractionMethod, "metadata_only")
    XCTAssertEqual(resolution.errorCode, "ERR_TIMEOUT")
    XCTAssertEqual(resolution.transportStatus, "safari_extension_error:ERR_TIMEOUT")
    XCTAssertTrue((resolution.warning ?? "").contains("ERR_TIMEOUT"))
  }

  func testResolveBrowserCaptureMapsUnavailableToMetadataFallback() {
    let resolution = resolveBrowserCapture(
      target: .chrome,
      bridgeResult: .failure(ChromeNativeMessagingTransportError.emptyOutput),
      frontAppName: "Google Chrome"
    )

    XCTAssertEqual(resolution.extractionMethod, "metadata_only")
    XCTAssertEqual(resolution.errorCode, "ERR_EXTENSION_UNAVAILABLE")
    XCTAssertEqual(resolution.transportStatus, "chrome_extension_error:ERR_EXTENSION_UNAVAILABLE")
  }

  func testResolveBrowserCaptureHandlesProtocolMismatchResult() {
    let message = ExtensionCaptureResponseMessage(
      id: "req-1",
      type: "extension.capture.result",
      timestamp: "2026-02-14T00:00:00.000Z",
      payload: ExtensionCaptureResponsePayload(
        protocolVersion: "2",
        capture: BrowserContextPayload(
          source: "browser",
          browser: "safari",
          url: "https://example.com",
          title: "Example",
          fullText: "Text",
          headings: [],
          links: [],
          metaDescription: nil,
          siteName: nil,
          language: nil,
          author: nil,
          publishedTime: nil,
          selectionText: nil,
          extractionWarnings: nil
        )
      )
    )

    let resolution = resolveBrowserCapture(
      target: .safari,
      bridgeResult: .success(.captureResult(message)),
      frontAppName: "Safari"
    )

    XCTAssertEqual(resolution.extractionMethod, "metadata_only")
    XCTAssertEqual(resolution.errorCode, "ERR_PROTOCOL_VERSION")
    XCTAssertEqual(resolution.transportStatus, "safari_extension_error:ERR_PROTOCOL_VERSION")
  }

  func testRenderMarkdownUsesDesktopSourceTypeAndMetadataForDesktopPayload() {
    let payload = BrowserContextPayload(
      source: "desktop",
      browser: "desktop",
      url: "app://com.apple.Terminal",
      title: "Terminal",
      fullText: "Desktop capture text.",
      headings: [],
      links: [],
      metaDescription: nil,
      siteName: "Terminal",
      language: nil,
      author: nil,
      publishedTime: nil,
      selectionText: nil,
      extractionWarnings: []
    )

    let markdown = renderMarkdown(
      requestID: "req-desktop-1",
      capturedAt: "2026-02-14T00:00:00.000Z",
      extractionMethod: "ocr",
      payload: payload
    )

    XCTAssertTrue(markdown.contains("source_type: \"desktop_app\""))
    XCTAssertTrue(markdown.contains("- source: desktop"))
    XCTAssertTrue(markdown.contains("- app_bundle_id: com.apple.Terminal"))
  }

  func testRenderMarkdownIsDeterministicForSameInput() {
    let payload = BrowserContextPayload(
      source: "browser",
      browser: "safari",
      url: "https://example.com/deterministic",
      title: "Deterministic Capture",
      fullText: "Sentence one. Sentence two. Sentence three.",
      headings: [BrowserContextPayload.Heading(level: 1, text: "Heading")],
      links: [BrowserContextPayload.Link(text: "Example", href: "https://example.com")],
      metaDescription: "Meta",
      siteName: "Example",
      language: "en",
      author: "Author",
      publishedTime: "2026-02-14T00:00:00.000Z",
      selectionText: "Sentence one.",
      extractionWarnings: ["warn-a"]
    )

    let first = renderMarkdown(
      requestID: "req-deterministic-1",
      capturedAt: "2026-02-14T00:00:00.000Z",
      extractionMethod: "browser_extension",
      payload: payload
    )

    let second = renderMarkdown(
      requestID: "req-deterministic-1",
      capturedAt: "2026-02-14T00:00:00.000Z",
      extractionMethod: "browser_extension",
      payload: payload
    )

    XCTAssertEqual(first, second)
  }
}
