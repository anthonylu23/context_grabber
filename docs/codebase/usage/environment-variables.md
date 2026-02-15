# Environment Variables

## Host Runtime
- `CONTEXT_GRABBER_REPO_ROOT`: repo path for host bridge resolution.
- `CONTEXT_GRABBER_BUN_BIN`: explicit Bun binary path for app-launch environments.
- `CONTEXT_GRABBER_BROWSER_TARGET`: force browser routing (`safari` or `chrome`).

## Safari Bridge
- `CONTEXT_GRABBER_SAFARI_SOURCE`: `auto`, `live`, or `fixture`.
- `CONTEXT_GRABBER_SAFARI_FIXTURE_PATH`: fixture override path.
- `CONTEXT_GRABBER_SAFARI_OSASCRIPT_BIN`: AppleScript executable override.

## Chrome Bridge
- `CONTEXT_GRABBER_CHROME_SOURCE`: `live`, `runtime`, `fixture`, or `auto`.
- `CONTEXT_GRABBER_CHROME_OSASCRIPT_BIN`: AppleScript executable override.
- `CONTEXT_GRABBER_CHROME_FIXTURE_PATH`: fixture override path.
- `CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD`: inline runtime JSON payload.
- `CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD_PATH`: runtime JSON payload file path.

## Desktop Testing Overrides
- `CONTEXT_GRABBER_DESKTOP_AX_TEXT`: force AX text for host-side testing.
- `CONTEXT_GRABBER_DESKTOP_OCR_TEXT`: force OCR text for host-side testing.
