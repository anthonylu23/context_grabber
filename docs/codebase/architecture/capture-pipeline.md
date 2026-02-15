# Capture Pipeline

## Host Pipeline (Swift)
1. Build capture request envelope.
2. Resolve effective frontmost app context.
3. Choose browser route or desktop route.
4. Normalize payload into markdown schema.
5. Write local file, copy clipboard, update UI indicators and logs.

## Browser Pipeline (Safari/Chrome)
1. Validate host envelope type/version.
2. Resolve extraction source (live/runtime/fixture by package rules).
3. Build capture payload with metadata, text, headings, links.
4. Return `extension.capture.result` or `extension.error`.
5. Host maps transport errors to metadata-only fallback payload.

## Desktop Pipeline
1. AX extraction from focused element/window via bounded tree traversal:
- start from focused element + focused window roots
- walk child/parent/title-linked AX elements with depth/element caps
- collect and dedupe normalized text attributes per node
2. Adaptive threshold gate:
- default AX threshold: `400` chars
- lower per-app thresholds for dense editor/terminal-style apps
3. If AX text meets threshold, emit desktop accessibility capture.
4. OCR fallback:
- Get shareable content from ScreenCaptureKit.
- Capture frontmost window image (display fallback if needed).
- Run Vision text recognition.
5. Metadata fallback when AX and OCR cannot provide text.

## Warnings and Transport Status
- Browser success: `*_extension_ok`.
- Browser error fallback: `*_extension_error:<CODE>`.
- Desktop success: `desktop_capture_accessibility` or `desktop_capture_ocr`.
- Desktop metadata fallback: `desktop_capture_metadata_only` + warning details.

## Determinism Rules
1. Stable markdown section order.
2. Stable truncation behavior and warning emission.
3. Stable chunk numbering (`chunk-001`, ...).
