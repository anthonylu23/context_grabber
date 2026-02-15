# Component: Browser Extensions

## Safari Extension Package
Path: `packages/extension-safari`

### Includes
- Native messaging CLI transport.
- Runtime modules for background/content/native-host bridge.
- Runtime bootstrap entries (`background-main`, `content-main`).
- Manifest for packaged runtime wiring.
- Placeholder extension icon assets used by manifest (`assets/icons`).

### Hardening Notes
- Runtime bootstrap checks now validate API shape before registration.
- Runtime barrel no longer exports side-effectful bootstrap modules.

## Safari Container Project
Path: `apps/safari-container`

### Includes
- Generated Xcode project for macOS Safari extension installs.
- App target + Safari app-extension target wiring.
- Embedded packaged runtime resources (`manifest.json` + `dist/**`).

### Workflow
- `bun run safari:container:sync` regenerates the container project from current packaged runtime artifacts.
- `bun run safari:container:build` compile-validates the generated project with unsigned `xcodebuild`.

## Chrome Extension Package
Path: `packages/extension-chrome`

### Includes
- Native messaging CLI transport.
- AppleScript active-tab extraction helper.
- Source modes: `live`, `runtime`, `fixture`, `auto` (`live -> runtime`).

## Cross-Browser Guarantees
1. Shared protocol version and envelope shape.
2. Metadata-only fallback when capture fails.
3. Deterministic payload normalization contract before host rendering.
