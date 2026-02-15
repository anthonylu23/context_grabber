# Context Grabber

A local-first macOS menu bar app that captures active browser tabs and desktop apps into structured markdown for LLM workflows.

## Installation & Usage

### Quick Start
```bash
bun install
bun run check          # lint + typecheck + test
```

### Host App
```bash
cd apps/macos-host
swift run
```
Trigger captures via the menu bar icon or the global hotkey `⌃⌥⌘C`.

Browser live extraction requires JavaScript from Apple Events enabled in Safari (`Settings > Developer`) or Chrome (`View > Developer`), plus Automation permission for the calling app in `System Settings > Privacy & Security > Automation`.
Native bridge `auto` source mode now defaults to live extraction. Runtime payload env vars are only required for explicit `runtime` mode (or optional runtime fallback in `auto`).

### Companion CLI

The Go CLI scaffold now lives under `cli/`:

```bash
cd cli
go run . list tabs --format json
go run . list apps --format json
go run . doctor --format json
```

Capture commands and MCP server support are still in progress. See `docs/plans/cli-expansion-plan.md` for details.

### Scripts
| Command | Description |
|---------|-------------|
| `bun run lint` | Biome lint checks |
| `bun run format` | Biome formatting |
| `bun run typecheck` | TypeScript type checks |
| `bun run test` | Run package tests |
| `bun run check` | lint + typecheck + test |
| `bun run safari:container:sync` | Rebuild Safari runtime artifacts |
| `bun run safari:container:build` | Compile-validate Safari container |

## Features

- **Menu bar capture** — one-click or hotkey (`⌃⌥⌘C`) context capture
- **Browser extraction** — Safari and Chrome tab content via AppleScript
- **Desktop extraction** — AX focused-element extraction with Vision OCR fallback
- **Deterministic markdown** — structured output with frontmatter, summary, key points, and chunked content
- **LLM summarization** — optional OpenAI / Anthropic / Gemini / Ollama summarization (heuristic fallback)
- **Clipboard integration** — copy as markdown file reference or plain text
- **Output format presets** — brief (capped key points/links) or full output
- **Retention management** — configurable max file count and max age with safe pruning
- **Diagnostics** — transport reachability, permission status, and storage writability checks
- **Companion CLI** — Go-based CLI with inventory + diagnostics implemented (`list tabs`, `list apps`, `doctor`); capture + MCP in progress

## Architecture & Docs

The system follows a trigger → routing → capture → render pipeline. Browser contexts are extracted via native messaging bridges; desktop contexts use Accessibility and Vision OCR. All processing is local.

| Doc | Path |
|-----|------|
| Handbook index | `docs/codebase/README.md` |
| Architecture overview | `docs/codebase/architecture/overview.md` |
| Capture pipeline | `docs/codebase/architecture/capture-pipeline.md` |
| Component docs | `docs/codebase/components/` |
| Local dev | `docs/codebase/usage/local-dev.md` |
| Environment variables | `docs/codebase/usage/environment-variables.md` |
| Testing strategy | `docs/codebase/operations/testing.md` |
| Limits & defaults | `docs/codebase/reference/limits-and-defaults.md` |
| Project plan | `docs/plans/context-grabber-project-plan.md` |

## Settings

Configurable via the menu bar Settings submenu and Advanced Settings window:

| Setting | Options | Default |
|---------|---------|---------|
| Output directory | Default or custom path | `~/Documents/ContextGrabber` |
| Output format | Brief, Full | Full |
| Clipboard copy mode | Markdown file, Plain text | Markdown file |
| Product context line | On, Off | On |
| Retention max files | 0 (unlimited) – N | 200 |
| Retention max age | 0 (unlimited) – N days | 30 days |
| Summarization mode | Heuristic, LLM | Heuristic |
| Summarization provider | OpenAI, Anthropic, Gemini, Ollama | — |
| Summary token budget | Integer | 120 |
| Summary timeout | Milliseconds | 2500 |

LLM providers require corresponding API key environment variables. See `docs/codebase/usage/environment-variables.md`.

## Tech Stack

- **Host app**: Swift, SwiftUI, AppKit, ScreenCaptureKit, Vision
- **Extensions**: TypeScript, Bun, WebExtension APIs
- **Bridge**: Native messaging (Safari + Chrome)
- **Tooling**: Biome (lint/format), Xcode (Safari container)
- **Testing**: XCTest (Swift), Bun test (TypeScript)

## Project Layout
```text
.
├── apps
│   ├── macos-host          # SwiftUI/AppKit menu bar host
│   └── safari-container    # Safari app-extension container
├── docs
│   ├── plans               # Project plans
│   └── codebase            # Technical handbook
├── cli                     # Go CLI scaffold (list + doctor implemented)
├── packages
│   ├── extension-chrome    # Chrome extension
│   ├── extension-safari    # Safari extension
│   ├── native-host-bridge  # Native messaging bridge
│   └── shared-types        # Shared contracts and types
├── scripts                 # Build and workspace scripts
├── biome.json
├── bunfig.toml
├── package.json
└── tsconfig.base.json
```
