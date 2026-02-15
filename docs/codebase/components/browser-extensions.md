# Component: Browser Extensions

## Safari Extension Package
Path: `packages/extension-safari`

### Includes
- Native messaging CLI transport.
- Runtime modules for background/content/native-host bridge.
- Runtime bootstrap entries (`background-main`, `content-main`).
- Manifest for packaged runtime wiring.

### Hardening Notes
- Runtime bootstrap checks now validate API shape before registration.
- Runtime barrel no longer exports side-effectful bootstrap modules.

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
