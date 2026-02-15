# Limits and Defaults

## Capture and Transport
- Protocol version: `1`
- Host default timeout: `1200ms`
- Desktop AX default threshold: `400` chars
- Desktop AX tuned thresholds:
  - dense editor apps: `220` chars
  - terminal-like apps: `180` chars
- Desktop AX traversal defaults:
  - max depth: `2` (raised to `3` for tuned app profiles)
  - max visited elements: `96` (raised for tuned app profiles)
- Desktop ScreenCaptureKit callback timeout: `1.5s`

## Content and Rendering
- Browser full-text cap: `200,000` chars
- Markdown raw excerpt cap: `8,000` chars
- Approximate token estimate: `chars / 4`

## Buffers
- Safari live extraction process buffer cap: `8MiB`

## Host Preferences
- Default retention max file count: `200`
- Default retention max file age: `30` days
- Retention max file count menu options: `50`, `100`, `200`, `500`, `Unlimited`
- Retention max age menu options: `7`, `30`, `90`, `Unlimited`
- Clipboard copy mode default: `Markdown File`
- Output directory default: `~/Documents/ContextGrabber/history`
- Capture filename shape: `yyyyMMdd-HHmmss-<requestPrefix>.md` (used to scope retention/recent-history filtering)
