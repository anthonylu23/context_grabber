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

  private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("context-grabber-tests-\(UUID().uuidString.lowercased())", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    try body(directoryURL)
  }

  private func sampleCaptureMarkdown(requestID: String = "ad3fdb24-5a1c-49d0-bfae-144f3bf96149") -> String {
    let payload = BrowserContextPayload(
      source: "browser",
      browser: "safari",
      url: "https://example.com/sample",
      title: "Sample Capture",
      fullText: "This is sample capture content.",
      headings: [],
      links: [],
      metaDescription: nil,
      siteName: "Example",
      language: "en",
      author: nil,
      publishedTime: nil,
      selectionText: nil,
      extractionWarnings: []
    )

    return renderMarkdown(
      requestID: requestID,
      capturedAt: "2026-02-14T23:11:51Z",
      extractionMethod: "browser_extension",
      payload: payload
    )
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

  func testMenuBarIconMapping() {
    let idle = menuBarIconForIndicatorState(.idle)
    XCTAssertEqual(idle.name, "MenuBarIcon")
    XCTAssertFalse(idle.isSystemSymbol)

    let capturing = menuBarIconForIndicatorState(.capturing)
    XCTAssertEqual(capturing.name, "arrow.triangle.2.circlepath.circle.fill")
    XCTAssertTrue(capturing.isSystemSymbol)

    let success = menuBarIconForIndicatorState(.success)
    XCTAssertEqual(success.name, "checkmark.circle.fill")
    XCTAssertTrue(success.isSystemSymbol)

    let error = menuBarIconForIndicatorState(.error)
    XCTAssertEqual(error.name, "exclamationmark.triangle.fill")
    XCTAssertTrue(error.isSystemSymbol)

    let disconnected = menuBarIconForIndicatorState(.disconnected)
    XCTAssertEqual(disconnected.name, "smallcircle.filled.circle")
    XCTAssertTrue(disconnected.isSystemSymbol)
  }

  func testCaptureFeedbackFormatting() {
    XCTAssertEqual(formatCaptureFeedbackTitle(kind: .success), "Capture saved")
    XCTAssertEqual(formatCaptureFeedbackTitle(kind: .failure), "Capture failed")

    XCTAssertEqual(
      formatCaptureSuccessFeedbackDetail(
        sourceLabel: "Safari",
        targetLabel: "Example title",
        extractionMethod: "browser_extension",
        transportStatus: "safari_extension_ok",
        warning: nil
      ),
      "Safari: Example title | method: browser_extension | transport: safari_extension_ok"
    )

    XCTAssertEqual(
      formatCaptureSuccessFeedbackDetail(
        sourceLabel: "Desktop",
        targetLabel: "Notes",
        extractionMethod: "desktop_accessibility",
        transportStatus: "desktop_capture_accessibility",
        warning: "metadata only"
      ),
      "Desktop: Notes | method: desktop_accessibility | transport: desktop_capture_accessibility | warning: metadata only"
    )

    XCTAssertEqual(
      formatCaptureFailureFeedbackDetail("Bridge timeout"),
      "Error: Bridge timeout"
    )
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

  func testSteadyIndicatorUsesLatestSafariCaptureTransportStatus() {
    XCTAssertEqual(
      steadyMenuBarIndicatorState(
        safariDiagnosticsTransportStatus: "safari_extension_unreachable",
        chromeDiagnosticsTransportStatus: "chrome_extension_unreachable",
        latestTransportStatus: "safari_extension_ok"
      ),
      .idle
    )
  }

  func testSteadyIndicatorUsesLatestChromeCaptureTransportStatus() {
    XCTAssertEqual(
      steadyMenuBarIndicatorState(
        safariDiagnosticsTransportStatus: "safari_extension_unreachable",
        chromeDiagnosticsTransportStatus: "chrome_extension_unreachable",
        latestTransportStatus: "chrome_extension_ok"
      ),
      .idle
    )
  }

  func testSteadyIndicatorFallsBackToDiagnosticsWhenLatestTransportIsUnrelated() {
    XCTAssertEqual(
      steadyMenuBarIndicatorState(
        safariDiagnosticsTransportStatus: "safari_extension_unreachable",
        chromeDiagnosticsTransportStatus: "chrome_extension_unreachable",
        latestTransportStatus: "desktop_capture_ready"
      ),
      .disconnected
    )
  }

  func testResolveExtensionDiagnosticsStatusForProtocolMatch() {
    let status = resolveExtensionDiagnosticsStatus(
      ping: { NativeMessagingPingResponse(ok: true, protocolVersion: protocolVersion) },
      transportStatusPrefix: "safari_extension"
    )

    XCTAssertEqual(status.label, "reachable/protocol \(protocolVersion)")
    XCTAssertEqual(status.transportStatus, "safari_extension_ok")
  }

  func testResolveExtensionDiagnosticsStatusForProtocolMismatch() {
    let status = resolveExtensionDiagnosticsStatus(
      ping: { NativeMessagingPingResponse(ok: true, protocolVersion: "2") },
      transportStatusPrefix: "chrome_extension"
    )

    XCTAssertEqual(status.label, "reachable/protocol mismatch")
    XCTAssertEqual(status.transportStatus, "chrome_extension_protocol_mismatch")
  }

  func testResolveExtensionDiagnosticsStatusForUnreachablePing() {
    let status = resolveExtensionDiagnosticsStatus(
      ping: { throw NSError(domain: "CapturePipelineTests", code: 9001) },
      transportStatusPrefix: "safari_extension"
    )

    XCTAssertEqual(status.label, "unreachable")
    XCTAssertEqual(status.transportStatus, "safari_extension_unreachable")
  }

  func testDiagnosticsTransportStatusForTarget() {
    let safariStatus: ExtensionDiagnosticsStatus = ("reachable/protocol \(protocolVersion)", "safari_extension_ok")
    let chromeStatus: ExtensionDiagnosticsStatus = ("unreachable", "chrome_extension_unreachable")

    XCTAssertEqual(
      diagnosticsTransportStatusForTarget(.safari, safariStatus: safariStatus, chromeStatus: chromeStatus),
      "safari_extension_ok"
    )
    XCTAssertEqual(
      diagnosticsTransportStatusForTarget(.chrome, safariStatus: safariStatus, chromeStatus: chromeStatus),
      "chrome_extension_unreachable"
    )
    XCTAssertEqual(
      diagnosticsTransportStatusForTarget(
        .unsupported(appName: "Notes", bundleIdentifier: "com.apple.Notes"),
        safariStatus: safariStatus,
        chromeStatus: chromeStatus
      ),
      "desktop_capture_ready"
    )
  }

  func testFormatDiagnosticsSummaryUsesExpectedShape() {
    let summary = formatDiagnosticsSummary(
      DiagnosticsSummaryContext(
        frontAppDisplayName: "Safari",
        safariLabel: "reachable/protocol \(protocolVersion)",
        chromeLabel: "unreachable",
        desktopAccessibilityLabel: "granted",
        desktopScreenLabel: "missing",
        lastCaptureLabel: "2026-02-14T20:00:00Z",
        lastErrorLabel: "ERR_TIMEOUT",
        latencyLabel: "123ms",
        storageWritable: true,
        historyPath: "/tmp/history"
      )
    )

    XCTAssertEqual(
      summary,
      "Front app: Safari | Safari: reachable/protocol \(protocolVersion) | Chrome: unreachable | Desktop AX: granted | Screen: missing | Last capture: 2026-02-14T20:00:00Z | Last error: ERR_TIMEOUT | Latency: 123ms | Storage writable: yes | History: /tmp/history"
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

  func testCFEqualitySetDeduplicatesDistinctButEqualCFValues() {
    let first: CFTypeRef = NSString(string: "same-value")
    let second: CFTypeRef = NSString(string: "same-value")
    XCTAssertFalse((first as AnyObject) === (second as AnyObject))

    var visited = CFEqualitySet()
    XCTAssertTrue(visited.insert(first))
    XCTAssertFalse(visited.insert(second))
    XCTAssertTrue(visited.contains(second))
  }

  func testRetentionLabelFormatting() {
    XCTAssertEqual(retentionMaxFileCountLabel(0), "Unlimited")
    XCTAssertEqual(retentionMaxFileCountLabel(100), "100")
    XCTAssertEqual(retentionMaxAgeDaysLabel(0), "Unlimited")
    XCTAssertEqual(retentionMaxAgeDaysLabel(30), "30 days")
  }

  func testRetentionPruneCandidatesAppliesAgeThenCount() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let newest = URL(fileURLWithPath: "/tmp/newest.md")
    let middle = URL(fileURLWithPath: "/tmp/middle.md")
    let oldest = URL(fileURLWithPath: "/tmp/oldest.md")

    let fileDates: [URL: Date] = [
      newest: Date(timeIntervalSince1970: 2_000_000_000 - 60),
      middle: Date(timeIntervalSince1970: 2_000_000_000 - 86_400 * 10),
      oldest: Date(timeIntervalSince1970: 2_000_000_000 - 86_400 * 120),
    ]

    let candidates = retentionPruneCandidates(
      files: [oldest, newest, middle],
      policy: HostRetentionPolicy(maxFileCount: 1, maxFileAgeDays: 90),
      now: now
    ) { url in
      fileDates[url]
    }

    XCTAssertEqual(Set(candidates), Set([middle, oldest]))
  }

  func testHostGeneratedCaptureFilenameRequiresTimestampAndSuffix() {
    XCTAssertTrue(isHostGeneratedCaptureFilename("20260214-231151-ad3fdb24.md"))
    XCTAssertFalse(isHostGeneratedCaptureFilename("notes.md"))
    XCTAssertFalse(isHostGeneratedCaptureFilename("20260214-231151.md"))
    XCTAssertFalse(isHostGeneratedCaptureFilename("invalid-231151-ad3fdb24.md"))
  }

  func testHasRequiredCaptureFrontmatterRequiresExpectedKeys() {
    let valid = sampleCaptureMarkdown()
    XCTAssertTrue(hasRequiredCaptureFrontmatter(valid))

    let invalid = """
    ---
    id: "123"
    captured_at: "2026-02-14T23:11:51Z"
    ---
    Content
    """
    XCTAssertFalse(hasRequiredCaptureFrontmatter(invalid))
  }

  func testFilterHostGeneratedCaptureFilesExcludesUnrelatedMarkdown() throws {
    try withTemporaryDirectory { directoryURL in
      let validCaptureURL = directoryURL.appendingPathComponent("20260214-231151-ad3fdb24.md", isDirectory: false)
      try sampleCaptureMarkdown().write(to: validCaptureURL, atomically: true, encoding: .utf8)

      let unrelatedNotesURL = directoryURL.appendingPathComponent("notes.md", isDirectory: false)
      try "# Notes\nUnrelated text.".write(to: unrelatedNotesURL, atomically: true, encoding: .utf8)

      let lookalikeURL = directoryURL.appendingPathComponent("20260214-231152-notes123.md", isDirectory: false)
      try "# Looks like capture filename but no frontmatter".write(to: lookalikeURL, atomically: true, encoding: .utf8)

      let filtered = filterHostGeneratedCaptureFiles([validCaptureURL, unrelatedNotesURL, lookalikeURL])
      XCTAssertEqual(filtered, [validCaptureURL])
    }
  }

  func testRecentHostCaptureFilesExcludeUnrelatedMarkdownFiles() throws {
    try withTemporaryDirectory { directoryURL in
      let oldestCaptureURL = directoryURL.appendingPathComponent("20260214-231151-ad3fdb24.md", isDirectory: false)
      let newestCaptureURL = directoryURL.appendingPathComponent("20260214-231152-bb9af51a.md", isDirectory: false)
      try sampleCaptureMarkdown(requestID: "ad3fdb24-5a1c-49d0-bfae-144f3bf96149")
        .write(to: oldestCaptureURL, atomically: true, encoding: .utf8)
      try sampleCaptureMarkdown(requestID: "bb9af51a-5a1c-49d0-bfae-144f3bf96149")
        .write(to: newestCaptureURL, atomically: true, encoding: .utf8)

      let unrelatedURL = directoryURL.appendingPathComponent("notes.md", isDirectory: false)
      try "# Notes\nUnrelated text.".write(to: unrelatedURL, atomically: true, encoding: .utf8)

      let files = [oldestCaptureURL, newestCaptureURL, unrelatedURL]
      let entries = recentHostCaptureFiles(files, limit: 5)
      XCTAssertEqual(entries, [newestCaptureURL, oldestCaptureURL])
    }
  }

  func testIsDirectoryWritableRequiresSuccessfulProbeWrite() throws {
    try withTemporaryDirectory { directoryURL in
      XCTAssertTrue(isDirectoryWritable(directoryURL))
    }

    let notWritable = isDirectoryWritable(
      URL(fileURLWithPath: "/tmp/context-grabber-unused-test"),
      ensureDirectory: { _ in },
      writeProbe: { _, _ in
        throw NSError(domain: "CapturePipelineTests", code: 1)
      },
      removeProbe: { _ in }
    )
    XCTAssertFalse(notWritable)
  }

  func testOutputDirectoryValidationErrorReturnsMessageWhenDirectoryIsNotWritable() {
    let dir = URL(fileURLWithPath: "/tmp/context-grabber-unwritable")
    XCTAssertEqual(
      outputDirectoryValidationError(dir, writableCheck: { _ in false }),
      "Selected output directory is not writable."
    )
    XCTAssertNil(outputDirectoryValidationError(dir, writableCheck: { _ in true }))
  }

  func testLoadHostSettingsSanitizesNegativeRetentionValues() {
    let suiteName = "context-grabber-tests-\(UUID().uuidString.lowercased())"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Expected ephemeral test UserDefaults suite.")
      return
    }
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    defaults.set(-42, forKey: "context_grabber.retention_max_file_count")
    defaults.set(-9, forKey: "context_grabber.retention_max_age_days")
    defaults.set("", forKey: "context_grabber.output_directory_path")
    defaults.set(true, forKey: "context_grabber.captures_paused_placeholder")

    let settings = loadHostSettings(userDefaults: defaults)
    XCTAssertEqual(settings.retentionMaxFileCount, HostSettings.defaultRetentionMaxFileCount)
    XCTAssertEqual(settings.retentionMaxAgeDays, HostSettings.defaultRetentionMaxAgeDays)
    XCTAssertNil(settings.outputDirectoryURL)
    XCTAssertEqual(settings.capturesPausedPlaceholder, true)
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
      "AX extraction below threshold (\(minimumAccessibilityTextChars - 1)/\(minimumAccessibilityTextChars) chars) and OCR extraction unavailable."
    )
    XCTAssertEqual(
      resolution.payload.extractionWarnings,
      [
        "AX extraction below threshold (\(minimumAccessibilityTextChars - 1)/\(minimumAccessibilityTextChars) chars); used OCR fallback text.",
        "OCR extraction unavailable.",
      ]
    )
    XCTAssertEqual(resolution.payload.fullText, accessibilityText)
  }

  func testResolveDesktopCaptureUsesEditorThresholdTuning() async {
    let accessibilityText = String(repeating: "a", count: 260)
    let resolution = await resolveDesktopCapture(
      context: DesktopCaptureContext(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
      accessibilityTextOverride: accessibilityText,
      ocrTextOverride: nil,
      accessibilityExtractor: { nil },
      ocrExtractor: { nil }
    )

    XCTAssertEqual(desktopMinimumAccessibilityTextChars(
      context: DesktopCaptureContext(
        appName: "Visual Studio Code",
        bundleIdentifier: "com.microsoft.VSCode"
      )
    ), 220)
    XCTAssertEqual(resolution.extractionMethod, "accessibility")
    XCTAssertEqual(resolution.payload.fullText, accessibilityText)
  }

  func testResolveDesktopCaptureUsesDefaultThresholdForUntunedApps() async {
    let accessibilityText = String(repeating: "a", count: 260)
    let resolution = await resolveDesktopCapture(
      context: DesktopCaptureContext(appName: "Notes", bundleIdentifier: "com.apple.Notes"),
      accessibilityTextOverride: accessibilityText,
      ocrTextOverride: nil,
      accessibilityExtractor: { nil },
      ocrExtractor: { nil }
    )

    XCTAssertEqual(desktopMinimumAccessibilityTextChars(
      context: DesktopCaptureContext(
        appName: "Notes",
        bundleIdentifier: "com.apple.Notes"
      )
    ), minimumAccessibilityTextChars)
    XCTAssertEqual(resolution.extractionMethod, "metadata_only")
    XCTAssertEqual(
      resolution.warning,
      "AX extraction below threshold (\(accessibilityText.count)/\(minimumAccessibilityTextChars) chars) and OCR extraction unavailable."
    )
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
