# Context Grabber

Context Grabber is a local-first macOS menu bar app that captures active user context and emits deterministic markdown for LLM workflows.

## Workspace Status
The initial Bun + TypeScript monorepo scaffold is set up with strict typing and shared contracts.

### Recent Hardening
- Runtime guards validate supported native message types and payload schemas at the bridge boundary.
- Package typecheck now includes both `src` and `test` files via `tsconfig.typecheck.json`.
- Workspace checks auto-discover package directories under `packages/`.
- `@context-grabber/shared-types` now exports Bun-first source for dev and `dist` output for default runtime consumers.
- Swift host capture now treats markdown write and clipboard write failures as capture failures.
- Swift host frontmatter values now use YAML-safe quoting/escaping.
- Swift host capture now uses a Safari native-messaging transport request instead of direct fixture reads.
- Safari extension package now includes a native-messaging CLI bridge and transport request handler.
- Safari CLI stdin handling is now validated via integration tests (real stdin -> JSON response path).
- Swift host now accepts structured bridge responses even if the bridge exits non-zero.
- Safari native-messaging CLI now performs live active-tab extraction from Safari by default.
- Global hotkey capture is now wired to the same capture pipeline (`⌃⌥⌘C`).
- Safari extraction now increases `spawnSync` max buffer to handle larger page payloads safely.
- Swift host now resolves Bun via explicit env/path fallbacks for non-terminal launch environments.
- Safari runtime now includes explicit Web Extension modules (`runtime/content`, `runtime/background`) for extension-side capture/request handling.
- Chrome extension now has protocol-parity transport + native-messaging CLI scaffolding and tests.
- Native host bridge tests now cover unavailable/invalid transport fallback and oversized-content truncation determinism.
- Safari runtime now includes a native host port binder (`runtime/native-host`) for packaged Web Extension request/response wiring.
- Safari CLI source resolution is now strict: `auto`/`live` require live extraction, and `fixture` is explicit opt-in for testing.
- Swift host now routes capture transport by frontmost browser (Safari or Chrome) and diagnostics report both channels.
- Menu-triggered host captures now prefer the last known browser app when the menu bar app is active.
- Swift host now has integration tests for truncation behavior, metadata-only fallback payload/markdown, and markdown determinism.
- Safari runtime now includes concrete packaged entrypoint helpers:
  - `runtime/background-entrypoint` for native-host port handling and active-tab content-script requests
  - `runtime/content-entrypoint` for content-script capture message handling
- Chrome now has live AppleScript active-tab extraction (`extract-active-tab`) and CLI source modes `live`, `runtime`, `fixture`, with `auto` fallback `live -> runtime` (fixture is explicit).
- Safari package now includes runtime bootstrap entry files (`runtime/background-main`, `runtime/content-main`) and a WebExtension `manifest.json` that references compiled runtime assets.
- A concrete Safari container app-extension project is now scaffolded at `apps/safari-container` via `safari-web-extension-converter`, using packaged runtime assets (`manifest.json` + `dist/**`).
- Safari extension manifest now includes placeholder icon assets (`packages/extension-safari/assets/icons`) and sync flow stages `icons/**` into the generated container.
- Host unsupported-app capture now uses a real desktop AX->OCR path:
  - AX focused-element extraction first
  - Vision OCR fallback second
  - metadata-only desktop fallback when both fail
- Host diagnostics now report desktop readiness (Accessibility + Screen Recording permission states).
- Desktop OCR image capture now uses ScreenCaptureKit (window-first, display fallback), replacing deprecated `CGWindowListCreateImage`.
- Host menu now includes one-click permission remediation actions for missing desktop permissions.
- Desktop AX extraction now walks focused element/window trees with bounded depth and app-aware threshold tuning for dense editor and terminal app profiles.
- Swift host integration tests now cover desktop AX/OCR branches and resolver-level timeout/unavailable mapping.
- Swift host internals are now split into focused modules:
  - `BrowserCapturePipeline.swift`
  - `DesktopCapturePipeline.swift`
  - `DiagnosticsPresentation.swift`
  - `MenuBarPresentation.swift`
  - `MarkdownRendering.swift`

### Packages
- `packages/shared-types`: shared contracts and message envelope types.
- `packages/extension-chrome`: Chrome extension TypeScript scaffold.
- `packages/extension-safari`: Safari extension TypeScript scaffold.
- `packages/native-host-bridge`: native-host bridge TypeScript scaffold.
- `apps/macos-host`: SwiftUI/AppKit menu bar host scaffold with mock capture flow.
- `apps/safari-container`: generated macOS Safari app-extension container project.

## Quick Start
```bash
bun install
bun run check
```

## Scripts
- `bun run lint`: run Biome checks.
- `bun run format`: format repository files with Biome.
- `bun run typecheck`: run TypeScript type checks across all packages.
- `bun run test`: run package tests.
- `bun run check`: lint + typecheck + test.
- `bun run safari:container:sync`: rebuild Safari runtime artifacts and regenerate the Safari container Xcode project.
- `bun run safari:container:build`: compile-validate Safari container project with unsigned `xcodebuild`.

## Project Layout
```text
.
├── apps
│   ├── macos-host
│   └── safari-container
├── docs
│   ├── plans
│   └── codebase
├── packages
│   ├── extension-chrome
│   ├── extension-safari
│   ├── native-host-bridge
│   └── shared-types
├── scripts
│   ├── build-safari-container.sh
│   ├── check-workspace.ts
│   └── sync-safari-container.sh
├── biome.json
├── bunfig.toml
├── package.json
└── tsconfig.base.json
```

## Host App (Milestone A Scaffold)
```bash
cd apps/macos-host
swift run
```

Current host capabilities:
- menu bar actions (`Capture Now`, `Recent Captures` submenu, `Copy Last Capture`, `Open History Folder`, `Run Diagnostics`, `Diagnostics Status` submenu, `Preferences`, `Open Accessibility Settings`, `Open Screen Recording Settings`, `Quit`)
- menu status surfaces: relative last-capture label and menu-bar icon indicator states (success/failure/disconnected)
- preferences-backed output controls for custom output directory and retention policy (max files, max age)
- retention/recent-history operations are scoped to host-generated capture files only (safe with mixed markdown folders)
- pause/resume capture placeholder toggle in menu
- global hotkey capture (`⌃⌥⌘C`) with parity to menu capture flow
- deterministic markdown generation from browser and desktop (AX/OCR) capture responses
- local markdown persistence + clipboard copy
- local diagnostics (transport reachability + protocol compatibility), probe-based storage writability checks, and host logging

Browser live extraction requirements:
- Safari: enable `Settings -> Developer -> Allow JavaScript from Apple Events` for AppleScript-based `do JavaScript` capture.
- Chrome: enable `View -> Developer -> Allow JavaScript from Apple Events` for AppleScript-based `execute javascript`.
- macOS Automation: allow the calling app (`Terminal`/host app) to control Safari/Chrome in `System Settings -> Privacy & Security -> Automation`.

## Next Steps
- down the line, shift to browser-extension-first capture (Safari/Chrome extension messaging as primary) and keep AppleScript fallback for dev modes.
- milestone F2 polish: capture feedback popup, custom menu bar icon, and lightweight settings surface polish.
- milestone G: companion CLI + agent integration using the shared capture pipeline.

## Documentation
- Docs index: `docs/README.md`
- Product plan: `docs/plans/context-grabber-project-plan.md`
- Codebase handbook index: `docs/codebase/README.md`
- Architecture overview: `docs/codebase/architecture/overview.md`
- Local dev usage: `docs/codebase/usage/local-dev.md`
- Testing strategy: `docs/codebase/operations/testing.md`
- Limits/defaults reference: `docs/codebase/reference/limits-and-defaults.md`
