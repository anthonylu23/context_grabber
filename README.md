# Context Grabber

A local-first macOS menu bar app that captures active browser tabs and desktop apps into structured markdown for LLM workflows.

## Installation & Usage

### Homebrew (Recommended)

```bash
brew tap anthonylu23/context-grabber
brew install --cask context-grabber
```

This installs:
- **ContextGrabber.app** → `/Applications/ContextGrabber.app`
- **cgrab CLI** → `/usr/local/bin/cgrab`

After install, verify with `cgrab --version` and `cgrab doctor`.

### Direct Download

Download `context-grabber-macos-0.1.0.pkg` from [GitHub Releases](https://github.com/anthonylu23/context_grabber/releases) and open it. Right-click → Open if Gatekeeper blocks (unsigned).

### Build from Source

```bash
# Build and stage release artifacts, then assemble .pkg
STAGING_DIR=$(scripts/release/stage-macos-artifacts.sh)
scripts/release/build-macos-package.sh "$STAGING_DIR"
open .tmp/context-grabber-macos-0.1.0.pkg
```

### Development Setup
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

### Context Grabber CLI

The Go CLI lives under `cgrab/`:

#### Rebuild and run from repo

```bash
cd cgrab && go build .
./cgrab --help
```

Use `./cgrab ...` from `cgrab/` when running the local binary you just built.

#### Run without building (dev iteration)

```bash
cd cgrab
go run . --help
```

#### Install globally on PATH

```bash
# from repo root
./scripts/install-cli.sh
```

After install, run commands as `cgrab ...` from any directory.

#### Rebuild + reinstall after CLI code changes

```bash
cd cgrab && go build .
cd ..
./scripts/install-cli.sh
```

Verify:

```bash
command -v cgrab
cgrab --version
```

| Command | Description |
|---------|-------------|
| `cgrab list` | Show both open tabs and running apps |
| `cgrab list --tabs` | Show tabs only |
| `cgrab list --apps` | Show apps only |
| `cgrab list tabs` | Show open browser tabs |
| `cgrab list apps` | Show running desktop apps |
| `cgrab capture --focused` | Capture browser or desktop context |
| `cgrab capture --tab 1:2 --browser safari` | Capture a specific tab |
| `cgrab capture --app Finder` | Capture a desktop app |
| `cgrab config show` | Show current config |
| `cgrab config set-output-dir <subdir>` | Set capture output subdirectory |
| `cgrab doctor` | Run system health checks |
| `cgrab docs` | Open docs in browser |
| `cgrab skills install` | Install agent skill definitions |
| `cgrab skills uninstall` | Remove agent skill definitions |

Examples:

```bash
# inventory
cgrab list
cgrab list --tabs --browser safari
cgrab list --apps
cgrab list --format json

# capture
cgrab capture --focused
cgrab capture --tab 1:2 --browser safari
cgrab capture --app Finder --method auto

# diagnostics + config
cgrab doctor
cgrab config show
cgrab config set-output-dir projects/client-a
```

`go run . ...` from `cgrab/` also works during development. `go install` from `cgrab/` installs as `cgrab` as well.

By default, `cgrab capture` saves outputs under `~/contextgrabber/captures/` (or your configured subdirectory).
Use `CONTEXT_GRABBER_CLI_HOME=/absolute/path` to override the base storage folder.
For browser capture, `cgrab` attempts to auto-launch `ContextGrabber.app` before invoking extension bridge capture.

#### Outside the repo tree

- Desktop capture host resolution: `CONTEXT_GRABBER_HOST_BIN` env override -> repo debug host -> installed app fallback (`/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost`).
- Browser capture and diagnostics require repo assets — set `CONTEXT_GRABBER_REPO_ROOT=/path/to/context_grabber`.

### Agent Skills

Install skill definitions so AI coding agents (Claude Code, OpenCode, Cursor) can discover and use `cgrab`:

```bash
# skills.sh ecosystem (recommended)
npx skills add anthonylu23/context_grabber

# Or via cgrab itself
cgrab skills install
```

The skill teaches agents when and how to use `cgrab` for context capture, including the full command reference, output format, and common workflows. See `docs/codebase/usage/agent-workflows.md` for details.

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
- **Context Grabber CLI** — Go-based CLI with inventory/capture/diagnostics plus local config/docs helpers

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
| Agent integration | `docs/codebase/usage/agent-workflows.md` |
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
├── cgrab                   # Go CLI — `go install` produces `cgrab` binary
├── packages
│   ├── agent-skills        # Agent skill definitions + interactive installer
│   ├── extension-chrome    # Chrome extension
│   ├── extension-safari    # Safari extension
│   ├── extension-shared    # Shared extension transport, payload, and sanitization
│   ├── native-host-bridge  # Native messaging bridge
│   └── shared-types        # Shared contracts and types
├── skills
│   └── context-grabber     # skills.sh ecosystem discovery
├── packaging               # macOS .pkg installer metadata
├── scripts                 # Build, install, and release scripts
├── biome.json
├── bunfig.toml
├── package.json
└── tsconfig.base.json
```
