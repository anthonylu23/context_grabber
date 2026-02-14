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
- If extracted text length >= `MIN_TEXT_LEN` (default `400` chars): use AX path.
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
- File write still succeeds, user gets saved file path.

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

6. Milestone F: Quality of Life
- Deliverables:
  - Recent captures list in menu.
  - Configurable retention settings.
  - Improved notifications and failure visibility.
- Exit criteria:
  - Daily personal-use loop is smooth with no blocking manual fixes.

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
- mock fixture-based capture path
- deterministic markdown write to local history
- clipboard copy and local diagnostics/logging
14. macOS host capture now fails explicitly when markdown persistence or clipboard write fails.
15. macOS host frontmatter rendering now escapes YAML-quoted values for safer output.

## Next Steps (Implementation Queue)
1. Replace fixture-based host capture with Safari native messaging transport (host request + extension response handshake).
2. Add host-side protocol mapping from extension errors to user-facing diagnostics and notification text.
3. Integrate hotkey registration and trigger parity between menu action and hotkey action.
4. Add capture integration tests using fixture variants for:
- long content truncation
- metadata-only fallback
- byte-identical markdown determinism checks
5. Implement Chrome transport path against the same protocol envelope and fallback rules.
