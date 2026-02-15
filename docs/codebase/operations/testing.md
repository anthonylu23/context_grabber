# Testing Strategy

## Workspace Validation
```bash
bun run check
```
Runs lint, typecheck, and package tests across the workspace.

## Host Validation
```bash
cd apps/macos-host
swift build
swift test
```

## Safari Container Validation
```bash
bun run safari:container:sync
bun run safari:container:build
```

## Coverage Focus
1. Host (`CapturePipelineTests`)
- Browser target routing.
- Browser fallback mapping.
- Diagnostics presentation/status mapping.
- Desktop AX/OCR/metadata branches.
- Desktop AX threshold tuning for app-specific profiles.
- Deterministic markdown and truncation.
- Menu indicator helper behavior.
- Host retention label/ordering behavior.
- Settings load sanitization for persisted retention preferences.

2. Extension packages
- CLI request/response behavior.
- Source mode fallback behavior.
- Runtime bridge bootstraps and entrypoints.
- Contract validation and error paths.

3. Shared packages
- Envelope and payload validation.
- Timeout/unavailable fallback determinism.
