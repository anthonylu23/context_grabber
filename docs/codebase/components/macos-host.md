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

## Current Operational Behavior
- Capture lock prevents concurrent runs (`captureInFlight`).
- Successful capture updates:
  - status line
  - menu icon indicator (`idle`, `capturing`, `success`, `error`, `disconnected`)
  - transient inline feedback panel (auto-dismissed)
  - recent captures list
  - clipboard and history file
- Failures preserve explicit warnings and error codes in status/markdown metadata.
- Desktop metadata-only fallbacks include a diagnostic excerpt when no extractable text is available.
- History storage resolves from settings:
  - default: `~/Documents/ContextGrabber/history`
  - custom: user-selected folder from menu preferences
- Post-write retention pruning is applied on each successful capture:
  - max file count
  - max file age (days)
- Menu preferences currently expose:
  - output directory selection/reset
  - retention max files
  - retention max age
  - clipboard copy mode (`Markdown File` or `Text`)
  - pause/resume capture placeholder toggle
- Menu also includes an About section with version/build labeling and handbook shortcut.
- Handbook shortcut resolves repo root through multiple runtime candidates (`CONTEXT_GRABBER_REPO_ROOT`, cwd, source path, bundle, executable path) to work from Finder/Xcode launches.
- Output directory changes are validated for writability before persistence.
- Diagnostics state is also surfaced inline in menu (`System Readiness`) for Safari, Chrome, Accessibility, and Screen Recording.
