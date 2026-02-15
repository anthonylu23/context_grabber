# Local Development

## Prerequisites
- Bun installed.
- Xcode + Swift toolchain.
- macOS host environment.

## Setup
```bash
bun install
bun run check
```

## Run Host
```bash
cd /path/to/context_grabber
export CONTEXT_GRABBER_REPO_ROOT="$PWD"
cd apps/macos-host
swift run
```

## Run Host (Headless CLI Mode)
```bash
cd /path/to/context_grabber/apps/macos-host

# show CLI help
swift run ContextGrabberHost --capture --help

# capture a running desktop app by name
swift run ContextGrabberHost --capture --app Finder

# capture by bundle id and force AX-only method
swift run ContextGrabberHost --capture --bundle-id com.apple.dt.Xcode --method ax

# emit structured JSON (includes rendered markdown and capture metadata)
swift run ContextGrabberHost --capture --format json
```

## Safari Container Project
```bash
# regenerate from packaged Safari runtime assets
bun run safari:container:sync

# compile-check generated project (unsigned)
bun run safari:container:build
```

Open in Xcode:
```bash
open apps/safari-container/ContextGrabberSafari/ContextGrabberSafari.xcodeproj
```

Signed first-run checklist:
1. Set the same Apple Development team for both app and extension targets.
2. Keep extension bundle id prefixed by app bundle id.
3. Run `ContextGrabberSafari` app target, then enable extension in Safari Settings -> Extensions.
4. See `apps/safari-container/README.md` for troubleshooting details.

## Targeted Test Runs
```bash
# Swift host
cd apps/macos-host && swift test

# package tests
bun test --cwd packages/extension-safari
bun test --cwd packages/extension-chrome
```

## Companion CLI

The TS companion CLI has been removed. The Go CLI under `cli/` now supports list/capture/doctor.

```bash
cd /path/to/context_grabber/cli
go test ./...
go build -o cgrab .

# inventory commands
./cgrab list tabs --format json
./cgrab list apps --format json

# capture commands
./cgrab capture --focused
./cgrab capture --tab 1:2 --browser safari
./cgrab capture --tab --url-match "docs" --method applescript
./cgrab capture --app Finder --method auto

# diagnostics
./cgrab doctor --format json
```

Notes:
- Browser capture methods: `auto`, `applescript` (live extraction), `extension` (runtime payload path).
- Desktop capture methods: `auto`, `applescript` (alias of `auto`), `ax`, `ocr`.

For a short trigger command, build the binary as `cgrab`:

```bash
cd /path/to/context_grabber/cli
go build -o cgrab .
./cgrab --help
```

`go run . <command>` also works for quick local iteration.

## Browser Source Defaults
- Safari and Chrome CLI source `auto` now prefer AppleScript live extraction first, with runtime payload fallback only when runtime payload env vars are configured.
- Fixture capture remains explicit (`CONTEXT_GRABBER_*_SOURCE=fixture`) for deterministic testing.
