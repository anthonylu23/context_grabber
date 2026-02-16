# Output Schema

Structure of `cgrab capture` output in both markdown and JSON formats.

## Markdown Output

Capture produces deterministic markdown with YAML frontmatter followed by structured content sections.

### Frontmatter

YAML block delimited by `---`:

```yaml
---
id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
captured_at: "2026-02-15T14:30:00.000Z"
source_type: "webpage"
origin: "https://example.com/page"
title: "Example Page Title"
app_or_site: "Example Site"
extraction_method: "browser_extension"
confidence: 0.92
truncated: false
token_estimate: 1234
warnings: []
---
```

#### Field Reference

| Field | Type | Values | Description |
|---|---|---|---|
| `id` | string | UUID v4 | Unique identifier for this capture |
| `captured_at` | string | ISO 8601 | Capture timestamp |
| `source_type` | string | `webpage`, `desktop_app` | Origin type |
| `origin` | string | URL or `app://<bundleID>` | Source location. Browser captures use the page URL; desktop captures use `app://com.example.app` format |
| `title` | string | — | Page title (browser) or app name (desktop) |
| `app_or_site` | string | — | Site name or hostname (browser) or app name (desktop) |
| `extraction_method` | string | `browser_extension`, `accessibility`, `ocr`, `metadata_only` | How content was extracted |
| `confidence` | float | 0.00–1.00 | Extraction quality score (see table below) |
| `truncated` | bool | — | `true` if content exceeded the 200,000 character limit |
| `token_estimate` | int | — | Estimated token count: `ceil(char_count / 4)` |
| `warnings` | string[] | — | Any extraction warnings (empty array if none) |

#### Confidence Scores by Method

| Method | Confidence | Description |
|---|---|---|
| `browser_extension` | 0.92 | Full DOM extraction via extension |
| `accessibility` | 0.75 | macOS Accessibility API text extraction |
| `ocr` | 0.60 | Vision framework OCR on screen capture |
| `metadata_only` | 0.45 | Only app name and basic metadata available |

**Note:** Browser captures are rendered by a TypeScript engine and desktop captures by a Swift engine. There are minor rendering differences: the `warnings` field renders as `warnings: []` for browser captures but as a YAML list for desktop captures. Agents should parse the YAML frontmatter generically rather than relying on a specific serialization format for array fields.

### Content Sections

After the frontmatter, the markdown contains these sections in order:

#### Summary

```markdown
## Summary
Extractive summary of the page content, up to 6 sentences. Generated
heuristically from the first meaningful paragraphs of content.
```

- Maximum 6 sentences
- Heuristic extraction (not LLM-generated in the capture pipeline)

#### Key Points

```markdown
## Key Points
- First key point extracted from the content
- Second key point
- Up to 8 deduplicated key sentences
```

- Maximum 8 points
- Deduplicated against each other and against the summary

#### Content Chunks

```markdown
## Content Chunks
### chunk-001 (tokens: 1500)
First chunk of normalized page text...

### chunk-002 (tokens: 800)
Second chunk of normalized page text...
```

- Target chunk size: 1,500 tokens
- Hard maximum: 2,000 tokens per chunk (browser captures via TypeScript renderer)
- Chunks are sequentially numbered: `chunk-001`, `chunk-002`, etc.
- Token count shown in each chunk header for browser captures; desktop captures (Swift renderer) omit the token count parenthetical

#### Raw Excerpt

````markdown
## Raw Excerpt
```text
First 8,000 characters of normalized text content, preserving
original structure but with boilerplate removed...
```
````

- Maximum 8,000 characters
- Fenced in a `text` code block

#### Links & Metadata

```markdown
## Links & Metadata
### Links
- [Link Text](https://example.com/link)
- [Another Link](https://example.com/other)

### Metadata
- browser: safari
- url: https://example.com
- language: en
- author: John Doe
- site_name: Example Site
- meta_description: Page description from meta tags
- published_time: 2026-01-15
```

Metadata fields are included only when available. Desktop captures include `app_name` and `app_bundle_id` instead of browser-specific fields.

---

## Content Limits

| Limit | Value | Description |
|---|---|---|
| Max full text | 200,000 chars | Content truncated beyond this; `truncated: true` in frontmatter |
| Max envelope | 250,000 chars | Total serialized message limit |
| Max raw excerpt | 8,000 chars | Raw excerpt section cap |
| Target chunk tokens | 1,500 | Preferred chunk size |
| Hard chunk tokens | 2,000 | Maximum chunk size (browser captures only; desktop captures flush at 1,500 without a hard cap) |
| Max summary lines | 6 | Summary sentence limit (browser captures; desktop captures use a ~120 token budget) |
| Max key points | 8 | Key points limit |
| Token estimation | `ceil(chars / 4)` | Approximate token count |

---

## JSON Output

When using `--format json`, the structure depends on the capture type.

### Browser Capture JSON

```json
{
  "target": "safari",
  "extractionMethod": "browser_extension",
  "warnings": [],
  "markdown": "---\nid: ...\n---\n\n## Summary\n...",
  "payload": {
    "source": "browser",
    "browser": "safari",
    "url": "https://example.com",
    "title": "Page Title",
    "fullText": "...",
    "headings": [
      { "level": 1, "text": "Main Heading" }
    ],
    "links": [
      { "text": "Link", "href": "https://..." }
    ],
    "metaDescription": "...",
    "siteName": "...",
    "language": "en",
    "author": "...",
    "publishedTime": "...",
    "selectionText": "...",
    "extractionWarnings": []
  }
}
```

| Field | Type | Description |
|---|---|---|
| `target` | string | Browser name (`safari`, `chrome`) |
| `extractionMethod` | string | Method used for extraction |
| `errorCode` | string | Error code if capture failed (omitted on success via `omitempty`) |
| `warnings` | string[] | Capture warnings (always an array) |
| `markdown` | string | Full rendered markdown including frontmatter |
| `payload` | object | Raw extension payload (when available) |

### Desktop Capture JSON

Desktop capture JSON is produced by the Swift host binary. It follows the same markdown frontmatter structure with `source_type: "desktop_app"` and includes desktop-specific metadata fields (`app_name`, `app_bundle_id`).

---

## List Output JSON

### Tabs

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

### Apps

```json
[
  {
    "appName": "Finder",
    "bundleIdentifier": "com.apple.finder",
    "windowCount": 3
  }
]
```

### Combined (tabs + apps)

```json
{
  "tabs": [ ... ],
  "apps": [ ... ]
}
```

---

## Doctor Output JSON

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
    { "target": "chrome", "status": "unreachable", "detail": "..." }
  ],
  "warnings": []
}
```

| Field | Type | Values |
|---|---|---|
| `overallStatus` | string | `ready`, `unreachable` |
| `bridges[].status` | string | `ready`, `unreachable`, `protocol_mismatch` |
