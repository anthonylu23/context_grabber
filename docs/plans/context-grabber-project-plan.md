# Context-Grabber Project Plan (macOS Menu Bar, Local-First, Web-First)

## Goal
Build a native macOS menu bar app (Swift/SwiftUI + AppKit) that captures the user's current context and outputs structured markdown for LLM workflows.

## Product Constraints
1. Local-only processing and storage in capture pipeline.
2. Manual trigger only (global hotkey + menu action).
3. Web-first quality bar for Chrome and Safari focused tabs.
4. Desktop fallback via Accessibility first, OCR second.
5. Markdown output must be deterministic and paste-ready.

## Stack Decisions
1. Native app: Swift 5.10+, SwiftUI + AppKit, built in Xcode.
2. Browser code: TypeScript only (no plain JavaScript files for app logic).
3. JavaScript runtime/tooling: Bun (`bun install`, `bun run`) for extension builds, tests, and local scripts.
4. Extension targets: Safari Web Extension + Chrome Manifest V3.
5. Shared contracts: one TypeScript shared types package/folder consumed by both extensions and validated against native host JSON contracts.

## In Scope
1. Menu bar app with status menu and capture action.
2. Global hotkey trigger.
3. Safari and Chrome extension capture via native messaging.
4. Desktop capture path (AX extraction + OCR fallback).
5. Markdown normalization and chunking pipeline.
6. Clipboard copy and local history files.
7. Diagnostics for permissions, extension connectivity, and failures.

## Out of Scope (for now)
1. Automatic capture on app or tab change.
2. Cloud summarization or remote processing.
3. Arc/Firefox support.
4. Destination-specific output templates.
5. Auto-paste or auto-typing into target applications.

## Architecture
1. `ContextGrabberApp` (native host)
- Menu bar UI, global hotkey, permission orchestration, capture pipeline orchestration.
- Native messaging endpoints for browser extensions.

2. Browser Capture Layer
- Safari Web Extension + Chrome Extension.
- Content scripts extract readable page text + metadata.
- Native messaging sends payload to macOS app.

3. Desktop Capture Layer
- Accessibility extractor reads focused element/window text when available.
- OCR fallback runs Vision on focused window screenshot.

4. Normalization + Markdown Engine
- Boilerplate cleanup, deduplication, chunking, key-point extraction.
- Deterministic markdown schema generation.

5. Storage + Clipboard
- Timestamped markdown history in local app directory.
- Clipboard copy of final markdown content.

6. Diagnostics
- Permission checks and actionable remediation hints.
- Extension link health and capture path/fidelity reporting.

## Concrete Data Contracts
1. Capture trigger

```ts
type CaptureMode = "manual_hotkey" | "manual_menu";

interface CaptureRequest {
  requestId: string;
  timestamp: string; // ISO-8601
  mode: CaptureMode;
}
```

2. Browser payload

```ts
interface BrowserContextPayload {
  source: "browser";
  browser: "chrome" | "safari";
  url: string;
  title: string;
  metaDescription?: string;
  siteName?: string;
  language?: string;
  author?: string;
  publishedTime?: string;
  selectionText?: string;
  fullText: string;
  headings: Array<{ level: number; text: string }>;
  links: Array<{ text: string; href: string }>;
  extractionWarnings?: string[];
}
```

3. Desktop payload

```ts
interface DesktopContextPayload {
  source: "desktop";
  appBundleId: string;
  appName: string;
  windowTitle?: string;
  accessibilityText?: string;
  ocrText?: string;
  usedOcr: boolean;
  ocrConfidence?: number; // 0-1
  extractionWarnings?: string[];
}
```

4. Normalized capture

```ts
type ExtractionMethod = "browser_extension" | "accessibility" | "ocr" | "metadata_only";

interface NormalizedContext {
  id: string;
  capturedAt: string;
  sourceType: "webpage" | "desktop_app";
  title: string;
  origin: string; // URL or app/window identifier
  appOrSite: string;
  extractionMethod: ExtractionMethod;
  confidence: number; // 0-1
  truncated: boolean;
  tokenEstimate: number;
  metadata: Record<string, string>;
  captureWarnings: string[];
  summary: string;
  keyPoints: string[];
  chunks: Array<{ chunkId: string; tokenEstimate: number; text: string }>;
  rawExcerpt: string;
}
```

## Markdown Output Schema
1. YAML frontmatter fields:
- `id`
- `captured_at`
- `source_type`
- `origin`
- `title`
- `app_or_site`
- `extraction_method`
- `confidence`
- `truncated`
- `token_estimate`
- `warnings`

2. Body sections (always emitted, even if empty):
- `## Summary`
- `## Key Points`
- `## Content Chunks`
- `## Raw Excerpt`
- `## Links & Metadata`

## Capture Decision Tree
1. Trigger received.
2. Read focused app bundle id.
3. If focused app is Safari or Chrome:
- Request active tab capture from extension (timeout: 1200ms).
- If payload received with non-empty `fullText`: continue as browser capture.
- If extension timeout/error: create `metadata_only` capture using browser title + URL when available, with warning.
4. If not browser capture (or browser capture has insufficient text under threshold):
- Attempt Accessibility extraction from focused UI element/window.
- If extracted text length >= `MIN_TEXT_LEN` (default `240` chars): use AX path.
- Else run OCR on focused window image and use OCR path.
5. Normalize, chunk, summarize, generate markdown.
6. Persist file, copy clipboard, notify user with capture method + warnings.

## Local Summarization and Chunking Rules
1. No cloud calls in summarization.
2. Summary strategy:
- Extractive, heuristic-based only.
- Sentence tokenize normalized text.
- Score sentences by heading proximity, term frequency, and novelty.
- Choose top sentences up to max 6 lines.

3. Key points strategy:
- Pick 5 to 8 bullets from highest-scoring distinct sentences.
- Deduplicate by token overlap threshold.

4. Chunking strategy:
- Target chunk size: 1200 to 1800 estimated tokens.
- Hard cap: 2000 estimated tokens.
- Split at heading or paragraph boundaries when possible.
- Deterministic chunk IDs: `chunk-001`, `chunk-002`, etc.

5. Truncation strategy:
- If total text exceeds max raw size (default `200k` chars), truncate tail.
- Set `truncated: true` and append warning.

## Performance and Reliability Targets
1. Test hardware baseline: Apple Silicon laptop, local build.
2. Browser capture latency:
- Median <= 2.5s
- p95 <= 5.0s

3. Desktop capture latency:
- Median <= 3.5s
- p95 <= 6.0s

4. Stability target:
- 300 consecutive captures without crash.
- Failed captures must emit explicit reason and no hangs.

5. Output integrity target:
- Clipboard content must byte-match saved markdown file.

## Security and Privacy
1. Required macOS permissions:
- Accessibility
- Screen Recording (for OCR fallback)

2. Required browser permissions:
- Active tab access
- Scripting/content extraction
- Native messaging

3. Privacy guarantees:
- No outbound network calls in capture path.
- Data written only to local app directory.

4. Retention:
- Configurable max file count and max file age.
- Optional one-click history purge.

## Failure Handling
1. Missing permissions:
- Block affected path and present direct remediation steps.

2. Browser extension unavailable:
- Fallback to metadata-only capture with warning.

3. OCR low confidence:
- Emit warning when confidence < `0.55`.

4. Clipboard failure:
- Capture is marked failed, but the already-written markdown file remains in history.

5. Oversized or malformed content:
- Continue with truncation and warnings instead of failing capture.

## Implementation Roadmap
1. Milestone A: Skeleton + Packaging Viability
- Deliverables:
  - Menu bar app shell with manual capture action.
  - Global hotkey registration.
  - Draft entitlements/signing settings validated on local machine.
  - Markdown file write + clipboard copy.
- Exit criteria:
  - Manual trigger creates deterministic markdown file and clipboard output.
  - Signing and extension-host communication approach confirmed.

2. Milestone B: Safari End-to-End Capture
- Deliverables:
  - Safari extension + native messaging handshake.
  - Full text + metadata capture for active tab.
  - Browser timeout and metadata-only fallback behavior.
- Exit criteria:
  - Works across at least 10 varied Safari pages (article, docs, SPA, auth page).

3. Milestone C: Chrome Parity
- Deliverables:
  - Chrome extension and native messaging integration.
  - Payload parity with Safari.
  - Same fallback behavior and diagnostics surface.
- Exit criteria:
  - Chrome passes same capture scenario suite as Safari.

4. Milestone D: Desktop Capture (AX then OCR)
- Deliverables:
  - Focused-app detection and AX text extraction.
  - OCR fallback with confidence scoring.
  - Extraction method and warnings surfaced in output.
- Exit criteria:
  - AX success on text-centric apps.
  - OCR fallback works on low-AX apps without hangs.

5. Milestone E: Normalization Hardening
- Deliverables:
  - Deterministic summarization + chunking heuristics.
  - Large-content truncation and warning paths.
  - Diagnostics panel for permission and capture path health.
- Exit criteria:
  - Deterministic outputs on repeated runs for same input.
  - Performance and reliability targets reached.

6. Milestone F: Quality of Life + Menu Bar UI Enhancements
- Deliverables:
  - Recent captures list in menu.
  - Configurable retention settings.
  - Improved notifications and failure visibility.
  - Menu bar UI enhancements (see below).
- Exit criteria:
  - Daily personal-use loop is smooth with no blocking manual fixes.
  - Menu bar provides at-a-glance capture status and quick access to recent output.

### Menu Bar UI Enhancements (Milestone F)

#### Quick Wins
- **Menu bar icon status indicator**: brief checkmark/flash after successful capture; dot badge when extension is disconnected.
- **Separator lines**: `NSMenuItem.separator()` between action groups (capture, history, diagnostics, quit) for visual hierarchy.
- **Last capture timestamp**: disabled menu item near the top showing "Last capture: 2m ago" for quick status.

#### Functional Additions
- **Recent captures submenu**: instead of only "Open Recent Captures" (opens Finder), show last 3–5 captures inline as a submenu with title + timestamp, clickable to open the markdown file directly.
- **Transient capture feedback**: replace static "Opened history folder" text with dynamic status reflecting the last action (e.g. "Captured: developer.apple.com — copied to clipboard").
- **Preferences item**: capture output directory, hotkey customization, auto-capture toggle.
- **Pause/Resume toggle**: for future auto-capture, a menu item to pause/resume.
- **"Copy Last Capture" shortcut**: quick re-copy of the most recent capture without re-capturing.

#### Polish
- **Dynamic hotkey display**: if the user rebinds the global hotkey, reflect the current binding in the menu item text.
- **Inline diagnostics submenu**: show connection status per-browser inline (e.g. "Safari extension: connected", "Chrome: not installed") rather than requiring a separate diagnostics action.

#### Design Guardrails
- No full settings window unless strictly necessary — menu bar apps should stay lightweight.
- No notification banners for every capture — icon flash is sufficient feedback.
- Keep menu item count low; use submenus for detail rather than top-level clutter.

## Test Matrix
1. Browser full-page capture:
- Long article, docs site, SPA route changes, authenticated pages, heavy-nav marketing pages.

2. Metadata completeness:
- Missing optional fields must not break output shape.

3. Desktop capture:
- Editor (AX success), terminal, design app (AX weak -> OCR fallback).

4. Permission states:
- Fresh install, partial permissions, revoked permissions mid-session.

5. Large content:
- 100k+ character deterministic chunking and stable warning behavior.

6. Reliability:
- Repeated hotkey stress run with no deadlock/crash.

7. Determinism:
- Same input payload yields byte-identical markdown output.

## Done Criteria
1. Manual capture works reliably from menu and hotkey.
2. Safari and Chrome produce full-text captures when extension path is healthy.
3. Desktop capture reliably falls back from AX to OCR as needed.
4. Markdown schema is stable and includes provenance/fidelity fields.
5. Each capture is saved locally and copied to clipboard.
6. Capture path remains local-only and network-independent.

## Scaffold Status (2026-02-14)
1. Initial Bun + TypeScript monorepo workspace is in place.
2. Strict base TypeScript configuration is defined in `tsconfig.base.json`.
3. Shared capture contracts are implemented in `packages/shared-types`.
4. Chrome and Safari extension packages are scaffolded with placeholder TS entrypoints.
5. Native-host bridge package is scaffolded with message-envelope parsing utilities.
6. Repo-level tooling baseline is added:
- Biome lint/format configuration.
- Workspace check script (`scripts/check-workspace.ts`).
- Git pre-commit hook that runs `bun run check`.
7. Runtime message validation now checks supported message types and payload shapes (`browser.capture`, `desktop.capture`).
8. Typecheck now includes package test files via per-package `tsconfig.typecheck.json`.
9. Shared-types export strategy is Bun-first for workspace dev while preserving `dist` default runtime output.
10. Protocol-level contracts now include:
- protocol version pinning (`"1"`)
- host request / extension response / extension error message envelopes
- canonical bridge error codes (`ERR_PROTOCOL_VERSION`, `ERR_PAYLOAD_INVALID`, `ERR_TIMEOUT`, `ERR_EXTENSION_UNAVAILABLE`, `ERR_PAYLOAD_TOO_LARGE`)
- envelope and browser payload size validators
11. Native host bridge now includes:
- timeout-wrapped extension request flow (`1200ms` default)
- metadata-only fallback generation on timeout/transport/validation failure
- deterministic normalization + markdown rendering utilities
12. Safari/Chrome extension packages now emit protocol-versioned extension response envelopes.
13. macOS host scaffold is now present under `apps/macos-host`:
- SwiftUI/AppKit menu bar shell
- transport-backed capture path via Safari native-messaging bridge CLI
- deterministic markdown write to local history
- clipboard copy and local diagnostics/logging
14. macOS host capture now fails explicitly when markdown persistence or clipboard write fails.
15. macOS host frontmatter rendering now escapes YAML-quoted values for safer output.
16. Safari extension runtime now includes:
- host request transport handler with protocol/version/size guard enforcement
- bridge CLI entrypoint (`native-messaging`) for host request-response flow
- transport fixture source (`fixtures/active-tab.json`) and tests for protocol/error paths
17. Diagnostics now check Safari transport reachability and protocol compatibility against pinned version `1`.
18. Safari native-messaging CLI now reads stdin via Bun stream API and has integration test coverage for host request stdin->response flow.
19. Host transport now attempts to decode structured bridge JSON responses before treating non-zero exits as hard transport failures.
20. Safari transport now uses live active-tab extraction by default (AppleScript + in-page JS) with fixture mode only for explicit override/testing.
21. Host now supports global hotkey capture parity (`manual_hotkey`) using the same pipeline as menu-triggered capture.
22. Diagnostics now surface last capture timestamp, last transport error code, and last transport latency.
23. Safari Web Extension runtime scaffolding now includes:
- `runtime/content` extraction helpers for document-based capture
- `runtime/background` request handler integrating host request semantics
- runtime native-host port binder (`runtime/native-host`) for packaged extension request/response wiring
24. Safari bridge CLI source resolution is strict: `auto`/`live` require live extraction, and `fixture` is explicit test/dev mode.
25. Chrome transport parity scaffolding now includes:
- Chrome transport handler with protocol/error/size validation parity
- Chrome native-messaging CLI with runtime/fixture source modes (`auto`/`runtime` require runtime payload input)
- Chrome fixture and CLI/transport test coverage
26. Native host bridge tests now include:
- explicit unavailable transport fallback assertions
- invalid extension payload fallback assertions
- oversized normalization truncation determinism assertions
27. Host runtime now selects Safari vs Chrome transport channel from focused browser context (with optional `CONTEXT_GRABBER_BROWSER_TARGET` override) and diagnostics report both channels.
28. Host-level Swift integration tests now cover:
- long content truncation warning behavior
- metadata-only fallback payload + markdown behavior
- byte-identical markdown determinism checks
- browser target selection helpers
29. Safari packaged runtime wiring now includes concrete entrypoint helpers:
- `runtime/background-entrypoint` for native-host port bridge + active-tab content messaging
- `runtime/content-entrypoint` for content-side capture request handling
- shared runtime message contract constants/guards in `runtime/messages`
30. Safari packaged runtime now also includes:
- runtime bootstrap files (`runtime/background-main`, `runtime/content-main`)
- packaged WebExtension manifest (`packages/extension-safari/manifest.json`) targeting compiled runtime assets
31. Chrome live extraction path is now scaffolded via AppleScript active-tab capture (`extract-active-tab`) and wired into CLI source modes (`live`, `runtime`, `fixture`, `auto` with `runtime -> live` fallback; fixture is explicit).
32. Host unsupported-app capture now routes through a real desktop app resolver:
- falls back to Accessibility focused-element extraction (`minimumAccessibilityTextChars = 240`)
- falls back to Vision OCR window/screen text extraction
- falls back to deterministic desktop `metadata_only` when AX and OCR both fail
- emits desktop provenance (`source_type: desktop_app`) and desktop metadata in markdown
33. Host diagnostics now include desktop readiness checks:
- Accessibility permission state
- Screen Recording permission state
34. Host-level Swift integration tests now include:
- resolver-level timeout/unavailable browser mapping assertions
- desktop AX success / OCR fallback / metadata-only failure assertions
35. Desktop OCR image capture now uses ScreenCaptureKit (`SCScreenshotManager`) with window-first targeting and display fallback; host menu now includes direct permission remediation actions for Accessibility and Screen Recording settings panes.
36. Milestone F quick-win menu UX improvements are now partially implemented in host UI:
- relative last-capture label shown at top of the menu
- grouped menu sections with clearer separators
- recent captures submenu (direct file-open actions)
- copy-last-capture action
- menu-bar icon indicator states for success/failure/disconnected extension diagnostics
37. Host codebase refactor pass completed for core separation of concerns:
- extracted desktop capture pipeline into `DesktopCapturePipeline.swift`
- extracted menu indicator/label helpers into `MenuBarPresentation.swift`
- extracted markdown rendering helpers into `MarkdownRendering.swift`
38. Documentation has been reorganized into a multi-file handbook under `docs/codebase/`:
- architecture deep-dive pages
- component-level docs
- operations (permissions/diagnostics/testing)
- usage and reference sections
39. Milestone F functional additions are now implemented in host menu workflow:
- preferences-backed output directory selection
- retention settings (max file count + max file age) with post-capture pruning
- pause/resume capture placeholder toggle
- diagnostics status submenu with inline Safari/Chrome/Desktop readiness labels
40. Safari container integration milestone is now implemented:
- concrete converter-generated macOS Safari container project at `apps/safari-container`
- container resources wired to packaged runtime artifacts (`manifest.json` + `dist/**`)
- reproducible regeneration flow via `scripts/sync-safari-container.sh`
- unsigned compile validation command via `scripts/build-safari-container.sh`
41. Safari local-install UX hardening is now implemented:
- Safari manifest icons now provided by in-repo placeholder assets (`packages/extension-safari/assets/icons`)
- sync flow now validates and stages `icons/**` into converter input bundle
- step-by-step signed first-run install flow documented for Xcode + Safari enablement
- troubleshooting now includes bundle-id prefix and signing/profile remediation notes
42. Desktop extraction fidelity hardening is now implemented:
- AX extraction now traverses focused element/window trees with bounded child/parent/title-linked walks
- app-aware AX extraction profiles now tune thresholds and attribute sets for dense editor and terminal-like apps
- desktop warning strings now include observed-vs-threshold character counts for clearer OCR fallback diagnostics
- host tests now cover tuned threshold behavior for profiled vs untuned apps
43. Host decomposition refactor is now implemented for browser and diagnostics concerns:
- browser capture resolution + metadata fallback mapping moved to `BrowserCapturePipeline.swift`
- diagnostics status/summary formatting moved to `DiagnosticsPresentation.swift`
- `ContextGrabberHostApp.swift` now keeps scene/model orchestration with slimmer transport/diagnostics glue
- host tests now include diagnostics presentation helper coverage (protocol match/mismatch/unreachable + summary shape)
44. Browser-extension-first source resolution is now implemented for both Safari and Chrome bridge CLIs:
- source modes are now aligned across Safari/Chrome (`runtime`, `live`, `fixture`, `auto`)
- `auto` now resolves `runtime -> live` for both browsers, with fixture remaining explicit-only
- Safari CLI now supports runtime payload env input (`CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD`, `CONTEXT_GRABBER_SAFARI_RUNTIME_PAYLOAD_PATH`)
- package tests now cover runtime-first auto behavior, live fallback behavior, and runtime strict-mode failure behavior
45. Milestone F2 host UI/state polish is now in progress with core plumbing implemented:
- menu indicator states now include explicit capture lifecycle (`idle`, `capturing`, `success`, `error`, `disconnected`)
- successful/failed captures now render a transient inline feedback panel in the menu (auto-dismiss)
- output-directory selection now validates writability before persisting settings
- host tests now cover feedback formatting helpers, updated indicator mapping, and output-directory validation
46. Milestone F2 core polish pass is now completed:
- host menu now includes About metadata (`version/build`) and handbook shortcut action
- menu copy was tightened for diagnostics/settings/readiness labels
- host tests now include app-version label formatting coverage
- documentation updated for host About/readiness behavior
47. Milestone G companion CLI scaffold is now implemented:
- new package `packages/companion-cli` with commands `doctor` and `capture --focused`
- `doctor` pings Safari/Chrome native-messaging bridges and reports readiness
- `capture --focused` uses shared request/validation/markdown pipeline from `@context-grabber/native-host-bridge`
- auto target order defaults to Safari then Chrome, with `CONTEXT_GRABBER_BROWSER_TARGET` override
- companion CLI tests cover command parsing, doctor status behavior, and capture fallback behavior
48. Milestone G browser compatibility expansion now includes inventory commands:
- `list tabs` implemented with Safari + Chrome AppleScript enumeration (optional `--browser` filter)
- `list apps` implemented with System Events process/window enumeration
- both commands return JSON for agent-friendly consumption and include partial-failure warning behavior
- companion CLI tests now cover list command parsing and inventory success/failure scenarios
49. Desktop capture fallback robustness is now improved for blank-result cases:
- OCR path now retries once before metadata-only fallback when AX text is unavailable
- metadata-only desktop captures now include a non-empty diagnostic excerpt in markdown content
- host tests now cover OCR retry recovery and non-empty metadata-only fallback text
50. Desktop permission guidance is now more proactive during fallback capture paths:
- global AX minimum threshold lowered to `240` chars to reduce unnecessary OCR fallback
- desktop permission popup now appears for both `metadata_only` and `ocr` extraction methods
- docs updated to reflect new threshold and popup behavior
51. Desktop permissions popup copy is now fallback-aware:
- popup message now reports the actual capture fallback mode (`metadata_only` or `ocr`)
- host tests now cover popup fallback-description mapping for OCR/metadata/default branches
52. Output format controls are now implemented for paste-efficiency tuning:
- host settings now persist output preset (`brief` / `full`) and product-context-line toggle
- menu settings now expose preset and context-line controls
- markdown renderer now supports compact `brief` output (no chunks/raw excerpt) and richer `full` output
- host tests now cover settings persistence defaults and brief/full rendering behavior
53. Hybrid summarization system is now implemented in host capture output:
- summarization mode now supports `heuristic` (default) and optional `llm`
- LLM provider architecture supports `openai`, `anthropic`, `gemini`, and `ollama`
- menu settings now expose `Summarizing` controls (mode, provider, model, summary budget)
- LLM failures now deterministically fall back to heuristic summarization with explicit warning annotation
- host tests now cover summarization settings persistence and llm success/fallback behavior
54. Advanced settings UX split is now implemented:
- menu `Settings` now keeps core controls and adds `Advanced Settings...` window entrypoint
- retention and summarization controls moved to Advanced Settings window only
- advanced window includes all previous setup controls plus advanced controls
- output directory selection in menu now uses checkmark-selected `Default` vs `Custom` options (no output text line)
55. Capture summary popup rollout is now implemented:
- new non-activating floating `NSPanel` shows per-capture summary context
- popup includes quick actions (`Copy to Clipboard`, `Open File`, `Dismiss`)
- popup auto-dismisses after ~4s and mirrors the inline menu feedback state
- host capture flow no longer uses `UNMutableNotificationContent` banners for completion/failure

7. Milestone F2: UI Polish & Capture Feedback Panel

### Progress Update (2026-02-15)
- Implemented:
  - inline capture feedback panel (success/failure) with auto-dismiss behavior
  - floating capture summary popup with quick actions (copy/open/dismiss)
  - capture lifecycle indicator states with stale-reset guard for timed indicator resets
  - output directory writability validation in settings flow
  - settings/about menu copy polish and handbook shortcut action
- Deferred from F2:
  - optional interaction polish items (animation/haptics/sound)

### Capture Summary Popup
After each capture, show a transient floating panel (SwiftUI `.popover` or lightweight `NSPanel`) with:
- **Title** of captured content (truncated)
- **Source app/site** (e.g. "Safari — developer.apple.com")
- **Extraction method** badge (extension / applescript / ax / ocr / metadata-only)
- **Token estimate** (from NormalizedContext)
- **Truncation warning** if applicable
- **Quick actions**: "Copy to Clipboard" / "Open File" / "Dismiss"
- Auto-dismiss after ~4 seconds, or click to dismiss immediately
- Replaces the current `UNMutableNotificationContent` approach (which doesn't work in `swift run` anyway)

### App Icon
- Custom menu bar icon (not just SF Symbols) — a small monochrome glyph that fits the macOS menu bar style (template image)
- Keep SF Symbol state overlays for success/failure/disconnected, but as modifications to the custom base icon
- Include a proper app icon for the dock/About/Finder (1024x1024 asset catalog)

### Settings Panel
Lightweight settings popover or small window accessible from the menu:
- **Output directory** picker (currently hardcoded to local app directory)
- **Retention settings**: max file count, max file age, one-click purge (already spec'd in project plan but no UI)
- **Global hotkey** rebinding
- **Capture defaults**: preferred method override, include selection text toggle
- **Appearance**: dark/light/system (if the popup has its own chrome)
- Keep it a single-pane popover — no tab bar, no multi-page settings

### Menu Visual Refinements
- **Capture status section**: replace plain text status line with a styled mini-card (icon + colored text for last capture result)
- **Recent captures**: add favicons or SF Symbol type indicators (webpage vs desktop app) next to each entry
- **Keyboard shortcut hints**: show shortcut badges on more menu items (Copy Last, Open History)
- **"About" item**: app version, build info, link to project repo

### Interaction Polish
- **Menu bar icon animation**: brief pulse/spin during active capture (not just state change after)
- **Haptic feedback** on capture completion (if trackpad is available, via `NSHapticFeedbackManager`)
- **Sound**: optional subtle capture sound (like Screenshot.app), off by default

### Design Guardrails
- The popup must not steal focus or interrupt workflow — behave like a macOS notification, not a modal
- Settings should persist via `UserDefaults` or a simple plist — no database
- Keep total menu item count low; use submenus for detail
- All icons should be template images that adapt to light/dark mode automatically

### Key Files
- `apps/macos-host/Sources/ContextGrabberHost/ContextGrabberHostApp.swift` — popup view, settings surface, about item, animation during capture
- `apps/macos-host/Sources/ContextGrabberHost/MenuBarPresentation.swift` — extend indicator states for animation, capture summary formatting helpers
- New: `CaptureResultPopup.swift` — transient capture summary panel
- New: `SettingsView.swift` — settings popover
- New: asset catalog for custom menu bar icon and app icon

- Exit criteria:
  - Capture triggers popup with correct token count, title, source app.
  - Popup auto-dismisses and doesn't steal focus.
  - Settings changes persist across app restart.
  - Menu bar icon shows custom glyph with state overlays.
  - `swift build` compiles cleanly and existing tests pass.

8. Milestone G: Companion CLI + Agent Integration
- Deliverables:
  - Standalone CLI that reuses the existing capture pipeline (bridge, normalization, markdown engine).
  - Tab and app enumeration commands.
  - Targeted capture by tab/app selection or pattern match.
  - Capture method override (auto, applescript, extension, ax, ocr).
  - Agent skill manifests (MCP tool definitions / Claude Code skill) bundled with the CLI.
  - Diagnostics command for permission and extension health.
- Proposed CLI surface:
  - `context-grabber list tabs` — enumerate open browser tabs (Safari + Chrome).
  - `context-grabber list apps` — enumerate running desktop apps with windows.
  - `context-grabber capture --focused` — grab current foreground context (same as menu bar capture).
  - `context-grabber capture --tab <id|--url-match|--title-match>` — capture a specific browser tab.
  - `context-grabber capture --app <id|--name-match>` — capture a specific desktop app.
  - `context-grabber capture ... --method auto|applescript|extension|ocr|ax` — override capture method.
  - `context-grabber doctor` — permission status, extension connectivity, transport health.
  - Output: markdown to stdout by default (pipe-friendly); `--file` and `--clipboard` flags for current behavior.
- Design constraints:
  - Single capture engine shared with the menu bar host — CLI is a trigger surface, not a reimplementation.
  - Tab/app IDs are ephemeral; prefer `--url-match` / `--title-match` / `--name-match` filters over numeric IDs for agent reliability.
  - Agent skill definitions should allow discovery and invocation by Claude Code, Cursor, and similar tools.
- Suggested timing: after Milestone B (Safari end-to-end) is stable.
- Stack recommendation: **Go** (primary) with osascript/shell-out for macOS framework access.
  - Rationale: single static binary, excellent CLI ecosystem (cobra), fast compile times for iteration, straightforward MCP server implementation (JSON-RPC over stdio), goroutines map well to concurrent enumeration + health checks.
  - macOS integration approach: shell out to `osascript` for tab/app enumeration and AppleScript-based capture; invoke existing Swift host or Bun bridge binaries for extension-based and AX/OCR capture paths. Avoids CGo complexity.
  - Alternatives considered:
    - **Rust**: better direct macOS framework access via `objc2`, but steeper learning curve and longer time-to-working-CLI.
    - **Zig**: macOS framework interop is immature; no CLI or MCP ecosystem. Better suited to lower-level projects.
    - **Bun/TS**: fastest to ship (pipeline already exists in TS, `bun build --compile` for single binary), but no new language learning. Viable fallback if Go introduces too much friction.
- Exit criteria:
  - `list` + `capture --focused` + `capture --tab` + `capture --app` work end-to-end.
  - At least one agent skill manifest (MCP or Claude Code) is functional and discoverable.
  - CLI reuses the same pipeline code as the host app with no duplicated capture logic.

## Next Steps (Implementation Queue)
1. Milestone G capture commands — add `capture --focused`, `capture --tab`, and `capture --app` wiring in Go (Bun + `ContextGrabberHost --capture` subprocesses).
2. Milestone G agent integration — add MCP tool server (`serve`) and skill manifests/docs for discoverable invocation.
3. Summarization follow-up — add provider diagnostics surfacing and model validation hints in host UI.
4. Transport hardening follow-up — add Swift integration tests for native-messaging timeout and large-payload streaming behavior.

## Progress Notes (Milestone G CLI Rebuild)
56. The Bun/TS companion CLI (`packages/companion-cli`) has been removed in favor of a Go + Swift hybrid architecture:
  - Go binary handles CLI framework (cobra), MCP server (mcp-go), osascript enumeration, and subprocess orchestration
  - Bun/TS pipeline retained for browser extension capture (spawned as subprocess, optional dependency)
  - Full implementation plan at `docs/plans/cli-expansion-plan.md`
57. Architecture decision: single-binary CLI mode instead of separate Swift CLI target:
  - `ContextGrabberHost` binary gains headless CLI mode (triggered by `--capture` flags)
  - CLI mode skips SwiftUI, runs capture pipeline, outputs to stdout, exits
  - Key rationale: macOS grants Accessibility/Screen Recording permissions per-binary path — single binary means the CLI inherits the GUI app's existing permission grants with zero extra user setup
  - The Go CLI spawns `ContextGrabberHost --capture ...` as a subprocess for desktop capture
58. Phase 1 revised scope: Swift library extraction (`ContextGrabberCore`) + CLI mode in existing binary:
  - Extract 7 files wholesale + ~700 lines from monolith into `ContextGrabberCore` library target
  - Add `CLIEntryPoint.swift` for headless capture mode
  - Types to extract from monolith: transport classes (Safari/Chrome, ~490 lines), protocol types (~100 lines), browser detection (~50 lines), core types (~60 lines)
  - Unify duplicated `ProcessExecutionResult`, promote `GenericEnvelope`
  - No separate `ContextGrabberDesktopCLI` executable — single binary serves both GUI and CLI
59. Native messaging bridge `auto` source behavior now prefers live extraction first (Safari/Chrome), with runtime fallback only when runtime payload env vars are explicitly configured. This avoids runtime-env error noise for normal live-capture workflows.
60. Milestone G Phase 1 (Swift extraction + dual-mode binary) is now implemented:
  - `ContextGrabberCore` library target is wired and consumed by host UI + tests
  - `ContextGrabberHost` now supports headless CLI mode via `--capture` without launching SwiftUI
  - `ContextGrabberHost --capture` supports `--app` / `--bundle-id`, `--method auto|ax|ocr`, and `--format markdown|json`
  - Validation passed: `swift build`, `swift test`, `swift run ContextGrabberHost --capture --help`
61. Milestone G Phase 2 CLI scaffold is now implemented (list + doctor slice):
  - new Go module `cli/` with cobra command tree (`list`, `doctor`)
  - `list tabs` and `list apps` now enumerate via osascript using ASCII RS/US delimiters and JSON/markdown output modes
  - `doctor` now reports osascript/bun/host-binary capabilities and Safari/Chrome bridge ping readiness
  - Go coverage added for osascript parsing/partial-failure behavior and doctor capability resolution (`go test ./...`)
