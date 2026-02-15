# Permissions Model

## macOS Permissions
1. Accessibility
- Required for AX focused-element extraction.
- If missing, desktop AX path returns unavailable and host logs remediation.

2. Screen Recording
- Required for ScreenCaptureKit-based OCR image capture.
- If missing, desktop OCR path may fail and metadata fallback is used.

3. Automation (Apple Events)
- Required for AppleScript-based Safari/Chrome live extraction.
- Must be granted to the calling process (Terminal or app bundle).

## Browser Developer Settings
1. Safari: `Settings -> Developer -> Allow JavaScript from Apple Events`
2. Chrome: `View -> Developer -> Allow JavaScript from Apple Events`

Without these settings, live tab extraction fails with extension-unavailable style errors.
