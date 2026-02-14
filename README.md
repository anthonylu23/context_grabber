# Context Grabber

Context Grabber is a local-first macOS menu bar app for quickly capturing the current screen context and turning it into structured markdown for LLM workflows.

## What This Project Will Be
- Manual hotkey/menu trigger for one-click context capture
- Full-page capture for Safari and Chrome tabs via browser extensions
- Desktop app capture using Accessibility text extraction with OCR fallback
- Deterministic markdown output copied to clipboard and saved locally
- Diagnostics for permissions, capture source, and failure reasons

## Tech Stack
- Native app: Swift 5.10+, SwiftUI + AppKit (macOS)
- Browser extensions: TypeScript (Safari Web Extension + Chrome MV3)
- JS runtime/tooling: Bun (`bun install`, `bun run`)
- OCR: Apple Vision framework
- Desktop extraction: macOS Accessibility APIs
- Storage/output: local markdown files + system clipboard

## Core Constraints
- Local-only processing and storage in the capture pipeline
- No cloud dependency required
- Deterministic, paste-ready markdown schema

## Current Status
- Planning complete and implementation roadmap defined in `context-grabber-project-plan.md`.
- Next step: scaffold the workspace and build the first end-to-end manual capture slice.
