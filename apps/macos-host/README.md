# ContextGrabberHost (macOS)

SwiftUI/AppKit menu bar host scaffold for Milestone A.

## Current Capabilities
- Menu bar app with actions:
  - `Capture Now`
  - `Open Recent Captures`
  - `Run Diagnostics`
  - `Quit`
- Uses bundled mock browser payload fixture for initial vertical-slice validation.
- Generates deterministic markdown and writes to:
  - `~/Library/Application Support/ContextGrabber/history/`
- Copies markdown output to clipboard.
- Writes local logs to:
  - `~/Library/Application Support/ContextGrabber/logs/host.log`

## Run
```bash
cd apps/macos-host
swift run
```

## Notes
- Safari/Chrome native messaging and extension handshake are next implementation steps.
- AX/OCR desktop capture is intentionally deferred.
