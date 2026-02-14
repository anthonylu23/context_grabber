# Architecture

## Overview
Context Grabber is a local-first macOS menu bar tool that captures active context and emits deterministic markdown for LLM workflows.

## Core Components
- `apps/macos-host`: SwiftUI/AppKit menu bar host app, local file output, clipboard integration, transport diagnostics.
- `packages/shared-types`: protocol contracts, message envelopes, validators, error codes.
- `packages/extension-safari`: Safari-side transport handler + native-messaging CLI bridge.
- `packages/extension-chrome`: Chrome protocol envelope helpers (parity scaffolding).
- `packages/native-host-bridge`: capture orchestration, normalization, deterministic markdown rendering (TypeScript side).

## Request/Response Flow
1. Host creates `host.capture.request` with protocol version and timeout.
2. Safari bridge handles request, validates shape/version, loads extraction payload (fixture-backed currently), validates payload size.
3. Safari bridge returns:
- `extension.capture.result` on success, or
- `extension.error` with protocol error code.
4. Host resolves capture:
- Uses browser payload on success.
- Falls back to metadata-only payload on timeout/transport/protocol errors.
5. Host renders markdown, writes local file, copies clipboard, updates diagnostics state.

## Reliability Guards
- Protocol version pinning (`"1"`).
- Runtime envelope validation before processing.
- Size limits for payload and serialized envelopes.
- Timeout-driven fallback path for extension transport failures.
- Deterministic markdown schema/output sections.
