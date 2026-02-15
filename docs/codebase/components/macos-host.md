# Component: macOS Host

## Responsibilities
1. Present menu bar UI and global hotkey capture trigger.
2. Resolve capture target (Safari/Chrome/Desktop).
3. Execute capture pipeline and fallback handling.
4. Persist markdown history and copy clipboard output.
5. Surface diagnostics and permission remediation actions.

## Key Types and Flows
- `ContextGrabberModel`: runtime state and orchestration.
- `CaptureResolution`: unified capture result abstraction.
- `resolveCapture(request:)`: router entrypoint for browser/desktop capture.
- `createCaptureOutput(...)`: markdown rendering + output packaging.

## Refactored Internal Modules
1. `DesktopCapturePipeline.swift`
- Desktop capture data models.
- AX extraction utilities, including bounded focused-tree traversal and deduplicated attribute collection.
- App-aware AX extraction profile tuning (threshold + attribute set for dense editors and terminal apps).
- ScreenCaptureKit + Vision OCR pipeline.
- Protocol-driven dependency injection for desktop extractors.

2. `MenuBarPresentation.swift`
- Indicator state-to-symbol mapping.
- Capture feedback panel presentation models and formatting helpers.
- Last-capture relative label formatting.
- Disconnected-state heuristics.

3. `MarkdownRendering.swift`
- Frontmatter and body section rendering.
- Summary/key-point/chunk extraction helpers.
- YAML-safe quoting utilities.

4. `HostSettings.swift`
- UserDefaults-backed host preferences model.
- Output directory override + label helpers.
- Retention policy primitives and deterministic prune candidate ordering.
- Shared option sets for menu-driven retention controls.

5. `BrowserCapturePipeline.swift`
- Browser capture resolution and metadata fallback mapping.
- Shared `CaptureResolution` shape for browser/desktop resolver outputs.

6. `DiagnosticsPresentation.swift`
- Extension diagnostics status mapping from ping responses/errors.
- Diagnostics summary-string formatting helpers.
- Browser-target diagnostics transport status selection helper.

7. `CaptureResultPopup.swift`
- Non-activating floating popup controller for capture result summaries.
- Popup UI with quick actions (`Copy to Clipboard`, `Open File`, `Dismiss`).
- Popup positioning and non-focus-stealing presentation behavior.

8. `AdvancedSettingsView.swift`
- Advanced Settings form view (output, retention, summarization, capture controls).

## Current Operational Behavior
- Capture lock prevents concurrent runs (`captureInFlight`).
- Successful capture updates:
  - status line
  - menu icon indicator (`idle`, `capturing`, `success`, `error`, `disconnected`)
  - transient inline menu feedback panel (auto-dismissed)
  - transient floating capture-result popup (auto-dismissed) with quick actions
  - recent captures list
  - clipboard and history file
- Capture completion now uses the host popup surfaces instead of macOS user-notification banners.
- Failures preserve explicit warnings and error codes in status/markdown metadata.
- Desktop metadata-only fallbacks include a diagnostic excerpt when no extractable text is available.
- History storage resolves from settings:
  - default: `~/Documents/ContextGrabber/history`
  - custom: user-selected folder from menu preferences
- Post-write retention pruning is applied on each successful capture:
  - max file count
  - max file age (days)
- Menu `Settings` now exposes core controls only:
  - output directory selector (`Default`/`Custom`) with checkmark-selected state
  - clipboard copy mode (`Markdown File` or `Text`)
  - output format preset (`Brief` or `Full`)
  - product context line toggle
  - pause/resume capture placeholder toggle
  - `Advanced Settings...` action
- Advanced Settings window now exposes:
  - all core controls listed above
  - retention max files + max age controls
  - summarization controls (mode/provider/model/summary budget)
- Markdown output presets now control body verbosity:
  - `Brief`: summary, key points, links, and compact metadata only (chunks/raw excerpt omitted).
  - `Full`: full structured body including content chunks and raw excerpt.
- Summarization behavior:
  - deterministic heuristic summarization is the default path
  - LLM summarization is opt-in and provider-driven
  - LLM failures (missing credentials, timeout, invalid response) automatically fall back to heuristic summarization and append a warning in output frontmatter
- Menu also includes an About section with version/build labeling and handbook shortcut.
- Handbook shortcut resolves repo root through multiple runtime candidates (`CONTEXT_GRABBER_REPO_ROOT`, cwd, source path, bundle, executable path) to work from Finder/Xcode launches.
- Output directory changes are validated for writability before persistence.
- Diagnostics state is also surfaced inline in menu (`System Readiness`) for Safari, Chrome, Accessibility, and Screen Recording.

## Milestone G Phase 1 Status: Implemented

The host is now split into a shared library and a dual-mode executable.

### `ContextGrabberCore` (library target)
Shared capture/runtime logic now lives in `apps/macos-host/Sources/ContextGrabberCore/`:
- Refactored pipeline modules (`BrowserCapturePipeline.swift`, `DesktopCapturePipeline.swift`, `MarkdownRendering.swift`, `MenuBarPresentation.swift`, `DiagnosticsPresentation.swift`, `HostSettings.swift`, `Summarization.swift`)
- Monolith extractions:
  - `TransportLayer.swift` — Safari/Chrome native messaging transport execution
  - `ProtocolTypes.swift` — envelope/payload/request/response protocol shapes
  - `BrowserDetection.swift` — browser/channel resolution helpers
  - `CoreTypes.swift` — shared constants and host-level utility types

### `ContextGrabberHost` (single executable, dual mode)
- **GUI mode** (default): launches SwiftUI menu bar host.
- **CLI mode** (`--capture`): runs headless desktop capture and exits without SwiftUI initialization.
- Launcher file `ContextGrabberHostLauncher.swift` routes between CLI and GUI mode before app startup.
- `CLIEntryPoint.swift` currently supports:
  - `--capture`
  - `--app <name>` or `--bundle-id <id>`
  - `--method auto|ax|ocr`
  - `--format markdown|json`

### Why this architecture
macOS Accessibility and Screen Recording grants are tied to binary path. Reusing `ContextGrabberHost` for headless capture allows CLI invocations to reuse the same permission grant as the menu bar app. This is the desktop-capture subprocess surface for the upcoming Go companion CLI.

### Remaining Milestone G follow-ups
- Extend CLI mode argument surface to match final Go orchestration needs (`--focused`, tab/app targeting parity where applicable).
- Expand CLI test coverage further as capture subcommands are added (baseline parser/exit-code tests now exist in `CLIEntryPointTests.swift`).
