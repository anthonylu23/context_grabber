# CLI Reference

Complete command, flag, and environment variable reference for `cgrab`.

## Binary

- **Name:** `cgrab` (alias: `context-grabber`)
- **Platform:** macOS only
- **Version:** `cgrab --version`

## Global Flags

Available on every command:

| Flag | Type | Default | Description |
|---|---|---|---|
| `--format` | string | `markdown` | Output format: `json` or `markdown` |
| `--file` | string | (none) | Write output to file path instead of default destination |
| `--clipboard` | bool | `false` | Copy output to system clipboard (via `pbcopy`) |
| `--version` | bool | — | Print version and exit |
| `--help` / `-h` | bool | — | Print help |

### Output Routing

1. If `--file` is set: write to file (no stdout)
2. If `--clipboard` is set without `--file`: copy to clipboard AND write to stdout
3. If neither `--file` nor `--clipboard`: write to stdout (except `capture`, which auto-saves — see below)
4. If both `--file` and `--clipboard` are set: write to file and clipboard (no stdout)

---

## Commands

### `cgrab list`

Enumerate open browser tabs and/or running desktop apps.

```
cgrab list [flags]
cgrab list tabs [--browser safari|chrome]
cgrab list apps
```

#### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--tabs` | bool | `false` | Include browser tabs |
| `--apps` | bool | `false` | Include running desktop apps |
| `--browser` | string | (both) | Filter tabs by browser: `safari` or `chrome` |

If neither `--tabs` nor `--apps` is set, both are included.

#### Output — Markdown

```
# Open Tabs
- safari w1:t1 (active) - Page Title - https://example.com
- safari w1:t2 - Another Page - https://example.com/page
- chrome w1:t1 (active) - Chrome Tab - https://google.com

# Running Apps
- Finder (com.apple.finder) - windows: 3
- Safari (com.apple.Safari) - windows: 2
```

Tabs sorted by: browser (alpha), window index (asc), tab index (asc). Active tab annotated with `(active)`.

#### Output — JSON (tabs)

```json
[
  {
    "browser": "safari",
    "windowIndex": 1,
    "tabIndex": 1,
    "isActive": true,
    "title": "Page Title",
    "url": "https://example.com"
  }
]
```

#### Output — JSON (apps)

```json
[
  {
    "appName": "Finder",
    "bundleIdentifier": "com.apple.finder",
    "windowCount": 3
  }
]
```

#### Output — JSON (combined)

```json
{
  "tabs": [ ... ],
  "apps": [ ... ]
}
```

#### Partial Failure

If both tabs and apps are requested and one fails, the other's results are returned with a warning to stderr.

---

### `cgrab capture`

Capture structured content from a browser tab or desktop application.

```
cgrab capture [flags]
```

No positional arguments accepted.

#### Flags

| Flag | Type | Default | Description |
|---|---|---|---|
| `--focused` | bool | `false` | Capture the currently focused browser tab |
| `--tab` | string | — | Tab by `window:tab` index (e.g., `1:2` or `w1:t2`) |
| `--url-match` | string | — | Tab by URL substring (case-insensitive) |
| `--title-match` | string | — | Tab by title substring (case-insensitive) |
| `--app` | string | — | Desktop app by exact name |
| `--name-match` | string | — | Desktop app by name or bundle ID substring (case-insensitive) |
| `--bundle-id` | string | — | Desktop app by bundle identifier |
| `--browser` | string | (auto) | Target browser: `safari` or `chrome` |
| `--method` | string | `auto` | Capture method (see below) |
| `--timeout-ms` | int | `1200` | Capture bridge timeout in milliseconds |

#### Selector Rules

1. Exactly one selector is required
2. Cannot mix browser selectors (`--focused`, `--tab`, `--url-match`, `--title-match`) with desktop selectors (`--app`, `--name-match`, `--bundle-id`)
3. Only one browser selector allowed
4. Only one desktop selector allowed

#### Capture Methods

**Browser methods:**

| Value | Description |
|---|---|
| `auto` (default) | Let the bridge decide |
| `applescript` | AppleScript-based page scraping |
| `extension` | Browser extension native messaging |

**Desktop methods:**

| Value | Description |
|---|---|
| `auto` (default) | Prefers Accessibility, falls back to OCR |
| `ax` | Force Accessibility API extraction |
| `ocr` | Force Vision OCR screen capture |
| `applescript` | Treated same as `auto` |

#### Auto-Save Behavior

When `--file` is omitted, `capture` does NOT write to stdout. Instead:
1. Saves to `~/contextgrabber/captures/capture-<timestamp>.md` (or `.json`)
2. Prints the file path to stdout: `Saved capture to <path>`

When `--file` IS set, output goes to that file only.

#### `--focused` Fallback Order

1. If `--browser` is set: try that browser only
2. If `CONTEXT_GRABBER_BROWSER_TARGET` is set: try that browser only
3. Otherwise: try Safari first, then Chrome

#### Browser Capture Prerequisites

The CLI auto-launches `ContextGrabber.app` before browser capture if the host app is not running (4-second timeout). Browser capture also requires Bun and the repo root (or `CONTEXT_GRABBER_REPO_ROOT`).

#### Desktop Capture Prerequisites

Only requires the `ContextGrabberHost` binary. No Bun, extensions, or repo root needed.

---

### `cgrab doctor`

Run system health checks.

```
cgrab doctor
```

Exits non-zero if overall status is not `ready`.

#### Checks

1. Repository root resolution (auto-detected or `CONTEXT_GRABBER_REPO_ROOT`)
2. osascript availability (`/usr/bin/osascript`)
3. Bun runtime availability
4. ContextGrabberHost binary (searched in order: env var → repo build dir → installed app)
5. Safari and Chrome bridge ping (protocol version `1`)

#### Output — Markdown

```
# Context Grabber Doctor
- overall_status: ready
- repo_root: /path/to/repo
- osascript_available: true
- bun_available: true
- host_binary_available: true
- host_binary_path: /path/to/ContextGrabberHost

## Bridge Status
- safari: ready (protocol=1)
- chrome: unreachable (bun not available)

## Warnings
- bun not found; browser capture commands will be unavailable
```

#### Output — JSON

```json
{
  "overallStatus": "ready",
  "repoRoot": "/path/to/repo",
  "osascriptAvailable": true,
  "bunAvailable": true,
  "hostBinaryAvailable": true,
  "hostBinaryPath": "/path/to/ContextGrabberHost",
  "bridges": [
    { "target": "safari", "status": "ready", "detail": "protocol=1" },
    { "target": "chrome", "status": "unreachable", "detail": "bun not available" }
  ],
  "warnings": []
}
```

---

### `cgrab config`

Manage CLI configuration.

#### `cgrab config show`

Print current configuration.

```
Context Grabber CLI Config
-------------------------
base_dir: /Users/<user>/contextgrabber
config_file: /Users/<user>/contextgrabber/config.json
capture_output_subdir: captures
capture_output_dir: /Users/<user>/contextgrabber/captures
```

#### `cgrab config set-output-dir <subdir>`

Set the capture output subdirectory. Alias: `set-path`.

Constraints:
- Must be non-empty
- Must be a relative path (not absolute)
- Cannot escape base directory (no `..` prefix)

#### `cgrab config reset-output-dir`

Reset capture output subdirectory to default (`captures`).

#### Config File

Stored at `~/contextgrabber/config.json` (or `$CONTEXT_GRABBER_CLI_HOME/config.json`).

```json
{
  "captureOutputSubdir": "captures"
}
```

---

### `cgrab docs`

Open the GitHub repository in the system browser.

```
cgrab docs
```

Falls back to printing the URL if `open` fails.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CONTEXT_GRABBER_CLI_HOME` | `~/contextgrabber` | Override base storage directory. Must be absolute. |
| `CONTEXT_GRABBER_BROWSER_TARGET` | (none) | Default browser for `--focused`: `safari` or `chrome` |
| `CONTEXT_GRABBER_REPO_ROOT` | auto-detected | Repository root path. Required for browser capture outside repo tree. |
| `CONTEXT_GRABBER_OSASCRIPT_BIN` | `/usr/bin/osascript` | Override osascript binary path |
| `CONTEXT_GRABBER_BUN_BIN` | `bun` (from PATH) | Override Bun runtime path |
| `CONTEXT_GRABBER_HOST_BIN` | auto-detected | Override ContextGrabberHost binary path. Search order: env → `<repo>/apps/macos-host/.build/debug/ContextGrabberHost` → `/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost` |
| `CONTEXT_GRABBER_APP_BUNDLE_PATH` | `/Applications/ContextGrabber.app` | Override `.app` bundle path for auto-launch |

---

## Common Errors

| Error | Cause | Fix |
|---|---|---|
| `capture requires one target selector` | No selector flag provided | Add `--focused`, `--tab`, `--app`, etc. |
| `capture selectors must be either browser-targeted or app-targeted, not both` | Mixed browser + desktop selectors | Use only one category |
| `browser capture accepts only one selector` | Multiple browser selectors | Pick one of `--focused`, `--tab`, `--url-match`, `--title-match` |
| `desktop capture accepts only one selector` | Multiple desktop selectors | Pick one of `--app`, `--name-match`, `--bundle-id` |
| `unsupported --format value` | Invalid format | Use `json` or `markdown` |
| `unsupported browser` | Invalid browser value | Use `safari` or `chrome` |
| `invalid --tab value` | Bad tab reference format | Use `w1:t2` or `1:2` |
| `no tab found for --tab` | Tab index doesn't exist | Verify with `cgrab list tabs` |
| `no tab matched --url-match` | No URL contains substring | Check URLs with `cgrab list tabs` |
| `no running app matched --name-match` | No app name/bundle ID contains substring | Check with `cgrab list apps` |
| `bun not found; browser capture is unavailable` | Bun not installed | Install Bun or set `CONTEXT_GRABBER_BUN_BIN` |
| `ContextGrabberHost binary not found` | Host not built/installed | Install ContextGrabber.app or set `CONTEXT_GRABBER_HOST_BIN` |
| `doctor status is unreachable` | System not ready | Run `cgrab doctor --format json` for details |
