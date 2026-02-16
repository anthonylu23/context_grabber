---
name: context-grabber
description: >
  Capture browser tabs and desktop app context as structured markdown
  for LLM workflows. Use when developers need to: (1) gather context
  from open browser tabs or running desktop apps, (2) create structured
  markdown from web pages or application state, (3) inventory open tabs
  or running apps. Triggers on: "cgrab", "context grabber", "capture
  context", "browser tabs", "desktop capture", "grab context".
---

# Context Grabber — Agent Skill

Capture the user's current browser tabs or desktop application context as structured, paste-ready markdown. Context Grabber is a local-first macOS tool that extracts page content, normalizes it, and produces deterministic markdown with YAML frontmatter, summaries, key points, and chunked content — designed for LLM consumption.

## When to Use

Use `cgrab` when the user:

- Asks you to look at, read, or capture what's in their browser tabs
- Wants context from a running desktop application (Finder, Xcode, Notes, etc.)
- Asks to "grab context", "capture this page", or "get what I'm looking at"
- Needs structured markdown from web pages for analysis or reference
- Wants to inventory their open tabs or running apps
- Mentions `cgrab` or `context-grabber` by name

## When NOT to Use

- The user wants to fetch a URL directly (use web fetch tools instead)
- The user wants to interact with a web page (click, fill forms, etc.)
- The task does not involve the user's currently open browser tabs or desktop apps

## Prerequisites

| Requirement | Needed For | Check |
|---|---|---|
| `cgrab` binary on PATH | All commands | `which cgrab` |
| `ContextGrabber.app` installed | Browser capture (auto-launched) | `cgrab doctor` |
| Bun runtime on PATH | Browser capture | `cgrab doctor` |
| Browser extension installed | Extension-based capture | `cgrab doctor` |
| Accessibility permissions | Desktop capture | System Settings > Privacy > Accessibility |

Run `cgrab doctor` to check system readiness. Desktop capture (via `--app`, `--name-match`, `--bundle-id`) only requires the host binary — no Bun or extensions needed.

## Core Workflow

The standard pattern is: **inventory → select → capture → use output**.

### Step 1: Inventory what's open

```bash
# List all open tabs and running apps
cgrab list

# List only browser tabs
cgrab list tabs

# List only running desktop apps
cgrab list apps

# List tabs from a specific browser
cgrab list tabs --browser safari
```

Example output:
```
# Open Tabs
- safari w1:t1 (active) - Apple Developer Documentation - https://developer.apple.com/documentation
- safari w1:t2 - Swift.org - https://swift.org
- chrome w1:t1 (active) - GitHub - https://github.com

# Running Apps
- Finder (com.apple.finder) - windows: 3
- Xcode (com.apple.dt.Xcode) - windows: 2
```

### Step 2: Select and capture

```bash
# Capture the currently focused browser tab
cgrab capture --focused

# Capture a specific tab by index (from list output)
cgrab capture --tab w1:t2 --browser safari

# Capture a tab matching a URL substring
cgrab capture --url-match "github.com"

# Capture a tab matching a title substring
cgrab capture --title-match "Swift"

# Capture a desktop app by exact name
cgrab capture --app Finder

# Capture a desktop app by name substring
cgrab capture --name-match xcode

# Capture by bundle identifier
cgrab capture --bundle-id com.apple.dt.Xcode
```

### Step 3: Use the output

By default, `cgrab capture` saves to `~/contextgrabber/captures/capture-<timestamp>.md` and prints the file path to stdout. To get structured output directly:

```bash
# Save to a specific file
cgrab capture --focused --file /tmp/context.md

# Copy to clipboard
cgrab capture --focused --clipboard

# Get JSON output for programmatic use
cgrab capture --focused --format json --file /tmp/context.json
```

## Output Format

Capture output is deterministic markdown with YAML frontmatter:

```yaml
---
id: "<uuid>"
captured_at: "<ISO8601>"
source_type: "webpage"              # or "desktop_app"
origin: "<url or app://bundleID>"
title: "<page or app title>"
extraction_method: "browser_extension"  # or "accessibility", "ocr"
confidence: 0.92
token_estimate: 1234
---
```

Followed by sections: **Summary**, **Key Points**, **Content Chunks**, **Raw Excerpt**, **Links & Metadata**. See `references/output-schema.md` for the complete structure.

## Selectors

Capture requires exactly one selector. Browser and desktop selectors cannot be mixed.

**Browser selectors** (pick one):
- `--focused` — currently active browser tab
- `--tab <w:t>` — by window:tab index (e.g., `w1:t2` or `1:2`)
- `--url-match <substring>` — first tab with matching URL (case-insensitive)
- `--title-match <substring>` — first tab with matching title (case-insensitive)

**Desktop selectors** (pick one):
- `--app <name>` — exact app name
- `--name-match <substring>` — first app matching name or bundle ID (case-insensitive)
- `--bundle-id <id>` — exact bundle identifier

## Error Handling

| Problem | Diagnostic | Recovery |
|---|---|---|
| Extension not reachable | `cgrab doctor` shows `unreachable` | Install extension, ensure ContextGrabber.app is running |
| Bun not found | `cgrab doctor` shows bun unavailable | Install Bun or set `CONTEXT_GRABBER_BUN_BIN` |
| Host binary not found | `cgrab doctor` shows host unavailable | Install ContextGrabber.app or set `CONTEXT_GRABBER_HOST_BIN` |
| Tab not found | Error message with selector details | Run `cgrab list tabs` to verify tab exists |
| App not found | Error message with selector details | Run `cgrab list apps` to verify app is running |
| Accessibility denied | Desktop capture returns minimal output | Grant Accessibility in System Settings > Privacy |
| No browser tabs captured | `--focused` falls back Safari → Chrome | Specify `--browser` explicitly |

When a capture fails, always suggest running `cgrab doctor --format json` for full diagnostics.

## Environment Variables

These override default paths for non-standard installations:

| Variable | Purpose |
|---|---|
| `CONTEXT_GRABBER_HOST_BIN` | Path to `ContextGrabberHost` binary |
| `CONTEXT_GRABBER_BUN_BIN` | Path to Bun runtime |
| `CONTEXT_GRABBER_BROWSER_TARGET` | Default browser (`safari` or `chrome`) |
| `CONTEXT_GRABBER_REPO_ROOT` | Repository root (needed for browser capture outside repo tree) |
| `CONTEXT_GRABBER_CLI_HOME` | Override base storage directory (default `~/contextgrabber`) |
| `CONTEXT_GRABBER_APP_BUNDLE_PATH` | Override `.app` bundle path for auto-launch |

See `references/cli-reference.md` for full details.

## Important Behaviors

1. **`capture` auto-saves when `--file` is omitted.** Output goes to `~/contextgrabber/captures/capture-<timestamp>.md`, not stdout. The file path is printed to stdout.
2. **`--focused` tries Safari first, then Chrome.** Use `--browser` to target a specific browser.
3. **Tab references from `list` are directly usable.** The `w1:t2` format in list output can be passed directly to `--tab w1:t2`.
4. **`doctor` exits non-zero on unhealthy status.** Use `cgrab doctor --format json` for machine-readable diagnostics.
5. **Desktop capture does not require Bun or extensions.** Only the host binary is needed.

## Reference Documents

- `references/cli-reference.md` — complete command, flag, and environment variable reference
- `references/output-schema.md` — markdown output structure and JSON mode documentation
- `references/workflows.md` — common agent workflow patterns and examples
