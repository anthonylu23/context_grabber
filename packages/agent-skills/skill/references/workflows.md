# Agent Workflows

Common patterns for AI agents using `cgrab` to capture and use context.

## Research Workflow — Multi-Tab Capture

When the user has multiple relevant tabs open and you need context from several of them:

```bash
# 1. List all open tabs
cgrab list tabs

# 2. Identify relevant tabs from the listing, then capture each
cgrab capture --tab w1:t1 --browser safari --file /tmp/tab1.md
cgrab capture --tab w1:t3 --browser safari --file /tmp/tab2.md
cgrab capture --url-match "docs.python.org" --file /tmp/python-docs.md

# 3. Read the captured files for analysis
cat /tmp/tab1.md
```

**Tips:**
- Use `--url-match` or `--title-match` when tab indices might change
- Save to specific files with `--file` to read them back programmatically
- The `w1:t2` references from `cgrab list tabs` output can be used directly with `--tab`

## Focused Capture — Quick Context

When the user says "look at what I have open" or "capture this page":

```bash
# Capture whatever browser tab is currently focused
cgrab capture --focused --file /tmp/focused.md
```

This tries Safari first, then Chrome. If you know the user's preferred browser:

```bash
cgrab capture --focused --browser chrome --file /tmp/focused.md
```

## Desktop App Context

When the user wants context from a non-browser application:

```bash
# 1. List running apps to find the target
cgrab list apps

# 2. Capture by exact name
cgrab capture --app "Xcode" --file /tmp/xcode-context.md

# 3. Or capture by name substring (case-insensitive)
cgrab capture --name-match "finder" --file /tmp/finder-context.md

# 4. Or by bundle identifier
cgrab capture --bundle-id com.apple.dt.Xcode --file /tmp/xcode.md
```

**Desktop capture methods:**
- `auto` (default): tries Accessibility first, falls back to OCR
- `--method ax`: force Accessibility API (best for text-heavy apps)
- `--method ocr`: force Vision OCR (useful when AX returns minimal content)

```bash
# Force OCR if the default method returns sparse content
cgrab capture --app "Preview" --method ocr --file /tmp/preview.md
```

## Diagnostics Workflow

When capture fails or returns unexpected results:

```bash
# Run full diagnostics
cgrab doctor --format json
```

Check the JSON output for:
- `overallStatus`: should be `"ready"`
- `bunAvailable`: required for browser capture
- `hostBinaryAvailable`: required for desktop capture
- `bridges[].status`: each browser's extension readiness

If doctor shows issues, relay the specific warnings to the user with actionable fixes.

## JSON Mode — Programmatic Use

When you need structured data rather than markdown:

```bash
# List tabs as JSON for programmatic processing
cgrab list tabs --format json

# Capture with JSON output
cgrab capture --focused --format json --file /tmp/capture.json
```

The JSON capture output includes both the rendered markdown and the raw payload, making it useful when you need to parse specific fields:

```json
{
  "target": "safari",
  "extractionMethod": "browser_extension",
  "markdown": "---\nid: ...\n---\n...",
  "payload": {
    "url": "https://...",
    "title": "...",
    "fullText": "..."
  }
}
```

## Clipboard Integration

When the user wants captured content on their clipboard:

```bash
# Capture to clipboard
cgrab capture --focused --clipboard

# Capture to both file and clipboard
cgrab capture --focused --file /tmp/context.md --clipboard
```

Note: when both `--file` and `--clipboard` are set, output goes to both but nothing is printed to stdout.

## Tab Search Patterns

When you need to find a specific tab among many:

```bash
# Find a tab by URL substring
cgrab capture --url-match "stackoverflow.com/questions/12345"

# Find a tab by title substring
cgrab capture --title-match "React hooks"

# If multiple browsers might have matching tabs, specify the browser
cgrab capture --url-match "github.com" --browser chrome
```

URL and title matching are case-insensitive substring searches. If the match is ambiguous (e.g., multiple tabs match), the first match is used.

## Configuration for Non-Standard Setups

When `cgrab` can't find its dependencies:

```bash
# Point to a custom host binary location
export CONTEXT_GRABBER_HOST_BIN=/path/to/ContextGrabberHost

# Point to a custom Bun installation
export CONTEXT_GRABBER_BUN_BIN=/path/to/bun

# Set repo root when running outside the project tree
export CONTEXT_GRABBER_REPO_ROOT=/path/to/context_grabber

# Change default capture output directory
cgrab config set-output-dir my-captures
```

## Error Recovery Patterns

### Extension not reachable

```bash
# Check what's wrong
cgrab doctor

# If ContextGrabber.app isn't running, the CLI tries to auto-launch it.
# If auto-launch fails, tell the user:
# "Please open ContextGrabber.app from your Applications folder."
```

### Capture returns sparse content

```bash
# Try a different extraction method
cgrab capture --app "Notes" --method ocr --file /tmp/notes.md

# Check if Accessibility permissions are granted
# System Settings > Privacy & Security > Accessibility
```

### Tab index changed

```bash
# Re-list to get current indices
cgrab list tabs

# Or use URL/title matching instead of index-based selection
cgrab capture --url-match "the-page-url"
```
