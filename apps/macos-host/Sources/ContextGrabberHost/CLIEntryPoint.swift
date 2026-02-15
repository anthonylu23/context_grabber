import AppKit
import ContextGrabberCore
import Foundation

private enum HostCLICaptureMethod: String {
  case auto
  case ax
  case ocr
}

private enum HostCLIOutputFormat: String {
  case markdown
  case json
}

private struct HostCLIConfiguration {
  var appName: String?
  var bundleIdentifier: String?
  var captureMethod: HostCLICaptureMethod = .auto
  var outputFormat: HostCLIOutputFormat = .markdown
}

private let cliTargetActivationTimeoutNanoseconds: UInt64 = 1_500_000_000
private let cliTargetActivationPollIntervalNanoseconds: UInt64 = 50_000_000

struct HostCLIParsedArguments: Equatable {
  let appName: String?
  let bundleIdentifier: String?
  let captureMethod: String
  let outputFormat: String
}

private struct HostCLICaptureResult {
  let requestID: String
  let capturedAt: String
  let resolution: DesktopCaptureResolution
  let markdown: String
}

private struct HostCLIJSONOutput: Codable {
  let requestID: String
  let capturedAt: String
  let extractionMethod: String
  let transportStatus: String
  let warning: String?
  let errorCode: String?
  let payload: BrowserContextPayload
  let markdown: String
}

private enum HostCLIError: LocalizedError {
  case usageRequested
  case missingValue(flag: String)
  case invalidValue(flag: String, value: String)
  case unknownArgument(String)
  case targetApplicationNotFound(name: String?, bundleIdentifier: String?)
  case targetApplicationActivationFailed(name: String?, bundleIdentifier: String?)
  case captureExecutionFailed(String)

  var errorDescription: String? {
    switch self {
    case .usageRequested:
      return nil
    case .missingValue(let flag):
      return "Missing value for \(flag)."
    case .invalidValue(let flag, let value):
      return "Invalid value for \(flag): \(value)."
    case .unknownArgument(let argument):
      return "Unknown argument: \(argument)"
    case .targetApplicationNotFound(let name, let bundleIdentifier):
      if let bundleIdentifier, !bundleIdentifier.isEmpty {
        return "No running application found for bundle id \(bundleIdentifier)."
      }
      if let name, !name.isEmpty {
        return "No running application found named \(name)."
      }
      return "No target application could be resolved."
    case .targetApplicationActivationFailed(let name, let bundleIdentifier):
      if let bundleIdentifier, !bundleIdentifier.isEmpty {
        return "Timed out waiting for target application \(bundleIdentifier) to become frontmost."
      }
      if let name, !name.isEmpty {
        return "Timed out waiting for target application \(name) to become frontmost."
      }
      return "Timed out waiting for target application to become frontmost."
    case .captureExecutionFailed(let message):
      return "Headless capture failed: \(message)"
    }
  }
}

enum CLIEntryPoint {
  static func isCaptureInvocation(arguments: [String]) -> Bool {
    return arguments.dropFirst().contains("--capture")
  }

  static func run(arguments: [String]) async -> Int32 {
    do {
      let configuration = try parse(arguments: arguments)
      let result = try await runCapture(configuration: configuration)
      try emit(result: result, outputFormat: configuration.outputFormat)
      return 0
    } catch let error as HostCLIError {
      if case .usageRequested = error {
        fputs(usageText, stdout)
        return 0
      }

      if let message = error.errorDescription, !message.isEmpty {
        fputs("error: \(message)\n", stderr)
      }
      fputs("Run with --capture --help for usage.\n", stderr)
      return 1
    } catch {
      fputs("error: \(error.localizedDescription)\n", stderr)
      return 1
    }
  }

  static func parseArgumentsForTesting(arguments: [String]) throws -> HostCLIParsedArguments {
    let configuration = try parse(arguments: arguments)
    return HostCLIParsedArguments(
      appName: configuration.appName,
      bundleIdentifier: configuration.bundleIdentifier,
      captureMethod: configuration.captureMethod.rawValue,
      outputFormat: configuration.outputFormat.rawValue
    )
  }

  private static func parse(arguments: [String]) throws -> HostCLIConfiguration {
    var configuration = HostCLIConfiguration()
    let args = Array(arguments.dropFirst())

    var index = 0
    while index < args.count {
      let argument = args[index]
      switch argument {
      case "--capture":
        index += 1
      case "--app":
        configuration.appName = try value(for: argument, args: args, index: &index)
      case "--bundle-id":
        configuration.bundleIdentifier = try value(for: argument, args: args, index: &index)
      case "--method":
        let value = try value(for: argument, args: args, index: &index).lowercased()
        guard let method = HostCLICaptureMethod(rawValue: value) else {
          throw HostCLIError.invalidValue(flag: argument, value: value)
        }
        configuration.captureMethod = method
      case "--format":
        let value = try value(for: argument, args: args, index: &index).lowercased()
        guard let format = HostCLIOutputFormat(rawValue: value) else {
          throw HostCLIError.invalidValue(flag: argument, value: value)
        }
        configuration.outputFormat = format
      case "--help", "-h":
        throw HostCLIError.usageRequested
      default:
        throw HostCLIError.unknownArgument(argument)
      }
    }

    return configuration
  }

  private static func value(for flag: String, args: [String], index: inout Int) throws -> String {
    let valueIndex = index + 1
    guard valueIndex < args.count else {
      throw HostCLIError.missingValue(flag: flag)
    }

    let value = args[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !value.hasPrefix("-") else {
      throw HostCLIError.missingValue(flag: flag)
    }

    index = valueIndex + 1
    return value
  }

  private static func runCapture(configuration: HostCLIConfiguration) async throws -> HostCLICaptureResult {
    let targetApp = try resolveTargetApplication(configuration: configuration)
    if let targetApp {
      _ = targetApp.activate(options: [])
      let becameFrontmost = await waitForFrontmostApplication(
        targetProcessIdentifier: targetApp.processIdentifier,
        timeoutNanoseconds: cliTargetActivationTimeoutNanoseconds,
        pollIntervalNanoseconds: cliTargetActivationPollIntervalNanoseconds
      )
      if !becameFrontmost {
        throw HostCLIError.targetApplicationActivationFailed(
          name: targetApp.localizedName ?? configuration.appName,
          bundleIdentifier: targetApp.bundleIdentifier ?? configuration.bundleIdentifier
        )
      }
    }

    let fallbackFrontmost = targetApp == nil ? NSWorkspace.shared.frontmostApplication : nil
    let appName = targetApp?.localizedName ?? configuration.appName ?? fallbackFrontmost?.localizedName
    let bundleIdentifier = targetApp?.bundleIdentifier
      ?? configuration.bundleIdentifier
      ?? fallbackFrontmost?.bundleIdentifier
    let processIdentifier = targetApp?.processIdentifier ?? fallbackFrontmost?.processIdentifier

    let context = DesktopCaptureContext(
      appName: appName,
      bundleIdentifier: bundleIdentifier
    )
    let resolution = await resolveDesktopCaptureResolution(
      configuration: configuration,
      context: context,
      processIdentifier: processIdentifier
    )

    let requestID = UUID().uuidString.lowercased()
    let capturedAt = isoTimestamp()
    let markdown = renderMarkdown(
      requestID: requestID,
      capturedAt: capturedAt,
      extractionMethod: resolution.extractionMethod,
      payload: resolution.payload,
      outputPreset: .full,
      includeProductContextLine: HostSettings.defaultIncludeProductContextLine
    )

    return HostCLICaptureResult(
      requestID: requestID,
      capturedAt: capturedAt,
      resolution: resolution,
      markdown: markdown
    )
  }

  private static func resolveTargetApplication(
    configuration: HostCLIConfiguration
  ) throws -> NSRunningApplication? {
    if let bundleIdentifier = configuration.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
      !bundleIdentifier.isEmpty
    {
      if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
        return app
      }
      throw HostCLIError.targetApplicationNotFound(name: nil, bundleIdentifier: bundleIdentifier)
    }

    if let appName = configuration.appName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !appName.isEmpty
    {
      let lowercased = appName.lowercased()
      if let exactMatch = NSWorkspace.shared.runningApplications.first(where: {
        ($0.localizedName?.lowercased() ?? "") == lowercased
      }) {
        return exactMatch
      }

      if let partialMatch = NSWorkspace.shared.runningApplications.first(where: {
        ($0.localizedName?.lowercased() ?? "").contains(lowercased)
      }) {
        return partialMatch
      }

      throw HostCLIError.targetApplicationNotFound(name: appName, bundleIdentifier: nil)
    }

    return nil
  }

  private static func resolveDesktopCaptureResolution(
    configuration: HostCLIConfiguration,
    context: DesktopCaptureContext,
    processIdentifier: pid_t?
  ) async -> DesktopCaptureResolution {
    switch configuration.captureMethod {
    case .auto:
      return await resolveDesktopCapture(
        context: context,
        frontmostProcessIdentifier: processIdentifier
      )
    case .ax:
      let extractor = LiveDesktopAccessibilityExtractor()
      let dependencies = DesktopCaptureDependencies(
        accessibilityExtractor: { pid in
          extractor.extractFocusedText(frontmostProcessIdentifier: pid)
        },
        ocrExtractor: { _ in nil }
      )
      return await resolveDesktopCapture(
        context: context,
        frontmostProcessIdentifier: processIdentifier,
        dependencies: dependencies
      )
    case .ocr:
      let extractor = LiveDesktopOCRExtractor()
      let dependencies = DesktopCaptureDependencies(
        accessibilityExtractor: { _ in "" },
        ocrExtractor: { pid in
          await extractor.extractText(frontmostProcessIdentifier: pid)
        }
      )
      return await resolveDesktopCapture(
        context: context,
        accessibilityTextOverride: "",
        frontmostProcessIdentifier: processIdentifier,
        dependencies: dependencies
      )
    }
  }

  static func waitForFrontmostApplication(
    targetProcessIdentifier: pid_t,
    timeoutNanoseconds: UInt64,
    pollIntervalNanoseconds: UInt64,
    frontmostProcessIdentifierProvider: () -> pid_t? = {
      NSWorkspace.shared.frontmostApplication?.processIdentifier
    },
    sleep: (UInt64) async -> Void = { duration in
      try? await Task.sleep(nanoseconds: duration)
    }
  ) async -> Bool {
    let timeoutSeconds = TimeInterval(timeoutNanoseconds) / 1_000_000_000.0
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    repeat {
      if frontmostProcessIdentifierProvider() == targetProcessIdentifier {
        return true
      }
      await sleep(pollIntervalNanoseconds)
    } while Date() < deadline

    return frontmostProcessIdentifierProvider() == targetProcessIdentifier
  }

  private static func emit(
    result: HostCLICaptureResult,
    outputFormat: HostCLIOutputFormat
  ) throws {
    switch outputFormat {
    case .markdown:
      fputs(result.markdown, stdout)
      if !result.markdown.hasSuffix("\n") {
        fputs("\n", stdout)
      }
    case .json:
      let payload = HostCLIJSONOutput(
        requestID: result.requestID,
        capturedAt: result.capturedAt,
        extractionMethod: result.resolution.extractionMethod,
        transportStatus: result.resolution.transportStatus,
        warning: result.resolution.warning,
        errorCode: result.resolution.errorCode,
        payload: result.resolution.payload,
        markdown: result.markdown
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(payload)
      if let json = String(data: data, encoding: .utf8) {
        fputs(json, stdout)
        if !json.hasSuffix("\n") {
          fputs("\n", stdout)
        }
      } else {
        throw HostCLIError.captureExecutionFailed("Failed to encode JSON output.")
      }
    }
  }

  private static let usageText = """
  ContextGrabberHost CLI mode

  Usage:
    ContextGrabberHost --capture [--app <name>] [--bundle-id <id>] [--method auto|ax|ocr] [--format markdown|json]

  Examples:
    ContextGrabberHost --capture --app Finder
    ContextGrabberHost --capture --bundle-id com.apple.dt.Xcode --method ax
    ContextGrabberHost --capture --format json
  """
}
