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

## Context Grabber CLI

The TS companion CLI has been removed. The Go CLI under `cgrab/` now supports list/capture/doctor/config/docs.

### Rebuild local CLI binary

```bash
cd /path/to/context_grabber/cgrab
go build .
./cgrab --help
```

Use `./cgrab ...` when running from this directory.

### Run without rebuilding

```bash
cd /path/to/context_grabber/cgrab
go run . --help
```

### Typical command usage

```bash
cd /path/to/context_grabber/cgrab

# inventory commands
./cgrab list
./cgrab list --tabs --browser safari
./cgrab list --apps
./cgrab list tabs --format json
./cgrab list apps --format json

# capture commands
./cgrab capture --focused
./cgrab capture --tab 1:2 --browser safari
./cgrab capture --tab --url-match "docs" --method applescript
./cgrab capture --app Finder --method auto

# diagnostics
./cgrab doctor --format json

# config + docs
./cgrab config show
./cgrab config set-output-dir projects/client-a
./cgrab docs
```

Notes:
- `cgrab list` defaults to both tabs + apps when no selector flags are set.
- Browser capture methods: `auto`, `applescript` (live extraction), `extension` (runtime payload path).
- Desktop capture methods: `auto`, `applescript` (alias of `auto`), `ax`, `ocr`.
- Capture output default: `~/contextgrabber/captures/` (or configured subdir under `~/contextgrabber`).
- Config file: `~/contextgrabber/config.json`.
- Optional override for storage home: `CONTEXT_GRABBER_CLI_HOME=/absolute/path`.
- Browser capture auto-launches `ContextGrabber.app` when not running.
- Optional override for app bundle launch path: `CONTEXT_GRABBER_APP_BUNDLE_PATH=/absolute/path/to/ContextGrabber.app`.

## Install `cgrab` on PATH (dev)

```bash
cd /path/to/context_grabber
./scripts/install-cli.sh

# optional custom install location
./scripts/install-cli.sh --dest "$HOME/.local/bin"
```

If your shell cannot find `cgrab`, add the install location to zsh:

```bash
echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify global trigger behavior:

```bash
command -v cgrab
cgrab --version
cgrab doctor --format json
```

When you change CLI code and want the global command updated:

```bash
cd /path/to/context_grabber/cgrab
go build .
cd /path/to/context_grabber
./scripts/install-cli.sh
```

Outside the repo tree:
- desktop capture host resolution order is: `CONTEXT_GRABBER_HOST_BIN` -> repo debug host (`apps/macos-host/.build/debug/ContextGrabberHost`) -> installed app fallback (`/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost`).
- browser capture + browser bridge diagnostics still rely on repo assets (`packages/extension-*`), so set `CONTEXT_GRABBER_REPO_ROOT` for those workflows.

For browser workflows outside the repo tree, set:

```bash
export CONTEXT_GRABBER_REPO_ROOT="/path/to/context_grabber"
```

Optional override if desktop host binary is elsewhere:

```bash
export CONTEXT_GRABBER_HOST_BIN="/absolute/path/to/ContextGrabberHost"
```

`go run . <command>` still works for quick local iteration from `cgrab/`.

## Browser Source Defaults
- Safari and Chrome CLI source `auto` now prefer AppleScript live extraction first, with runtime payload fallback only when runtime payload env vars are configured.
- Fixture capture remains explicit (`CONTEXT_GRABBER_*_SOURCE=fixture`) for deterministic testing.
