# Codebase Details

## Protocol and Validation
- Protocol version constant: `1`.
- Host request type: `host.capture.request`.
- Extension result type: `extension.capture.result`.
- Extension error type: `extension.error`.
- Primary error codes:
  - `ERR_PROTOCOL_VERSION`
  - `ERR_PAYLOAD_INVALID`
  - `ERR_TIMEOUT`
  - `ERR_EXTENSION_UNAVAILABLE`
  - `ERR_PAYLOAD_TOO_LARGE`

## Key Limits and Defaults
- Default extension timeout: `1200ms`.
- Browser full-text cap: `200,000` chars.
- Envelope size cap: `250,000` serialized chars.
- Markdown raw excerpt cap: `8,000` chars.
- Safari AppleScript extraction max stdout/stderr buffer: `8MiB`.

## Deterministic Markdown Contract
- Frontmatter includes source/provenance/fidelity fields (`extraction_method`, `confidence`, `truncated`, warnings).
- Stable section order:
  - `Summary`
  - `Key Points`
  - `Content Chunks`
  - `Raw Excerpt`
  - `Links & Metadata`

## Testing Strategy
- `packages/shared-types`: protocol contracts and validator coverage.
- `packages/extension-safari`: transport handler + runtime modules (`content`, `background`, `native-host`) + CLI integration tests.
- `packages/extension-chrome`: protocol/transport/CLI parity tests.
- `packages/native-host-bridge`: fallback logic, invalid payload handling, and determinism/truncation tests.
- `apps/macos-host`: Swift integration tests for truncation, metadata-only fallback payload/markdown behavior, browser-target selection, and markdown determinism.
- Root `bun run check` runs lint + typecheck + tests for all packages.

## Current Known Scaffold Constraints
- Safari transport source resolution is strict:
  - `auto`/`live`: live AppleScript extraction only
  - `fixture`: explicit fixture mode
- Host channel routing selects Safari vs Chrome using effective frontmost app context (prefers last known browser app when the menu bar host is active).
- Chrome transport source resolution is runtime-or-fixture scaffolding, but fixture usage is explicit (`CONTEXT_GRABBER_CHROME_SOURCE=fixture`).
- `swift run` host mode is unbundled; user notifications are intentionally disabled in this mode.
- Desktop AX/OCR capture paths are planned but not yet implemented.
