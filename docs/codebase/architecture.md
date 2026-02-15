# Architecture

## Overview
Context Grabber is a local-first macOS menu bar tool that captures active context and emits deterministic markdown for LLM workflows.

## System Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Trigger                                                                │
│    Global Hotkey / Menu Action                                          │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  apps/macos-host  (SwiftUI / AppKit)                                    │
│                                                                         │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────────┐  │
│  │ Capture Pipeline  │──▶│  Channel Router   │   │ Menu Bar UI        │  │
│  └────────┬─────────┘   │ Safari / Chrome / │   │ (status icon,      │  │
│           │              │ Desktop           │   │  recent captures)  │  │
│           │              └──┬────┬────┬──────┘   └────────┬───────────┘  │
│           │                 │    │    │                    │              │
│           ▼                 │    │    │           ┌────────┴───────────┐  │
│  ┌──────────────────┐      │    │    │           │ Diagnostics &      │  │
│  │ Normalizer +      │      │    │    │           │ Permissions        │  │
│  │ Markdown Engine   │      │    │    │           └────────────────────┘  │
│  └────────┬─────────┘      │    │    │                                   │
│           │                 │    │    │                                   │
└───────────┼─────────────────┼────┼────┼───────────────────────────────────┘
            │                 │    │    │
            ▼                 │    │    │
┌───────────────────┐        │    │    │
│  Output            │        │    │    │
│  • Local .md file  │        │    │    │
│  • Clipboard       │        │    │    │
└───────────────────┘        │    │    │
                              │    │    │
          ┌───────────────────┘    │    └──────────────────┐
          │ frontmost = Safari     │ frontmost = Chrome     │ non-browser app
          ▼                        ▼                        ▼
┌──────────────────────────────────────────────┐  ┌─────────────────────────┐
│  Browser Capture Layer                        │  │  Desktop Capture Layer   │
│                                               │  │                          │
│  ┌─────────────────────┐ ┌──────────────────┐│  │  ┌────────────────────┐  │
│  │ extension-safari     │ │ extension-chrome ││  │  │ AX Focused-Element │  │
│  │                      │ │                  ││  │  │ Text Extraction    │  │
│  │  Native-Msg CLI      │ │  Native-Msg CLI  ││  │  └────────┬───────────┘  │
│  │    ▼                 │ │    ▼             ││  │           │              │
│  │  Background +        │ │  Background +    ││  │     text >= 400 chars?   │
│  │  Native Host Port    │ │  Native Host Port││  │      yes │     no │      │
│  │    ▼                 │ │    ▼             ││  │          │        ▼      │
│  │  Content Script      │ │  Content Script  ││  │          │  ┌──────────┐ │
│  │  Extraction          │ │  Extraction      ││  │          │  │ SCKit    │ │
│  └─────────────────────┘ └──────────────────┘│  │          │  │ Screenshot│ │
│                                               │  │          │  │ + Vision │ │
│  Returns: extension.capture.result            │  │          │  │ OCR      │ │
│  On error: extension.error + error code       │  │          │  └────┬─────┘ │
│  On timeout: ──▶ metadata-only fallback       │  │          │       │       │
└──────────────────────────────────────────────┘  │          │  OCR ok? │     │
                                                   │          │  yes│ no│      │
                                                   │          │    │   ▼      │
                                                   │          │  ┌──────────┐ │
                                                   │          │  │ Metadata │ │
                                                   │          │  │ Only     │ │
                                                   │          │  │ Fallback │ │
                                                   │          │  └──────────┘ │
                                                   └──────────┴───────────────┘

Shared Packages (consumed by host + extensions):
  • packages/shared-types — protocol contracts, validators, error codes
  • packages/native-host-bridge — orchestration, normalization, markdown rendering
```

### Capture Decision Flow

```
Trigger Received
       │
       ▼
Read Frontmost App
       │
       ▼
 ┌─────────────┐
 │ Safari or    │
 │ Chrome?      │
 └──┬───────┬───┘
  yes       no
    │        │
    ▼        ▼
 Request    AX Focused-Element
 Extension  Extraction
 Capture       │
 (1200ms)      ▼
    │      ┌──────────┐
    ▼      │ Text >=   │
 Payload   │ 400 chars?│
 with      └──┬─────┬──┘
 fullText?   yes     no
  yes│ no│    │      │
    │   │    │      ▼
    │   │    │   SCKit + Vision OCR
    │   │    │      │
    │   │    │      ▼
    │   │    │   ┌──────────┐
    │   │    │   │ OCR text  │
    │   │    │   │ available?│
    │   │    │   └──┬─────┬──┘
    │   │    │    yes     no
    │   ▼    │      │      │
    │  Metadata-    │      ▼
    │  Only Capture │   Desktop
    │  + Warning    │   Metadata-Only
    │   │    │      │   Fallback
    │   │    │      │      │
    ▼   ▼    ▼      ▼      ▼
  ┌──────────────────────────┐
  │ Normalize + Chunk +       │
  │ Summarize                 │
  └─────────────┬─────────────┘
                │
                ▼
  ┌──────────────────────────┐
  │ Generate Deterministic    │
  │ Markdown                  │
  └─────────────┬─────────────┘
                │
       ┌────────┼────────┐
       ▼        ▼        ▼
   Write     Copy to   Update
   Local     Clipboard  Diagnostics
   File
```

## Codebase Structure

```
context_grabber/
├── apps/
│   └── macos-host/                        # Native macOS menu bar app (Swift)
│       ├── Package.swift                   #   Swift package manifest
│       ├── Sources/ContextGrabberHost/
│       │   ├── ContextGrabberHostApp.swift #   App entry, menu bar, capture pipeline
│       │   └── Resources/
│       │       └── sample-browser-capture.json
│       └── Tests/ContextGrabberHostTests/
│           └── CapturePipelineTests.swift  #   Swift integration tests
│
├── packages/
│   ├── shared-types/                      # Protocol contracts & validators
│   │   ├── src/
│   │   │   ├── index.ts                   #   Package entry (re-exports)
│   │   │   └── contracts.ts               #   Types, envelopes, error codes, validators
│   │   └── test/
│   │       └── contracts.test.ts
│   │
│   ├── extension-safari/                  # Safari extension + native-messaging CLI
│   │   ├── manifest.json                  #   WebExtension manifest
│   │   ├── fixtures/active-tab.json       #   Test fixture payload
│   │   ├── src/
│   │   │   ├── index.ts                   #   Package entry
│   │   │   ├── transport.ts               #   Transport handler (protocol/size guards)
│   │   │   ├── native-messaging-cli.ts    #   Bridge CLI (stdin → response)
│   │   │   ├── extract-active-tab.ts      #   AppleScript live extraction
│   │   │   ├── sanitize-snapshot.ts       #   Runtime-safe sanitizer
│   │   │   └── runtime/                   #   Packaged extension runtime
│   │   │       ├── background.ts          #     Background request handler
│   │   │       ├── background-entrypoint.ts
│   │   │       ├── background-main.ts     #     Bootstrap
│   │   │       ├── content.ts             #     Content extraction helpers
│   │   │       ├── content-entrypoint.ts
│   │   │       ├── content-main.ts        #     Bootstrap
│   │   │       ├── native-host.ts         #     Native-host port binder
│   │   │       ├── messages.ts            #     Runtime message contracts
│   │   │       └── index.ts
│   │   └── test/                          #   Transport, CLI, runtime tests
│   │
│   ├── extension-chrome/                  # Chrome extension + native-messaging CLI
│   │   ├── manifest.json                  #   MV3 manifest
│   │   ├── fixtures/active-tab.json       #   Test fixture payload
│   │   ├── src/
│   │   │   ├── index.ts                   #   Package entry
│   │   │   ├── transport.ts               #   Transport handler
│   │   │   ├── native-messaging-cli.ts    #   Bridge CLI
│   │   │   └── extract-active-tab.ts      #   AppleScript live extraction
│   │   └── test/                          #   Transport, CLI, extraction tests
│   │
│   └── native-host-bridge/                # Capture orchestration + markdown engine (TS)
│       ├── src/
│       │   ├── index.ts                   #   Envelope parsing, timeout wrapper
│       │   ├── capture.ts                 #   Normalization, fallback logic
│       │   └── markdown.ts                #   Deterministic markdown rendering
│       └── test/
│           └── index.test.ts
│
├── scripts/
│   └── check-workspace.ts                 # Lint + typecheck + test runner
│
├── docs/
│   ├── codebase/
│   │   ├── architecture.md                # This file
│   │   ├── details.md                     # Protocol constants, limits, test strategy
│   │   └── usage.md                       # Build, run, test instructions
│   └── plans/
│       └── context-grabber-project-plan.md # Full project plan + roadmap
│
├── package.json                           # Bun workspace root
├── bunfig.toml                            # Bun config
├── tsconfig.base.json                     # Shared strict TS config
├── biome.json                             # Lint + format config
├── .editorconfig
├── .githooks/pre-commit                   # Runs `bun run check`
├── .github/workflows/ci.yml
├── types/bun-test.d.ts                    # Bun test type shims
├── AGENTS.md                              # AI agent guidelines
└── README.md
```

## Core Components
- `apps/macos-host`: SwiftUI/AppKit menu bar host app, local file output, clipboard integration, transport diagnostics, and permission-remediation menu actions.
- `packages/shared-types`: protocol contracts, message envelopes, validators, error codes.
- `packages/extension-safari`: Safari transport handler + native-messaging CLI + runtime modules (`content`, `background`, `native-host`, `background-entrypoint`, `content-entrypoint`, runtime bootstraps) and extension manifest for packaged runtime wiring.
- `packages/extension-chrome`: Chrome transport handler + native-messaging CLI + live active-tab extraction helper.
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
- Falls back to metadata-only payload on timeout/transport/protocol errors.
- For non-browser front apps, uses desktop AX->OCR resolver (AX focused element -> ScreenCaptureKit screenshot + Vision OCR fallback -> metadata-only desktop fallback).
6. Host renders markdown, writes local file, copies clipboard, updates diagnostics state.

## Reliability Guards
- Protocol version pinning (`"1"`).
- Runtime envelope validation before processing.
- Size limits for payload and serialized envelopes.
- Timeout-driven fallback path for extension transport failures.
- Deterministic markdown schema/output sections.
