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
- AX extraction utilities.
- ScreenCaptureKit + Vision OCR pipeline.
- Protocol-driven dependency injection for desktop extractors.

2. `MenuBarPresentation.swift`
- Indicator state-to-symbol mapping.
- Last-capture relative label formatting.
- Disconnected-state heuristics.

3. `MarkdownRendering.swift`
- Frontmatter and body section rendering.
- Summary/key-point/chunk extraction helpers.
- YAML-safe quoting utilities.

## Current Operational Behavior
- Capture lock prevents concurrent runs (`captureInFlight`).
- Successful capture updates:
  - status line
  - menu icon indicator
  - recent captures list
  - clipboard and history file
- Failures preserve explicit warnings and error codes in status/markdown metadata.
