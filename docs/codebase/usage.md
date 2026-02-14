# Usage

## Prerequisites
- Bun installed.
- Xcode + Swift toolchain available.
- macOS (for `apps/macos-host`).
- Safari live extraction requires `Safari -> Settings -> Developer -> Allow JavaScript from Apple Events`.
- Chrome live extraction requires `Chrome -> View -> Developer -> Allow JavaScript from Apple Events`.
- Apple Events capture requires macOS Automation permission for the calling app in `System Settings -> Privacy & Security -> Automation`.

## Workspace Checks
```bash
bun install
bun run check
```

## Run macOS Host
```bash
cd /path/to/context_grabber
export CONTEXT_GRABBER_REPO_ROOT="$PWD"
cd apps/macos-host
swift run
```

## Host Menu Actions
- `Capture Now (⌃⌥⌘C)`
- `Open Recent Captures`
- `Run Diagnostics`
- `Open Accessibility Settings`
- `Open Screen Recording Settings`
- `Quit`

## Safari Bridge CLI
Ping:
```bash
bun run --cwd packages/extension-safari native-messaging --ping
```

Request/response over stdin:
```bash
printf '%s\n' '{"id":"req-1","type":"host.capture.request","timestamp":"2026-02-14T00:00:00.000Z","payload":{"protocolVersion":"1","requestId":"req-1","mode":"manual_menu","requestedAt":"2026-02-14T00:00:00.000Z","timeoutMs":1200,"includeSelectionText":true}}' \
| bun run --cwd packages/extension-safari native-messaging
```

## Output Locations
- Capture history: `~/Library/Application Support/ContextGrabber/history/`
- Host logs: `~/Library/Application Support/ContextGrabber/logs/host.log`

## Useful Environment Variables
- `CONTEXT_GRABBER_REPO_ROOT`: repo root used by host to resolve Safari bridge package.
- `CONTEXT_GRABBER_BUN_BIN`: absolute path to Bun binary for host bridge launches (recommended for app-launch environments with limited `PATH`).
- `CONTEXT_GRABBER_BROWSER_TARGET`: optional override (`safari` or `chrome`) for host browser-channel routing.
- `CONTEXT_GRABBER_SAFARI_SOURCE`: set `fixture` to force fixture extraction; `auto`/`live` require Safari live extraction.
- `CONTEXT_GRABBER_SAFARI_FIXTURE_PATH`: override fixture path used by Safari bridge CLI.
- `CONTEXT_GRABBER_SAFARI_OSASCRIPT_BIN`: optional absolute `osascript` path override for Safari live extraction.
- `CONTEXT_GRABBER_CHROME_SOURCE`: set `live`, `runtime`, `fixture`, or `auto` (`auto` falls back `live -> runtime`; fixture is explicit opt-in).
- `CONTEXT_GRABBER_CHROME_OSASCRIPT_BIN`: optional absolute `osascript` path override for Chrome live extraction.
- `CONTEXT_GRABBER_CHROME_FIXTURE_PATH`: override fixture path used by Chrome bridge CLI.
- `CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD`: inline JSON payload used by Chrome runtime source mode.
- `CONTEXT_GRABBER_CHROME_RUNTIME_PAYLOAD_PATH`: file path to JSON payload used by Chrome runtime source mode.
- Chrome runtime/fixture payloads are normalized with the same capture contract as live mode (`selectionText` is emitted only when `includeSelectionText: true`).
- `CONTEXT_GRABBER_DESKTOP_AX_TEXT`: optional host-side override for AX extracted text (testing/dev).
- `CONTEXT_GRABBER_DESKTOP_OCR_TEXT`: optional host-side override for OCR extracted text (testing/dev).
