# Component: Contracts and Bridge

## Shared Types
Path: `packages/shared-types`

### Defines
- Host request envelope types.
- Extension response and error envelopes.
- Validator helpers.
- Error code catalog.

## Native Host Bridge
Path: `packages/native-host-bridge`

### Responsibilities
1. Parse and validate extension envelopes.
2. Apply timeout-aware fallback behavior.
3. Normalize payload fields and truncation handling.
4. Render deterministic markdown utilities for TS-side consumers.

## Error Mapping
Primary codes:
- `ERR_PROTOCOL_VERSION`
- `ERR_PAYLOAD_INVALID`
- `ERR_TIMEOUT`
- `ERR_EXTENSION_UNAVAILABLE`
- `ERR_PAYLOAD_TOO_LARGE`

These codes map into host warning text and transport status labels.
