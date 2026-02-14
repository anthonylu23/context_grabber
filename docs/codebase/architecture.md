# Architecture

## Overview
Context Grabber is a local-first macOS menu bar tool that captures active context and emits deterministic markdown for LLM workflows.

## Core Components
- `apps/macos-host`: SwiftUI/AppKit menu bar host app, local file output, clipboard integration, transport diagnostics.
- `packages/shared-types`: protocol contracts, message envelopes, validators, error codes.
- `packages/extension-safari`: Safari transport handler + native-messaging CLI + runtime modules (`content`, `background`, `native-host`) for extension-side capture and native-port handling.
- `packages/extension-chrome`: Chrome transport handler + native-messaging CLI parity scaffolding.
- `packages/native-host-bridge`: capture orchestration, normalization, deterministic markdown rendering (TypeScript side).

## Request/Response Flow
1. Host creates `host.capture.request` with protocol version and timeout.
2. Host selects browser channel from frontmost app context (Safari vs Chrome).
3. Browser bridge (Safari/Chrome) handles request, validates shape/version, resolves capture source, validates payload size.
4. Browser bridge returns:
- `extension.capture.result` on success, or
- `extension.error` with protocol error code.
5. Host resolves capture:
- Uses browser payload on success.
- Falls back to metadata-only payload on timeout/transport/protocol errors, or when the front app is not Safari/Chrome.
6. Host renders markdown, writes local file, copies clipboard, updates diagnostics state.

## Reliability Guards
- Protocol version pinning (`"1"`).
- Runtime envelope validation before processing.
- Size limits for payload and serialized envelopes.
- Timeout-driven fallback path for extension transport failures.
- Deterministic markdown schema/output sections.
