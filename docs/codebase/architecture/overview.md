# Architecture Overview

Context Grabber is a local-first macOS menu bar app that captures active context and writes deterministic markdown.

## Runtime Topology
1. Trigger source: menu action or global hotkey.
2. Host app routes capture by effective frontmost app.
3. Browser path: Safari or Chrome native-messaging transport.
4. Desktop path: Accessibility extraction first, OCR fallback second.
5. Output path: deterministic markdown file + clipboard + status diagnostics.

## Primary Design Goals
1. Deterministic output shape for downstream LLM workflows.
2. Fast local capture with explicit fallbacks.
3. Clear operational visibility (status line, diagnostics, warnings).
4. No remote processing in capture pipeline.

## Capture Routing
1. Frontmost app is Safari/Chrome:
- Send `host.capture.request` over browser-native messaging.
- On success, use extension payload.
- On timeout/transport/protocol failure, produce metadata-only fallback.

2. Frontmost app is non-browser:
- Attempt AX focused-element extraction.
- If AX text below threshold, attempt OCR via ScreenCaptureKit + Vision.
- If OCR unavailable, produce metadata-only desktop capture with warning.

## Reliability Guards
1. Protocol version pinning (`1`) for host/extension envelopes.
2. Payload shape and size validation in bridge layers.
3. Timeout-based fallback behavior in browser and desktop capture stages.
4. Deterministic markdown section ordering and truncation behavior.
