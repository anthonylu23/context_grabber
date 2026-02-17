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

## CLI Validation
```bash
cd cgrab
go test ./...
```

## Safari Container Validation
```bash
bun run safari:container:sync
bun run safari:container:build
```

## Packaging + Release Validation
```bash
# Stage app + CLI artifacts
STAGING_DIR=$(scripts/release/stage-macos-artifacts.sh)

# Build installer package (defaults to .tmp/context-grabber-macos-<version>.pkg)
PKG_PATH=$(scripts/release/build-macos-package.sh "$STAGING_DIR")

# Inspect product package structure
pkgutil --expand "$PKG_PATH" "$(mktemp -d -t pkg-inspect)/expanded"

# Inspect payload paths
pkgutil --payload-files "$PKG_PATH"
```

Notes:
- Current release CI also validates postinstall user/home resolution behavior via a mocked smoke test.
- On newer macOS versions, `com.apple.provenance` may still produce cosmetic `._*` payload entries.

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

4. Go CLI (`cgrab/`)
- List/capture command parsing and flag validation.
- Osascript tab/app enumeration and partial-failure handling.
- Desktop/browser bridge subprocess dispatch and host auto-launch.
- Skills install/uninstall path resolution, embed fallback, round-trip.
- Config store persistence and path traversal rejection.

## Skill File Sync Check
```bash
bash scripts/check-skill-sync.sh
```
Verifies all 3 skill file locations (`packages/agent-skills/skill/`, `cgrab/internal/skills/`, `skills/context-grabber/`) are byte-identical. Run by CI in the `js-checks` job.
The check compares both file contents and full file trees (extra/missing files are flagged).
