# Component: Context Grabber CLI

> **Status:** The Bun/TS companion CLI (`packages/companion-cli`) has been removed. The Go CLI (`cgrab/`) now implements list/capture/doctor/config/docs workflows.

## Architecture (current plan + implemented foundation)

The new CLI is a Go binary (`cgrab/`) that orchestrates capture via subprocesses:

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

- `cgrab/` Go module initialized with cobra command framework.
- Implemented commands:
  - `cgrab list` (defaults to both tabs + apps)
  - `cgrab list --tabs [--browser safari|chrome]`
  - `cgrab list --apps`
  - `cgrab list tabs [--browser safari|chrome]`
  - `cgrab list apps`
  - `cgrab capture --focused`
  - `cgrab capture --tab <window:tab>`
  - `cgrab capture --tab --url-match <pattern>`
  - `cgrab capture --tab --title-match <pattern>`
  - `cgrab capture --app <name|--name-match|--bundle-id>`
  - `cgrab doctor`
  - `cgrab config show`
  - `cgrab config set-output-dir <subdir>`
  - `cgrab config reset-output-dir`
  - `cgrab docs`
- Global output routing is wired:
  - stdout (default)
  - `--file <path>`
  - `--clipboard`
  - `--format json|markdown`
- Capture defaults:
  - if `--file` is omitted for `capture`, output is saved to `~/contextgrabber/<configured-subdir>/`
  - config is persisted at `~/contextgrabber/config.json`
  - `CONTEXT_GRABBER_CLI_HOME` can override the base storage folder (must be an absolute path)
  - browser capture attempts to auto-launch `ContextGrabber.app` before extension bridge capture
- `doctor` checks:
  - osascript availability
  - bun availability
  - `ContextGrabberHost` binary availability
  - Safari/Chrome bridge ping readiness (`--ping`, protocol compatibility)

## Command Surface

| Command | Description |
| --- | --- |
| `list [--tabs|--apps]` | Enumerate both inventories by default, or filter to tabs/apps |
| `list tabs [--browser safari\|chrome]` | Enumerate open browser tabs |
| `list apps` | Enumerate running desktop apps with windows |
| `capture --focused` | Capture currently focused browser tab |
| `capture --tab <window:tab \| --url-match \| --title-match>` | Capture a specific browser tab |
| `capture --app <name \| --name-match \| --bundle-id>` | Capture a specific desktop app |
| `doctor` | System capability and health check |
| `config show` | Show current CLI storage/config paths |
| `config set-output-dir <subdir>` | Set capture output subdirectory under `~/contextgrabber` |
| `config reset-output-dir` | Reset capture output path to default (`captures`) |
| `docs` | Open the GitHub repository in browser (fallback prints URL) |
| `skills install` | Install agent skill definitions (Bun interactive/non-interactive; fallback → embedded) |
| `skills uninstall` | Remove installed agent skill definitions |

## Agent Skill Installation

`cgrab skills install` provides two paths:

1. **Bun available:** delegates to `bunx @context-grabber/agent-skills` for the full interactive experience (Claude Code, OpenCode, Cursor with .mdc conversion, global/project scope selection).
2. **No Bun:** uses `go:embed` fallback to copy skill files directly. Supports Claude Code and OpenCode only (Cursor requires Bun for .mdc format conversion). Uses `--agent` and `--scope` flags.

When `--agent` and/or `--scope` are explicitly provided, the Bun path forwards them to the TS installer and runs non-interactively. If that non-interactive Bun delegation fails, `cgrab` falls back to the embedded installer. Interactive Bun failures are returned as errors (no automatic fallback).

Embedded skill files at `cgrab/internal/skills/` must stay in sync with the canonical source at `packages/agent-skills/skill/`. CI enforces this via `scripts/check-skill-sync.sh`.

## Dependencies

- `github.com/spf13/cobra` — CLI framework
- Existing Bun native-messaging bridge CLIs (for browser capture)
- Existing `ContextGrabberHost` dual-mode binary (for desktop capture)

## Global Trigger (dev setup)

Build local binary:

```bash
cd /path/to/context_grabber/cgrab
go build .
./cgrab --help
```

Install `cgrab` into a PATH directory:

```bash
cd /path/to/context_grabber
./scripts/install-cli.sh
```

Verify:

```bash
command -v cgrab
cgrab --version
cgrab doctor --format json
```

After CLI code changes, rebuild + reinstall to refresh global `cgrab`:

```bash
cd /path/to/context_grabber/cgrab
go build .
cd /path/to/context_grabber
./scripts/install-cli.sh
```

Current limitation: desktop host resolution order is `CONTEXT_GRABBER_HOST_BIN` -> repo debug host -> `/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost`; browser bridge workflows still rely on repo assets unless `CONTEXT_GRABBER_REPO_ROOT` is set.
