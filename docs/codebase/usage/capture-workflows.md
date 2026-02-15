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
4. If AX text is below the app-specific threshold, host attempts OCR.
5. If both fail, host writes metadata-only capture with explicit warnings.

## Reviewing Output
- Recent captures submenu shows latest host-generated capture entries only.
- `Copy Last Capture` re-copies latest markdown without recapturing.
- History defaults to: `~/Library/Application Support/ContextGrabber/history/`.
- You can override output location via `Preferences -> Choose Custom Output Directory...`.

## Retention and Pause Controls
- `Preferences -> Retention Max Files` controls file-count pruning (`Unlimited` disables count-based pruning).
- `Preferences -> Retention Max Age` controls age-based pruning (`Unlimited` disables age-based pruning).
- Pruning runs after each successful capture write and only targets host-generated capture files.
- `Preferences -> Pause/Resume Captures (Placeholder)` toggles a temporary no-op capture mode.
