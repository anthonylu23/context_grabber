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
- deterministic markdown generation from a bundled mock browser fixture
- local markdown persistence + clipboard copy
- local diagnostics and host logging

## Next Steps
- replace fixture capture with Safari native messaging handshake
- enforce `1200ms` extension timeout with metadata-only fallback wiring
- connect host runtime to shared protocol validators end-to-end
- add Chrome transport parity after Safari path is stable

## Product Plan
Implementation milestones, capture contracts, and roadmap details live in `context-grabber-project-plan.md`.
