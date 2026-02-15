import XCTest
@testable import ContextGrabberHost

final class CLIEntryPointTests: XCTestCase {
  func testIsCaptureInvocationRecognizesCaptureFlag() {
    XCTAssertTrue(
      CLIEntryPoint.isCaptureInvocation(arguments: ["ContextGrabberHost", "--capture"])
    )
    XCTAssertFalse(
      CLIEntryPoint.isCaptureInvocation(arguments: ["ContextGrabberHost", "--help"])
    )
  }

  func testParseArgumentsForTestingUsesDefaults() throws {
    let parsed = try CLIEntryPoint.parseArgumentsForTesting(
      arguments: ["ContextGrabberHost", "--capture"]
    )

    XCTAssertEqual(
      parsed,
      HostCLIParsedArguments(
        appName: nil,
        bundleIdentifier: nil,
        captureMethod: "auto",
        outputFormat: "markdown"
      )
    )
  }

  func testParseArgumentsForTestingParsesOverrides() throws {
    let parsed = try CLIEntryPoint.parseArgumentsForTesting(
      arguments: [
        "ContextGrabberHost",
        "--capture",
        "--app", "Finder",
        "--bundle-id", "com.apple.finder",
        "--method", "ax",
        "--format", "json",
      ]
    )

    XCTAssertEqual(parsed.appName, "Finder")
    XCTAssertEqual(parsed.bundleIdentifier, "com.apple.finder")
    XCTAssertEqual(parsed.captureMethod, "ax")
    XCTAssertEqual(parsed.outputFormat, "json")
  }

  func testParseArgumentsForTestingThrowsWhenFlagValueMissing() {
    XCTAssertThrowsError(
      try CLIEntryPoint.parseArgumentsForTesting(
        arguments: ["ContextGrabberHost", "--capture", "--app"]
      )
    )
  }

  func testParseArgumentsForTestingTreatsNextFlagAsMissingValue() {
    XCTAssertThrowsError(
      try CLIEntryPoint.parseArgumentsForTesting(
        arguments: ["ContextGrabberHost", "--capture", "--app", "--method", "ax"]
      )
    )
  }

  func testRunReturnsZeroForHelp() async {
    let exitCode = await CLIEntryPoint.run(arguments: ["ContextGrabberHost", "--capture", "--help"])
    XCTAssertEqual(exitCode, 0)
  }

  func testRunReturnsFailureForInvalidMethod() async {
    let exitCode = await CLIEntryPoint.run(
      arguments: ["ContextGrabberHost", "--capture", "--method", "invalid"]
    )
    XCTAssertEqual(exitCode, 1)
  }

  func testWaitForFrontmostApplicationReturnsTrueWhenAlreadyFrontmost() async {
    let didBecomeFrontmost = await CLIEntryPoint.waitForFrontmostApplication(
      targetProcessIdentifier: 777,
      timeoutNanoseconds: 100_000_000,
      pollIntervalNanoseconds: 1_000_000,
      frontmostProcessIdentifierProvider: { 777 },
      sleep: { _ in }
    )
    XCTAssertTrue(didBecomeFrontmost)
  }

  func testWaitForFrontmostApplicationReturnsFalseWhenTimeoutReached() async {
    let didBecomeFrontmost = await CLIEntryPoint.waitForFrontmostApplication(
      targetProcessIdentifier: 777,
      timeoutNanoseconds: 1_000_000,
      pollIntervalNanoseconds: 100_000,
      frontmostProcessIdentifierProvider: { 123 },
      sleep: { _ in }
    )
    XCTAssertFalse(didBecomeFrontmost)
  }
}
