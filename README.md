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

### Packages
- `packages/shared-types`: shared contracts and message envelope types.
- `packages/extension-chrome`: Chrome extension TypeScript scaffold.
- `packages/extension-safari`: Safari extension TypeScript scaffold.
- `packages/native-host-bridge`: native-host bridge TypeScript scaffold.
- `apps/macos-host`: SwiftUI/AppKit menu bar host scaffold with mock capture flow.

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

## Project Layout
```text
.
├── apps
│   └── macos-host
├── docs
│   ├── plans
│   └── codebase
├── packages
│   ├── extension-chrome
│   ├── extension-safari
│   ├── native-host-bridge
│   └── shared-types
├── scripts
│   └── check-workspace.ts
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
- menu bar actions (`Capture Now`, `Open Recent Captures`, `Run Diagnostics`, `Quit`)
- global hotkey capture (`⌃⌥⌘C`) with parity to menu capture flow
- deterministic markdown generation from Safari transport responses
- local markdown persistence + clipboard copy
- local diagnostics (transport reachability + protocol compatibility) and host logging

## Next Steps
- replace Safari AppleScript extraction path with full Safari Web Extension runtime extraction
- add integration tests for timeout/unavailable/fallback and markdown determinism at host level
- add Chrome transport parity after Safari path is stable

## Documentation
- Docs index: `docs/README.md`
- Product plan: `docs/plans/context-grabber-project-plan.md`
- Architecture: `docs/codebase/architecture.md`
- Usage: `docs/codebase/usage.md`
- Codebase details: `docs/codebase/details.md`
