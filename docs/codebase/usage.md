# Usage

## Prerequisites
- Bun installed.
- Xcode + Swift toolchain available.
- macOS (for `apps/macos-host`).

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
- `Capture Now`
- `Open Recent Captures`
- `Run Diagnostics`
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
- `CONTEXT_GRABBER_SAFARI_SOURCE`: set `fixture` to force fixture extraction; set `live` to force Safari active-tab extraction.
- `CONTEXT_GRABBER_SAFARI_FIXTURE_PATH`: override fixture path used by Safari bridge CLI.
