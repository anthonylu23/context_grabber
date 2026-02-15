# Component: Companion CLI

> **Status:** The Bun/TS companion CLI (`packages/companion-cli`) has been removed. It is being rebuilt as a Go binary with an MCP server. See `docs/plans/cli-expansion-plan.md` for the full implementation plan.

## Architecture (planned)

The new CLI is a Go binary (`cli/`) that orchestrates capture via subprocesses:

- **Go → osascript** for tab/app enumeration and activation
- **Go → Bun** for browser extension-based capture (optional, requires Bun + extensions)
- **Go → Swift CLI** for desktop AX/OCR capture (`context-grabber-desktop` built from same `Package.swift`)
- **Go MCP server** for agent integration via JSON-RPC over stdio

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
- New Swift CLI target (for desktop capture)
