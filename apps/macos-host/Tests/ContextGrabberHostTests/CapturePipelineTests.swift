import XCTest
@testable import ContextGrabberHost

final class CapturePipelineTests: XCTestCase {
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
