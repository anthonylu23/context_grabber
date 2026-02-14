# ContextGrabberHost (macOS)

SwiftUI/AppKit menu bar host scaffold for Milestone A.

## Current Capabilities
- Menu bar app with actions:
  - `Capture Now`
  - `Open Recent Captures`
  - `Run Diagnostics`
  - `Quit`
- Sends a protocol-versioned host request to Safari native-messaging bridge (`@context-grabber/extension-safari`).
- Uses metadata-only fallback when bridge transport fails, times out, or returns invalid payloads.
- Generates deterministic markdown and writes to:
  - `~/Library/Application Support/ContextGrabber/history/`
- Copies markdown output to clipboard.
- Writes local logs to:
  - `~/Library/Application Support/ContextGrabber/logs/host.log`

## Run
```bash
cd /path/to/context_grabber
export CONTEXT_GRABBER_REPO_ROOT=\"$PWD\"
cd apps/macos-host
swift run
```

## Troubleshooting
- If capture falls back to metadata-only, run `Run Diagnostics` from the menu and check transport reachability.
- Ensure Bun is installed and `packages/extension-safari` exists in the repo root.
- You can override the Safari bridge fixture using `CONTEXT_GRABBER_SAFARI_FIXTURE_PATH`.

## Notes
- Safari native messaging currently uses a fixture-backed extension source as transport scaffolding.
- AX/OCR desktop capture is intentionally deferred.
