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
- `Copy Last Capture` copies the latest capture using your configured clipboard mode.
- After each capture, a transient floating summary popup appears with quick actions (`Copy to Clipboard`, `Open File`, `Dismiss`).
- Clipboard mode can be set in `Settings -> Clipboard Copy Mode` (`Markdown File` or `Text`).
- History defaults to: `~/Documents/ContextGrabber/history/`.
- You can override output location via `Settings -> Output Directory -> Custom Output Directory`.

## Retention and Pause Controls
- `Settings -> Advanced Settings... -> Retention Max Files` controls file-count pruning (`Unlimited` disables count-based pruning).
- `Settings -> Advanced Settings... -> Retention Max Age` controls age-based pruning (`Unlimited` disables age-based pruning).
- Pruning runs after each successful capture write and only targets host-generated capture files.
- `Settings -> Pause/Resume Captures` toggles a temporary no-op capture mode.
