# CLI Expansion Plan: Go + Bun/Swift Hybrid

## Overview

Rebuild the Context Grabber companion CLI as a Go binary that orchestrates capture via subprocess calls to the existing Bun/TS pipeline (browser capture) and a new lightweight Swift CLI target (desktop AX/OCR capture). The Go binary also hosts an MCP server for agent integration.

The previous Bun/TS CLI (`packages/companion-cli`) has been removed. The Go CLI is a clean reimplementation that reuses the same underlying capture infrastructure (native-messaging bridge CLIs, Swift desktop pipeline) without duplicating capture logic.

## Architecture

```
Distribution artifacts:
  context-grabber              (Go, ~12MB)    CLI + MCP server
  context-grabber-desktop      (Swift, ~2MB)  AX/OCR desktop capture
  + existing Bun bridge CLIs   (TS)           browser extension capture (optional)

Required:  osascript (ships with macOS)
Optional:  bun + browser extensions (for rich browser capture)
```

### Subprocess Boundaries

| Boundary         | Used by                                              | Latency          |
| ---------------- | ---------------------------------------------------- | ---------------- |
| Go → osascript   | `list tabs`, `list apps`, tab/app activation         | ~150-300ms       |
| Go → Bun         | Browser extension capture (`capture --focused/--tab`)| ~400-700ms       |
| Go → Swift CLI   | Desktop capture (`capture --app`)                    | ~200-2200ms      |

### Rendering Ownership

Each subprocess owns its own markdown rendering. Go never renders markdown — it passes through what the subprocess emits to stdout.

- Browser captures: Bun/TS renders via `native-host-bridge/markdown.ts`
- Desktop captures: Swift renders via `MarkdownRendering.swift`

### Bun as Optional Dependency

The Go CLI works without Bun installed for: `list tabs`, `list apps`, `capture --app`, `doctor`, MCP server. Bun is only required for browser extension-based capture (`capture --focused`, `capture --tab`). The `doctor` command reports which capabilities are available.

## Go CLI Structure

```
cli/
  go.mod
  go.sum
  main.go
  cmd/
    root.go              cobra root command + global flags
    list.go              list tabs, list apps
    capture.go           capture --focused, --tab, --app
    doctor.go            diagnostics
    serve.go             MCP stdio server
  internal/
    osascript/
      tabs.go            AppleScript for tab enumeration + parsing
      apps.go            AppleScript for app enumeration + parsing
      activate.go        Tab/app activation via AppleScript
    bridge/
      bun.go             Bun subprocess: spawn, read stdout, error handling
      swift.go           Swift CLI subprocess: spawn, read stdout, error handling
      detect.go          Capability detection (Bun available? Swift CLI built?)
    mcp/
      server.go          MCP server setup, stdio transport
      tools.go           Tool definitions (list_tabs, list_apps, capture_*, doctor)
    output/
      writer.go          stdout / --file / --clipboard routing
```

### Dependencies

- `github.com/spf13/cobra` — CLI framework
- `github.com/mark3labs/mcp-go` — MCP server (stdio transport, tool definitions)
- Standard library for everything else (`os/exec`, `encoding/json`, `strings`, `fmt`)

### CLI Surface

```
context-grabber list tabs [--browser safari|chrome]
context-grabber list apps
context-grabber capture --focused [--method auto|applescript|extension]
context-grabber capture --tab <windowIndex:tabIndex> [--method auto|applescript|extension]
context-grabber capture --tab --url-match <pattern> [--method auto|applescript|extension]
context-grabber capture --tab --title-match <pattern> [--method auto|applescript|extension]
context-grabber capture --app <name> [--method auto|applescript|ax|ocr]
context-grabber capture --app --name-match <pattern> [--method auto|applescript|ax|ocr]
context-grabber capture --app --bundle-id <id> [--method auto|applescript|ax|ocr]
context-grabber doctor
context-grabber serve [--transport stdio]

Global flags:
  --file <path>             Write output to file instead of stdout
  --clipboard               Copy output to system clipboard (pbcopy)
  --format json|markdown    Output format (default: markdown; json for list commands)
  --help / -h
  --version / -v

Environment variables:
  CONTEXT_GRABBER_REPO_ROOT        Override repo root for locating Bun bridge CLIs
  CONTEXT_GRABBER_BUN_BIN          Override Bun binary path
  CONTEXT_GRABBER_BROWSER_TARGET   Force browser target (safari|chrome)
  CONTEXT_GRABBER_DESKTOP_BIN      Override Swift desktop capture binary path
```

### Capture Flow: `capture --tab`

1. If `--url-match` or `--title-match` provided: run `list tabs` internally, find first match
2. Activate the matched tab via AppleScript (`tell application "Safari" to set current tab of window W to tab T`)
3. Spawn Bun bridge CLI to capture the now-focused tab via `requestBrowserCapture`
4. Read markdown from stdout, pass through to output

Note: Tab activation briefly switches the user's active tab. This is a known trade-off — non-disruptive targeted capture would require protocol changes across multiple packages.

### Capture Flow: `capture --app`

1. If `--name-match` provided: run `list apps` internally, find first match
2. Activate the matched app via AppleScript (`tell application X to activate`)
3. Spawn the Swift desktop CLI: `context-grabber-desktop --app <name> --method auto`
4. Swift CLI runs AX extraction → OCR fallback → metadata-only fallback
5. Swift CLI renders markdown, writes to stdout
6. Go reads markdown, passes through to output

### MCP Tool Definitions

The MCP server (started via `context-grabber serve`) exposes tools that map 1:1 to CLI commands:

| Tool              | Description                              | Key Inputs                                         |
| ----------------- | ---------------------------------------- | -------------------------------------------------- |
| `list_tabs`       | Enumerate open browser tabs              | `browser?: "safari" \| "chrome"`                   |
| `list_apps`       | Enumerate running desktop apps           | (none)                                             |
| `capture_focused` | Capture the currently focused tab        | `method?: string`                                  |
| `capture_tab`     | Capture a specific browser tab           | `tab?, url_match?, title_match?, method?`          |
| `capture_app`     | Capture a specific desktop app           | `app?, name_match?, bundle_id?, method?`           |
| `doctor`          | Check system capabilities and health     | (none)                                             |

## Swift Desktop CLI Target

### Package.swift Changes

The existing monolithic `ContextGrabberHost` executable target must be split into a shared library and two executable targets.

Current structure:
```
Sources/ContextGrabberHost/    (all .swift files in one executable target)
```

New structure:
```
Sources/
  ContextGrabberHostLib/              shared library target
    DesktopCapturePipeline.swift       imports AppKit, Vision, etc.
    MarkdownRendering.swift            Foundation only
    HostSettings.swift                 Foundation only
    BrowserCapturePipeline.swift       Foundation only
    Summarization.swift                Foundation only
    MenuBarPresentation.swift
    DiagnosticsPresentation.swift
  ContextGrabberHost/                 menu bar app executable
    ContextGrabberHostApp.swift        SwiftUI app entry point
    AdvancedSettingsView.swift         SwiftUI settings view
    CaptureResultPopup.swift           NSPanel popup
    Resources/                         xcassets, icons, sample data
  ContextGrabberDesktopCLI/           desktop capture CLI executable
    main.swift                         ~50-80 lines, arg parsing + capture + stdout
```

### CLI Behavior

```
context-grabber-desktop --app "Xcode"
context-grabber-desktop --bundle-id "com.apple.dt.Xcode"
context-grabber-desktop --method ax|ocr|auto
context-grabber-desktop --format markdown|json
```

- Activates target app via `NSWorkspace`
- Runs `DesktopCapturePipeline.resolveDesktopCapture()`
- Renders markdown via `MarkdownRendering.swift` or outputs structured JSON
- Writes capture output to stdout, diagnostics to stderr
- Exit 0 on success, 1 on failure

### Access Control Changes

Files moving to `ContextGrabberHostLib` will need `public` access control on types and functions consumed by both executable targets. Key APIs:
- `resolveDesktopCapture()`
- `renderMarkdown()`
- `BrowserContextPayload` / `DesktopContextPayload` types
- `HostSettings` defaults
- `OutputFormatPreset` enum

## Implementation Phases

### Phase 0: Remove TS CLI ✅

Delete `packages/companion-cli/` and update all references (README, docs, bun.lock). The `check-workspace.ts` script auto-discovers packages so no code change is needed there.

### Phase 1: Swift Desktop CLI Target

**Goal:** `swift build` produces both `ContextGrabberHost` (menu bar app) and `ContextGrabberDesktopCLI` (headless capture).

Tasks:
1. Refactor `Package.swift`: create `ContextGrabberHostLib` library target
2. Move shared files to `Sources/ContextGrabberHostLib/`
3. Move GUI-only files to `Sources/ContextGrabberHost/` (stays as executable)
4. Add `public` access control to library APIs
5. Create `Sources/ContextGrabberDesktopCLI/main.swift`
6. Verify `swift build` compiles both targets
7. Verify `swift test` passes (55 tests)
8. Manual test: `swift run ContextGrabberDesktopCLI --app Finder`

**Estimated effort:** 1-2 sessions

### Phase 2: Go CLI Scaffold

**Goal:** `go build` produces a `context-grabber` binary with `list tabs`, `list apps`, and `doctor`.

Tasks:
1. Initialize `cli/` with `go mod init`, add cobra dependency
2. Implement `cmd/root.go` — root command, global flags, version
3. Implement `internal/osascript/tabs.go` — port tab enumeration AppleScript + parsing
4. Implement `internal/osascript/apps.go` — port app enumeration AppleScript + parsing
5. Implement `cmd/list.go` — `list tabs [--browser]` and `list apps` subcommands
6. Implement `internal/bridge/detect.go` — check Bun and Swift CLI availability
7. Implement `cmd/doctor.go` — capability detection, bridge health checks
8. Implement `internal/output/writer.go` — stdout/file/clipboard routing
9. Write Go tests with mocked `exec.Command` for osascript calls
10. Verify `go build` and `go test`

**Estimated effort:** 2-3 sessions

### Phase 3: Go Capture Commands

**Goal:** `capture --focused`, `capture --tab`, and `capture --app` work end-to-end.

Tasks:
1. Implement `internal/bridge/bun.go` — spawn Bun native-messaging CLIs, read stdout
2. Implement `internal/bridge/swift.go` — spawn `context-grabber-desktop`, read stdout
3. Implement `internal/osascript/activate.go` — activate specific tab or app via AppleScript
4. Implement `cmd/capture.go`:
   - `capture --focused` — spawn Bun bridge, read markdown
   - `capture --tab <index>` — activate tab, spawn Bun bridge
   - `capture --tab --url-match/--title-match` — list tabs, find match, activate, capture
   - `capture --app <name>` — activate app, spawn Swift CLI
   - `capture --app --name-match/--bundle-id` — list apps, find match, activate, capture
   - `--method` flag routing
5. Write Go tests with mocked subprocesses
6. End-to-end manual testing

**Estimated effort:** 2-3 sessions

### Phase 4: MCP Server

**Goal:** `context-grabber serve` starts an MCP stdio server with all tools registered.

Tasks:
1. Add `github.com/mark3labs/mcp-go` dependency
2. Implement `internal/mcp/tools.go` — tool definitions with JSON Schema inputs
3. Implement `internal/mcp/server.go` — register tools, wire handlers to command logic
4. Implement `cmd/serve.go` — `serve` subcommand, stdio transport
5. Test with MCP Inspector or JSON-RPC client
6. Write tool schema documentation

**Estimated effort:** 1-2 sessions

### Phase 5: Testing, Docs, and Integration

**Goal:** Full test coverage, updated documentation, agent-ready.

Tasks:
1. Go test coverage for all packages
2. Swift CLI test coverage (new tests in existing test target)
3. Update `docs/codebase/components/companion-cli.md` → Go CLI docs
4. Update `docs/codebase/usage/local-dev.md` with Go CLI usage
5. Update `README.md` with Go CLI installation and usage
6. Update project plan with Milestone G progress
7. Prepare `skills.md` structure (user writes the content)
8. Update `AGENTS.md` if needed for Go development workflow

**Estimated effort:** 1-2 sessions

## Behavioral Reference (from removed TS CLI)

The following behaviors from the TS CLI should be preserved in the Go reimplementation:

### List commands
- Tab entries include: `browser`, `windowIndex`, `tabIndex`, `isActive`, `title`, `url`
- App entries include: `appName`, `bundleIdentifier`, `windowCount`
- Tabs sorted by browser → windowIndex → tabIndex
- Apps sorted by appName → bundleIdentifier
- Partial success: if one browser fails but another succeeds, exit 0 with warnings on stderr
- Full failure: exit 1 with error details on stderr
- Output format: JSON array to stdout

### Doctor command
- Pings Safari and Chrome bridges in parallel
- Reports per-target state: `ready`, `protocol_mismatch`, `unreachable`
- Overall status: `ready` if at least one bridge is ready, `unreachable` otherwise
- Exit 0 if ready, 1 if unreachable

### Capture command
- Browser target override via `CONTEXT_GRABBER_BROWSER_TARGET` env var
- Default order: try Safari first, fall back to Chrome
- Extension unavailable: try next browser before failing
- Markdown output to stdout on success
- Diagnostic error to stderr on failure
- Exit 0 on success, 1 on failure

### Environment variables (carry forward)
- `CONTEXT_GRABBER_REPO_ROOT` — repo root override for locating bridge CLIs
- `CONTEXT_GRABBER_BUN_BIN` — Bun binary override
- `CONTEXT_GRABBER_BROWSER_TARGET` — force `safari` or `chrome`
- `CONTEXT_GRABBER_OSASCRIPT_BIN` — osascript binary override (rename to generic in Go)

### Delimiter conventions
- Tab/app enumeration uses ASCII RS (0x1E) as field delimiter and US (0x1F) as line delimiter in AppleScript output
- These are internal to the osascript interaction; JSON is the external interface

## Exit Criteria (Milestone G)

From the project plan:
- `list` + `capture --focused` + `capture --tab` + `capture --app` work end-to-end
- At least one agent skill manifest (MCP) is functional and discoverable
- CLI reuses the same pipeline code as the host app with no duplicated capture logic

Additional:
- `swift build` produces both host app and desktop CLI
- `go build` produces the main CLI binary
- `go test` and `swift test` pass
- `doctor` reports capability status accurately
- MCP server responds correctly to tool calls via stdio

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Swift library extraction breaks existing tests | High | Run `swift test` after each refactoring step |
| AppKit import in library target causes CLI issues | Medium | AppKit links fine without UI on macOS; verify with `swift build` early |
| mcp-go is pre-1.0, may have breaking changes | Low | Pin specific version in `go.mod` |
| Tab activation is disruptive (switches user's active tab) | Medium | Document behavior; consider `--no-activate` flag for metadata-only |
| Go osascript parsing diverges from TS implementation | Medium | Port exact delimiter constants; use TS tests as behavioral reference |
| Bun startup latency for browser capture | Low | ~100ms overhead is acceptable for a CLI tool |
