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

The TS companion CLI has been removed. It is being rebuilt as a Go binary with MCP server support. See `docs/plans/cli-expansion-plan.md` for the implementation plan.

## Browser Source Defaults
- Safari and Chrome CLI source `auto` now prefer runtime payload input first, then fall back to AppleScript live extraction.
- Fixture capture remains explicit (`CONTEXT_GRABBER_*_SOURCE=fixture`) for deterministic testing.
