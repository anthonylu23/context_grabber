# Context Grabber

Context Grabber is a local-first macOS menu bar app that captures active user context and emits deterministic markdown for LLM workflows.

## Workspace Status
The initial Bun + TypeScript monorepo scaffold is set up with strict typing and shared contracts.

### Recent Hardening
- Runtime guards validate supported native message types and payload schemas at the bridge boundary.
- Package typecheck now includes both `src` and `test` files via `tsconfig.typecheck.json`.
- Workspace checks auto-discover package directories under `packages/`.
- `@context-grabber/shared-types` now exports Bun-first source for dev and `dist` output for default runtime consumers.

### Packages
- `packages/shared-types`: shared contracts and message envelope types.
- `packages/extension-chrome`: Chrome extension TypeScript scaffold.
- `packages/extension-safari`: Safari extension TypeScript scaffold.
- `packages/native-host-bridge`: native-host bridge TypeScript scaffold.

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

## Product Plan
Implementation milestones, capture contracts, and roadmap details live in `context-grabber-project-plan.md`.
