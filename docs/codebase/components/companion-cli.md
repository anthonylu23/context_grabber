# Component: Companion CLI

Path: `packages/companion-cli`

## Responsibilities
1. Provide agent-friendly command-line entrypoints that reuse existing bridge contracts.
2. Surface extension health diagnostics (`doctor`) for Safari and Chrome native-messaging paths.
3. Trigger focused browser capture (`capture --focused`) and print deterministic markdown to stdout.

## Current Commands
- `doctor`
  - Pings Safari and Chrome bridge CLIs.
  - Reports per-channel readiness and an overall status.
- `capture --focused`
  - Uses browser target override when set (`CONTEXT_GRABBER_BROWSER_TARGET`).
  - Otherwise attempts Safari first, then Chrome.
  - Prints markdown to stdout on success.

## Implementation Notes
- Reuses `@context-grabber/native-host-bridge` for host-request framing, envelope validation, fallback handling, and deterministic markdown generation.
- Calls existing bridge CLIs (`packages/extension-safari/src/native-messaging-cli.ts`, `packages/extension-chrome/src/native-messaging-cli.ts`) through Bun rather than duplicating extraction logic.
- Maps bridge process timeouts to `ERR_TIMEOUT` so timeout behavior is handled as capture timeout (not extension-unavailable transport failure).
- Honors existing host environment conventions:
  - `CONTEXT_GRABBER_REPO_ROOT`
  - `CONTEXT_GRABBER_BUN_BIN`
  - `CONTEXT_GRABBER_BROWSER_TARGET`
