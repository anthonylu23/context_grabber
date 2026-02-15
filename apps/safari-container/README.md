# Safari Container (macOS)

Concrete Safari Web Extension container project generated from the packaged runtime in `packages/extension-safari`.

## Purpose
- Produce a real Xcode app + Safari extension target for local signed installs.
- Keep runtime resources aligned with compiled TypeScript extension artifacts (`manifest.json` + `dist/**` + `icons/**`).

## Project Location
- `apps/safari-container/ContextGrabberSafari/ContextGrabberSafari.xcodeproj`

## Regenerate From Current Runtime
From repo root:

```bash
bun run safari:container:sync
```

This command:
1. Builds `packages/extension-safari`.
2. Stages a temporary minimal WebExtension bundle (`manifest.json` + `dist/**` + `icons/**`).
3. Re-runs `safari-web-extension-converter` to refresh the Xcode project/resources.

## Build Validation (Unsigned)
From repo root:

```bash
bun run safari:container:build
```

This runs `xcodebuild` with `CODE_SIGNING_ALLOWED=NO` to validate project integrity in CI/local automation.

## First-Run Local Install (Signed)
1. Open the project:
```bash
open apps/safari-container/ContextGrabberSafari/ContextGrabberSafari.xcodeproj
```
2. In Xcode, select target `ContextGrabberSafari`:
- `Signing & Capabilities` -> choose your Apple Development team.
- Ensure signing is automatic for local development.
3. Select target `ContextGrabberSafari Extension`:
- `Signing & Capabilities` -> choose the same team.
- Keep bundle id as a child of app bundle id (`<app_bundle_id>.Extension`).
4. Choose scheme `ContextGrabberSafari` and run the app target.
5. Safari opens extension settings (or open manually):
- Safari -> Settings -> Extensions
- Enable `ContextGrabberSafari Extension`.

## Troubleshooting
- `Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier`:
  - App and extension bundle identifiers are misaligned.
  - Ensure extension bundle id starts with app bundle id + suffix (for example `.Extension`).
- Signing/provisioning errors in Xcode:
  - Confirm both targets use the same team and Automatic signing.
  - Re-select the team if Xcode cached stale signing settings.
- Extension does not appear in Safari -> Extensions:
  - Re-run app target after a successful signed build.
  - Confirm extension target built successfully in Xcode build log.

## Notes
- Placeholder icon assets are currently used in `packages/extension-safari/assets/icons` and can be replaced with branded assets later.
- Converter output is generated; treat `apps/safari-container` as derived from packaged runtime artifacts.
