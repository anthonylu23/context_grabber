# Limits and Defaults

## Capture and Transport
- Protocol version: `1`
- Host default timeout: `1200ms`
- Desktop AX default threshold: `240` chars
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
- Brief output key point cap: `5`
- Brief output links cap: `5`
- Summary budget options: `80`, `120`, `180` tokens

## Buffers
- Safari live extraction process buffer cap: `8MiB`

## Host Preferences
- Default retention max file count: `200`
- Default retention max file age: `30` days
- Retention max file count menu options: `50`, `100`, `200`, `500`, `Unlimited`
- Retention max age menu options: `7`, `30`, `90`, `Unlimited`
- Clipboard copy mode default: `Markdown File`
- Output format preset default: `Full`
- Product context line default: `On`
- Summarization mode default: `Heuristic`
- Summarization provider default: `Not Set`
- Summarization model default: provider-specific auto model
- Summarization timeout default: `2500ms`
- Output directory default: `~/Documents/ContextGrabber/history`
- Capture feedback auto-dismiss: `4s` (menu panel + floating popup)
- Capture filename shape: `yyyyMMdd-HHmmss-<requestPrefix>.md` (used to scope retention/recent-history filtering)
