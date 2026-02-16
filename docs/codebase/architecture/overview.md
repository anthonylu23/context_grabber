# Architecture Overview

Context Grabber is a local-first macOS menu bar app that captures active context and writes deterministic markdown.

## Runtime Topology
1. Trigger source: menu action, global hotkey, or CLI command (`cgrab capture`).
2. Host app routes capture by effective frontmost app.
3. Browser path: Safari or Chrome native-messaging transport (or AppleScript live extraction via CLI).
4. Desktop path: Accessibility extraction first, OCR fallback second.
5. Output path: deterministic markdown file + clipboard + status diagnostics.
6. CLI path: Go CLI (`cgrab`) orchestrates capture via subprocess dispatch to host binary (desktop) and Bun bridge (browser).

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
- If AX text is below app-aware threshold, attempt OCR via ScreenCaptureKit + Vision.
- If OCR unavailable, produce metadata-only desktop capture with warning.

## Agent Integration

Agent skill definitions (`packages/agent-skills/skill/`) make `cgrab` discoverable by AI coding agents (Claude Code, OpenCode, Cursor). Skills are installed via:
- `npx skills add anthonylu23/context_grabber` (skills.sh ecosystem, from `skills/context-grabber/`)
- `cgrab skills install` (Bun delegation or `go:embed` fallback from `cgrab/internal/skills/`)

## Reliability Guards
1. Protocol version pinning (`1`) for host/extension envelopes.
2. Payload shape and size validation in bridge layers.
3. Timeout-based fallback behavior in browser and desktop capture stages.
4. Deterministic markdown section ordering and truncation behavior.
