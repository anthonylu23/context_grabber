# Repository Map

## Top-Level
- `apps/macos-host`: native macOS host (SwiftUI/AppKit).
- `apps/safari-container`: generated Safari app-extension container Xcode project.
- `packages/shared-types`: protocol contracts and validators.
- `packages/extension-safari`: Safari bridge + runtime modules.
- `packages/extension-chrome`: Chrome bridge + extraction helpers.
- `packages/extension-shared`: shared extension transport, payload construction, sanitization, and document-script modules.
- `packages/native-host-bridge`: normalization and markdown helpers (TS side).
- `packages/agent-skills`: agent skill definition and reference docs for AI coding agents (SKILL.md + CLI reference, output schema, workflow patterns).
- `packages/companion-cli`: removed.
- `cgrab`: Go Context Grabber CLI (`list`, `capture`, `doctor`, `config`, `docs`). Directory named `cgrab` so `go install` produces the `cgrab` binary automatically.
- `docs`: plans + handbook.

## macOS Host Source Modules
- `Sources/ContextGrabberCore/`: shared library target used by GUI and CLI modes.
  - `BrowserCapturePipeline.swift`: browser transport result resolution + metadata fallback mapping.
  - `DesktopCapturePipeline.swift`: desktop AX/OCR extraction and resolver.
  - `DiagnosticsPresentation.swift`: diagnostics status + summary formatting helpers.
  - `MenuBarPresentation.swift`: menu icon state and capture label formatting helpers.
  - `MarkdownRendering.swift`: deterministic markdown renderer and related text helpers.
  - `HostSettings.swift`, `Summarization.swift`: settings persistence + summary generation.
  - `TransportLayer.swift`, `ProtocolTypes.swift`, `BrowserDetection.swift`, `CoreTypes.swift`: extracted protocol and transport core.
- `Sources/ContextGrabberHost/ContextGrabberHostLauncher.swift`: entrypoint that routes to GUI or headless CLI mode.
- `Sources/ContextGrabberHost/CLIEntryPoint.swift`: CLI-mode argument parsing + headless desktop capture execution.
- `Sources/ContextGrabberHost/ContextGrabberHostApp.swift`: SwiftUI menu bar app scene + host model orchestration.

## Test Locations
- Swift host tests: `apps/macos-host/Tests/ContextGrabberHostTests/CapturePipelineTests.swift`
- TS package tests: `packages/*/test/**/*.test.ts`
