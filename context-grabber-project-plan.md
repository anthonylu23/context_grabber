# Context-Grabber v1 Plan (macOS Menu Bar, Local-First, Web-First)

## Summary
Build a native macOS menu bar app (Swift/SwiftUI + AppKit) that captures current screen context and outputs structured markdown for LLM workflows.  
v1 priorities are:
1. Full-page capture for focused browser tabs (Chrome + Safari) via browser extensions + native host.
2. Non-browser desktop capture via Accessibility text extraction with Vision OCR fallback.
3. Manual global hotkey trigger, clipboard copy, and local markdown history files.
4. Local-only processing with no cloud dependency.

## Scope
In scope:
1. Menu bar app with status menu, capture action, and recent captures list.
2. Browser-aware full-page context capture with metadata.
3. Desktop app context capture fallback path.
4. Markdown normalization pipeline with chunking and section summaries.
5. Clipboard output + saved `.md` artifacts.
6. Permissions onboarding and diagnostics.

Out of scope (v1):
1. Auto-capture on focus change.
2. Cloud enrichment/summarization.
3. Auto-typing into destination apps.
4. Arc/Firefox support.
5. Tool-specific output presets (ChatGPT/Claude/Codex custom formats).

## Architecture
1. `ContextGrabberApp` (macOS native host)
- Menu bar UI, hotkey registration, permission checks, pipeline orchestration.
- IPC endpoint for browser extension payloads.
2. `Browser Capture Layer`
- Safari Web Extension + Chrome extension.
- Content script extracts full DOM text + semantic metadata.
- Native messaging bridge sends capture payload to macOS app.
3. `Desktop Capture Layer`
- Accessibility extractor for focused app selected/visible text.
- OCR fallback from focused window screenshot using Vision.
4. `Normalization + Markdown Engine`
- Cleans text, deduplicates boilerplate, chunks large docs, builds summary sections.
- Emits stable markdown schema + frontmatter.
5. `Storage + Clipboard`
- Writes timestamped markdown files to app data directory.
- Copies final markdown to system clipboard.
6. `Diagnostics`
- Permission state checks, extension connectivity checks, capture failure reasons.

## Public Interfaces / Types
1. Native capture request contract

```ts
type CaptureSource = "browser" | "desktop";
type CaptureMode = "manual_hotkey";

interface CaptureRequest {
  requestId: string;
  timestamp: string; // ISO-8601
  mode: CaptureMode;
}
```

2. Browser extension payload

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
}
```

4. Unified normalized context

```ts
interface NormalizedContext {
  id: string;
  capturedAt: string;
  sourceType: "webpage" | "desktop_app";
  title: string;
  origin: string; // URL or app/window identifier
  metadata: Record<string, string>;
  summary: string;
  keyPoints: string[];
  chunks: Array<{ chunkId: string; tokenEstimate: number; text: string }>;
  rawExcerpt: string;
}
```

5. Markdown output schema (stable)
1. YAML frontmatter: `id`, `captured_at`, `source_type`, `origin`, `title`, `app_or_site`, `language`, `token_estimate`.
2. Sections:
- `## Summary`
- `## Key Points`
- `## Content Chunks`
- `## Raw Excerpts`
- `## Links & Metadata`

## Data Flow
1. User presses global hotkey.
2. App inspects focused app.
3. If focused app is Chrome/Safari:
- Request active tab capture from extension.
- Receive full-page payload over native messaging.
4. Else:
- Attempt Accessibility extraction.
- If insufficient text, capture screenshot and run OCR.
5. Normalize and chunk content.
6. Generate markdown using stable schema.
7. Save `.md` file and copy same content to clipboard.
8. Show menu bar notification with result + source.

## Permissions and Security
1. macOS permissions required:
- Accessibility (AX APIs).
- Screen Recording (for OCR screenshot fallback).
2. Browser extension permissions:
- Active tab access, scripting/content extraction, native messaging.
3. Privacy guarantees:
- Local-only processing/storage by default.
- No network calls in capture pipeline.
4. Data retention:
- Local history directory with configurable max files/age.

## Failure Modes and Handling
1. Missing permissions:
- Block capture path and show exact permission remediation step.
2. Extension unavailable or disconnected:
- Fallback to URL/title only for browser, mark reduced fidelity.
3. Very large pages:
- Deterministic chunking and capped per-chunk size; preserve raw chunk references.
4. OCR low confidence:
- Flag confidence warning in markdown metadata.
5. Clipboard write failure:
- File still saved; user notified with file path.

## Implementation Phases
1. Phase 1: Native shell + hotkey + storage/clipboard + markdown engine scaffold.
2. Phase 2: Safari extension + native messaging + end-to-end webpage capture.
3. Phase 3: Chrome extension parity.
4. Phase 4: Desktop AX extraction + OCR fallback.
5. Phase 5: Chunk/summarize heuristics, diagnostics panel, and hardening.
6. Phase 6: Packaging, signing, and installer/distribution prep.

## Test Cases and Scenarios
1. Browser full-page capture
- Long article page, SPA page, authenticated docs page, heavy-nav marketing page.
2. Metadata extraction
- Confirm title/url/description/author/date availability and graceful missing-field behavior.
3. Desktop capture
- Text editor (AX success), design tool (AX limited -> OCR fallback), terminal window.
4. Permission states
- Fresh install with no permissions, partial permissions, revoked permissions.
5. Large-context handling
- 100k+ character content chunking consistency and markdown determinism.
6. Output integrity
- Clipboard content equals saved file content for each capture.
7. Reliability
- 100 repeated hotkey captures without crash or stuck state.
8. Performance targets
- Browser capture to clipboard under 2.5s median; desktop under 3.5s median on Apple Silicon baseline.

## Acceptance Criteria
1. Manual hotkey capture works from menu bar in all supported paths.
2. Chrome and Safari focused-tab captures include full text + metadata.
3. Non-browser capture succeeds via AX or OCR fallback with explicit source marker.
4. Generated markdown follows schema and is directly paste-ready for LLM tools.
5. Every capture is copied to clipboard and saved as timestamped `.md`.
6. All processing remains local with no outbound network dependency.

## Assumptions and Defaults
1. Primary users are individual macOS users on modern Apple Silicon devices.
2. v1 supports only Chrome + Safari for full webpage extraction.
3. Trigger model is manual hotkey only.
4. Output format is universal markdown (no per-LLM presets in v1).
5. Local history is enabled by default (clipboard + files).
6. Desktop capture prioritizes Accessibility text, then OCR fallback.
