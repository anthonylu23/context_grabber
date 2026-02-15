# Capture Workflows

## Browser Capture
1. Focus Safari or Chrome tab.
2. Trigger capture from menu or `⌃⌥⌘C`.
3. Host requests extension payload.
4. On success: markdown file + clipboard update.
5. On failure: metadata-only markdown with warning.

## Desktop Capture
1. Focus non-browser app.
2. Trigger capture.
3. Host attempts AX extraction.
4. If AX text is weak, host attempts OCR.
5. If both fail, host writes metadata-only capture with explicit warnings.

## Reviewing Output
- Recent captures submenu shows latest entries.
- `Copy Last Capture` re-copies latest markdown without recapturing.
- History folder: `~/Library/Application Support/ContextGrabber/history/`.
