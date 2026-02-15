# Component: Safari Container

Path: `apps/safari-container`

## Responsibilities
1. Provide concrete macOS app + Safari app-extension targets for local signed extension installs.
2. Embed packaged Safari WebExtension runtime assets (`manifest.json` + `dist/**` + `icons/**`) produced from `packages/extension-safari`.
3. Serve as the install bridge between TypeScript runtime code and Safari's extension host requirements.

## Project Shape
- Xcode project: `apps/safari-container/ContextGrabberSafari/ContextGrabberSafari.xcodeproj`
- App target: `ContextGrabberSafari`
- Extension target: `ContextGrabberSafari Extension`
- Extension resources path in project: `ContextGrabberSafari Extension/Resources`

## Regeneration Workflow
- Sync command: `bun run safari:container:sync`
- Script: `scripts/sync-safari-container.sh`
- Under the hood:
  1. Builds `packages/extension-safari`.
  2. Creates a temporary minimal bundle (`manifest.json` + `dist/**` + `icons/**`).
  3. Runs `xcrun safari-web-extension-converter` with `--macos-only --swift --copy-resources`.

## Build Validation
- Command: `bun run safari:container:build`
- Script: `scripts/build-safari-container.sh`
- Uses `xcodebuild ... CODE_SIGNING_ALLOWED=NO` for unsigned compile validation.

## Local Signed Install Requirements
1. Both app and extension targets must be signed by the same Apple Development team.
2. Extension bundle identifier must be prefixed by the parent app bundle identifier.
3. Extension enablement still requires Safari Settings -> Extensions after app install/run.

## Current Limitations
- Placeholder icon assets are used for extension manifest icons and should be replaced with final branded assets.
- Converter output is generated source; avoid manual edits that should be sourced from `packages/extension-safari` runtime artifacts.
