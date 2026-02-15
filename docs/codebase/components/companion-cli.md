# Component: Companion CLI

> **Status:** The Bun/TS companion CLI (`packages/companion-cli`) has been removed. The Go CLI scaffold (`cli/`) is now implemented for inventory + diagnostics, with capture and MCP phases in progress. See `docs/plans/cli-expansion-plan.md` for the full plan.

## Architecture (current plan + implemented foundation)

The new CLI is a Go binary (`cli/`) that orchestrates capture via subprocesses:

- **Go → osascript** for tab/app enumeration and activation
- **Go → Bun** for browser extension-based capture (optional, requires Bun + extensions)
- **Go → ContextGrabberHost CLI mode** for desktop AX/OCR capture (`ContextGrabberHost --capture ...`)
- **Go MCP server** for agent integration via JSON-RPC over stdio

## Implemented Foundation (Milestone G Phase 1)

- `ContextGrabberHost` now supports a headless CLI mode (same binary path as GUI app).
- CLI mode currently supports:
  - `ContextGrabberHost --capture --help`
  - `ContextGrabberHost --capture --app <name>`
  - `ContextGrabberHost --capture --bundle-id <id>`
  - `ContextGrabberHost --capture --method auto|ax|ocr`
  - `ContextGrabberHost --capture --format markdown|json`
- This enables Go CLI desktop capture orchestration without introducing a separate Swift executable target.

## Implemented Go Scaffold (Milestone G Phase 2 - partial)

- `cli/` Go module initialized with cobra command framework.
- Implemented commands:
  - `context-grabber list tabs [--browser safari|chrome]`
  - `context-grabber list apps`
  - `context-grabber doctor`
- Global output routing is wired:
  - stdout (default)
  - `--file <path>`
  - `--clipboard`
  - `--format json|markdown`
- `doctor` now checks:
  - osascript availability
  - bun availability
  - `ContextGrabberHost` binary availability
  - Safari/Chrome bridge ping readiness (`--ping`, protocol compatibility)

## Planned Commands

| Command | Description |
| --- | --- |
| `list tabs [--browser safari\|chrome]` | Enumerate open browser tabs |
| `list apps` | Enumerate running desktop apps with windows |
| `capture --focused` | Capture currently focused browser tab |
| `capture --tab <index\|--url-match\|--title-match>` | Capture a specific browser tab |
| `capture --app <name\|--name-match\|--bundle-id>` | Capture a specific desktop app |
| `doctor` | System capability and health check |
| `serve` | Start MCP stdio server |

## Dependencies

- `github.com/spf13/cobra` — CLI framework
- `github.com/mark3labs/mcp-go` — MCP server
- Existing Bun native-messaging bridge CLIs (for browser capture)
- Existing `ContextGrabberHost` dual-mode binary (for desktop capture)
