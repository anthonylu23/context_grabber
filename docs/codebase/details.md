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
- `packages/extension-safari`: transport handler + CLI integration tests.
- `packages/native-host-bridge`: fallback logic and determinism tests.
- Root `bun run check` runs lint + typecheck + tests for all packages.

## Current Known Scaffold Constraints
- Safari transport uses AppleScript-based live extraction by default (fixture source is optional via env override).
- `swift run` host mode is unbundled; user notifications are intentionally disabled in this mode.
- Desktop AX/OCR capture paths are planned but not yet implemented.
