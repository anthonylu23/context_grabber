# ContextGrabberHost (macOS)

SwiftUI/AppKit menu bar host scaffold for Milestone A.

## Current Capabilities
- Menu bar app with actions:
  - `Capture Now (⌃⌥⌘C)` (menu action + global hotkey trigger)
  - `Open Recent Captures`
  - `Run Diagnostics`
  - `Quit`
- Sends a protocol-versioned host request to Safari native-messaging bridge (`@context-grabber/extension-safari`).
- Selects Safari or Chrome native-messaging bridge based on the frontmost browser app (with optional env override).
- Uses metadata-only fallback when bridge transport fails, times out, or returns invalid payloads.
- Bridge path performs live Safari active-tab extraction by default.
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
- Ensure Bun is installed and both extension packages exist in the repo root:
  - `packages/extension-safari`
  - `packages/extension-chrome`
- If the host cannot find Bun when launched outside a terminal, set `CONTEXT_GRABBER_BUN_BIN` to an absolute Bun binary path.
- You can override the Safari bridge fixture using `CONTEXT_GRABBER_SAFARI_FIXTURE_PATH`.
- Use `CONTEXT_GRABBER_SAFARI_SOURCE=fixture` to force fixture extraction or `CONTEXT_GRABBER_SAFARI_SOURCE=live` to force Safari extraction.
- Use `CONTEXT_GRABBER_BROWSER_TARGET=safari` or `CONTEXT_GRABBER_BROWSER_TARGET=chrome` to override frontmost-app channel selection.
- If Safari extraction fails, ensure Safari is running with at least one open window/tab.
- `swift run` launches an unbundled binary; user notifications are auto-disabled in this mode to avoid runtime crashes.

## Notes
- Safari native messaging currently uses AppleScript-driven active-tab extraction as transport scaffolding.
- AX/OCR desktop capture is intentionally deferred.

## Related Docs
- Project plan: `docs/plans/context-grabber-project-plan.md`
- Architecture: `docs/codebase/architecture.md`
- Usage: `docs/codebase/usage.md`
