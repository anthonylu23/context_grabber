import Foundation

public let safariBundleIdentifiers: Set<String> = [
  "com.apple.Safari",
  "com.apple.SafariTechnologyPreview",
]

public let chromiumBundleIdentifiers: [String: String] = [
  "com.google.Chrome": "Google Chrome",
  "com.google.Chrome.canary": "Google Chrome Canary",
  "company.thebrowser.Browser": "Arc",
  "com.brave.Browser": "Brave Browser",
  "com.brave.Browser.beta": "Brave Browser Beta",
  "com.brave.Browser.nightly": "Brave Browser Nightly",
  "com.microsoft.edgemac": "Microsoft Edge",
  "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
  "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
  "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
  "com.vivaldi.Vivaldi": "Vivaldi",
  "com.operasoftware.Opera": "Opera",
  "com.operasoftware.OperaGX": "Opera GX",
]

/// Returns the AppleScript application name for a Chromium-based browser bundle identifier.
/// Falls back to "Google Chrome" if the bundle identifier is not recognized.
public func chromiumAppName(forBundleIdentifier bundleIdentifier: String?) -> String {
  guard let bundleIdentifier else { return "Google Chrome" }
  return chromiumBundleIdentifiers[bundleIdentifier] ?? "Google Chrome"
}

public enum BrowserTarget: Sendable {
  case safari
  case chrome
  case unsupported(appName: String?, bundleIdentifier: String?)

  public var browserLabel: String {
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

  public var transportStatusPrefix: String {
    switch self {
    case .safari:
      return "safari_extension"
    case .chrome:
      return "chrome_extension"
    case .unsupported:
      return "desktop_capture"
    }
  }

  public var displayName: String {
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

public func detectBrowserTarget(
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
    if chromiumBundleIdentifiers[frontmostBundleIdentifier] != nil {
      return .chrome
    }
  }

  return .unsupported(appName: frontmostAppName, bundleIdentifier: frontmostBundleIdentifier)
}
