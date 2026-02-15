# Testing Strategy

## Workspace Validation
```bash
bun run check
```
Runs lint, typecheck, and package tests across the workspace.

## Host Validation
```bash
cd apps/macos-host
swift test
```

## Coverage Focus
1. Host (`CapturePipelineTests`)
- Browser target routing.
- Browser fallback mapping.
- Desktop AX/OCR/metadata branches.
- Deterministic markdown and truncation.
- Menu indicator helper behavior.

2. Extension packages
- CLI request/response behavior.
- Source mode fallback behavior.
- Runtime bridge bootstraps and entrypoints.
- Contract validation and error paths.

3. Shared packages
- Envelope and payload validation.
- Timeout/unavailable fallback determinism.
