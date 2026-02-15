# Repository Map

## Top-Level
- `apps/macos-host`: native macOS host (SwiftUI/AppKit).
- `apps/safari-container`: generated Safari app-extension container Xcode project.
- `packages/shared-types`: protocol contracts and validators.
- `packages/extension-safari`: Safari bridge + runtime modules.
- `packages/extension-chrome`: Chrome bridge + extraction helpers.
- `packages/native-host-bridge`: normalization and markdown helpers (TS side).
- `packages/companion-cli`: companion terminal interface (`doctor`, `capture --focused`).
- `docs`: plans + handbook.

## macOS Host Source Modules
- `ContextGrabberHostApp.swift`: app scene + host model orchestration and menu wiring.
- `BrowserCapturePipeline.swift`: browser transport result resolution and metadata fallback mapping.
- `DesktopCapturePipeline.swift`: desktop AX/OCR extraction and resolver.
- `DiagnosticsPresentation.swift`: diagnostics status + summary formatting helpers.
- `MenuBarPresentation.swift`: menu icon state and capture label formatting helpers.
- `MarkdownRendering.swift`: deterministic markdown renderer and related text helpers.

## Test Locations
- Swift host tests: `apps/macos-host/Tests/ContextGrabberHostTests/CapturePipelineTests.swift`
- TS package tests: `packages/*/test/**/*.test.ts`
