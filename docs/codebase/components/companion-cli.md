# Component: Companion CLI

> **Status:** The Bun/TS companion CLI (`packages/companion-cli`) has been removed. The Go CLI (`cli/`) now implements list/capture/doctor workflows.

## Architecture (current plan + implemented foundation)

The new CLI is a Go binary (`cli/`) that orchestrates capture via subprocesses:

- **Go → osascript** for tab/app enumeration and activation
- **Go → Bun** for browser extension-based capture (optional, requires Bun + extensions)
- **Go → ContextGrabberHost CLI mode** for desktop AX/OCR capture (`ContextGrabberHost --capture ...`)

## Implemented Foundation (Milestone G Phase 1)

- `ContextGrabberHost` now supports a headless CLI mode (same binary path as GUI app).
- CLI mode currently supports:
  - `ContextGrabberHost --capture --help`
  - `ContextGrabberHost --capture --app <name>`
  - `ContextGrabberHost --capture --bundle-id <id>`
  - `ContextGrabberHost --capture --method auto|ax|ocr`
  - `ContextGrabberHost --capture --format markdown|json`
- This enables Go CLI desktop capture orchestration without introducing a separate Swift executable target.

## Implemented Go CLI

- `cli/` Go module initialized with cobra command framework.
- Implemented commands:
  - `cgrab list tabs [--browser safari|chrome]`
  - `cgrab list apps`
  - `cgrab capture --focused`
  - `cgrab capture --tab <window:tab>`
  - `cgrab capture --tab --url-match <pattern>`
  - `cgrab capture --tab --title-match <pattern>`
  - `cgrab capture --app <name|--name-match|--bundle-id>`
  - `cgrab doctor`
- Global output routing is wired:
  - stdout (default)
  - `--file <path>`
  - `--clipboard`
  - `--format json|markdown`
- `doctor` checks:
  - osascript availability
  - bun availability
  - `ContextGrabberHost` binary availability
  - Safari/Chrome bridge ping readiness (`--ping`, protocol compatibility)

## Command Surface

| Command | Description |
| --- | --- |
| `list tabs [--browser safari\|chrome]` | Enumerate open browser tabs |
| `list apps` | Enumerate running desktop apps with windows |
| `capture --focused` | Capture currently focused browser tab |
| `capture --tab <window:tab \| --url-match \| --title-match>` | Capture a specific browser tab |
| `capture --app <name \| --name-match \| --bundle-id>` | Capture a specific desktop app |
| `doctor` | System capability and health check |

## Dependencies

- `github.com/spf13/cobra` — CLI framework
- Existing Bun native-messaging bridge CLIs (for browser capture)
- Existing `ContextGrabberHost` dual-mode binary (for desktop capture)
