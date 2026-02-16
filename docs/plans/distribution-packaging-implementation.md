# Distribution + Packaging Implementation Plan

## Goal

Build a working unsigned `.pkg` installer that installs both `ContextGrabber.app` and `cgrab` CLI on macOS. This covers Phases 1-3 of the distribution plan (contract, scripts, dogfood). Signing/notarization and Homebrew Cask are deferred.

## Finalized Contract

### Install Layout

| Component              | Install Path                            |
| ---------------------- | --------------------------------------- |
| `ContextGrabber.app`   | `/Applications/ContextGrabber.app`      |
| `cgrab` CLI            | `/usr/local/bin/cgrab`                  |

### CLI Packaging Style

**Standalone binary** (not a symlink into the .app bundle).

Rationale:
- `cgrab` is a Go binary, `ContextGrabber.app` is Swift — separate build artifacts
- Go binary already resolves the host at `/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost` as a fallback path
- No symlink breakage if the app gets relocated
- Simpler `.pkg` structure: two independent components
- Follows the pattern used by `gh`, `docker`, and similar tools

### Version Strategy

- **Scheme**: semantic versioning, starting at `0.1.0`
- **Go CLI**: inject at build time via `-ldflags "-X github.com/context-grabber/cgrab/cmd.Version=0.1.0"`
- **Swift app**: set `CFBundleShortVersionString` and `CFBundleVersion` in the app bundle's `Info.plist` during staging
- **Single source of truth**: version is read from a `VERSION` file at the repo root, consumed by both build scripts
- **Pkg identifier**: `com.contextgrabber.pkg` (product), `com.contextgrabber.app` (app component), `com.contextgrabber.cli` (CLI component)

### Permission Model

Desktop capture relies on the single-binary permission model:
- `ContextGrabberHost` (inside `.app` bundle) has Accessibility/Screen Recording grants
- `cgrab capture --app` spawns `ContextGrabberHost --capture` → inherits the app's permissions
- The installed `.app` path must be stable (`/Applications/ContextGrabber.app`) so permission grants persist across installs

## File Layout

```
VERSION                                    # e.g. "0.1.0" — single source of truth
packaging/
  macos/
    distribution.xml                       # productbuild distribution descriptor
    scripts/
      postinstall                          # post-install script (create ~/contextgrabber/ dir, etc.)
    resources/
      welcome.html                        # installer welcome screen (optional)
scripts/
  release/
    stage-macos-artifacts.sh              # build + stage app and CLI
    build-macos-package.sh                # assemble .pkg from staged artifacts
```

## Phase 1: Packaging Contract

Already finalized above. Implementation tasks:

1. Create `VERSION` file at repo root with `0.1.0`
2. Update Go CLI build to read version from `VERSION` file (or accept as argument to build scripts)
3. Document the contract in this file (done)

## Phase 2: Packaging Scripts

### `scripts/release/stage-macos-artifacts.sh`

Purpose: build release artifacts and stage them for packaging.

```bash
#!/usr/bin/env bash
# Builds ContextGrabber.app and cgrab CLI, stages them in a temp directory.
# Usage: scripts/release/stage-macos-artifacts.sh [--version <semver>]
# Output: prints the staging directory path to stdout
```

Steps:
1. Read version from `VERSION` file (or `--version` flag override)
2. Build Swift app: `swift build -c release` from `apps/macos-host/`
3. Create `.app` bundle structure:
   ```
   ContextGrabber.app/
     Contents/
       MacOS/
         ContextGrabberHost    # copied from swift build output
       Info.plist               # generated with version, bundle ID, LSUIElement=1
       Resources/
   ```
4. Build Go CLI: `go build -ldflags "-X github.com/context-grabber/cgrab/cmd.Version=$VERSION" -o cgrab .` from `cgrab/`
5. Stage both into `$STAGING_DIR/`:
   ```
   $STAGING_DIR/
     app/
       ContextGrabber.app/...
     cli/
       cgrab
   ```
6. Print `$STAGING_DIR` path to stdout

### `scripts/release/build-macos-package.sh`

Purpose: build `.pkg` installer from staged artifacts.

```bash
#!/usr/bin/env bash
# Builds a .pkg installer from staged artifacts.
# Usage: scripts/release/build-macos-package.sh <staging-dir> [--output <path>]
# Output: .pkg file at the specified path (default: .tmp/context-grabber-macos-<version>.pkg)
```

Steps:
1. Build app component package:
   ```bash
   pkgbuild \
     --root "$STAGING_DIR/app" \
     --identifier com.contextgrabber.app \
     --version "$VERSION" \
     --install-location /Applications \
     "$WORK_DIR/app.pkg"
   ```
2. Build CLI component package:
   ```bash
   pkgbuild \
     --root "$STAGING_DIR/cli" \
     --identifier com.contextgrabber.cli \
     --version "$VERSION" \
     --install-location /usr/local/bin \
     --scripts packaging/macos/scripts \
     "$WORK_DIR/cli.pkg"
   ```
3. Combine with distribution descriptor:
   ```bash
   productbuild \
     --distribution packaging/macos/distribution.xml \
     --package-path "$WORK_DIR" \
     --resources packaging/macos/resources \
     "$OUTPUT_PATH"
   ```
4. Print output path and file size

### `packaging/macos/distribution.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Context Grabber</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true"/>
    <pkg-ref id="com.contextgrabber.app"/>
    <pkg-ref id="com.contextgrabber.cli"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.contextgrabber.app"/>
            <line choice="com.contextgrabber.cli"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.contextgrabber.app" visible="false">
        <pkg-ref id="com.contextgrabber.app"/>
    </choice>
    <choice id="com.contextgrabber.cli" visible="false">
        <pkg-ref id="com.contextgrabber.cli"/>
    </choice>
    <pkg-ref id="com.contextgrabber.app" version="VERSION" onConclusion="none">app.pkg</pkg-ref>
    <pkg-ref id="com.contextgrabber.cli" version="VERSION" onConclusion="none">cli.pkg</pkg-ref>
</installer-gui-script>
```

### `packaging/macos/scripts/postinstall`

```bash
#!/bin/bash
# Create default CLI storage directory
mkdir -p "$HOME/contextgrabber"
exit 0
```

## Phase 3: Dogfood Testing

### Build the package

```bash
# From repo root:
STAGING_DIR=$(scripts/release/stage-macos-artifacts.sh)
scripts/release/build-macos-package.sh "$STAGING_DIR"
```

### Validation Checklist

| Check | Command | Expected |
| ----- | ------- | -------- |
| Installer runs | `open .tmp/context-grabber-macos-0.1.0.pkg` | macOS installer GUI opens |
| App installed | `ls /Applications/ContextGrabber.app` | App bundle exists |
| CLI installed | `command -v cgrab` | `/usr/local/bin/cgrab` |
| CLI version | `cgrab --version` | `0.1.0` |
| CLI diagnostics | `cgrab doctor` | Reports capabilities |
| CLI list | `cgrab list --tabs` | Enumerates browser tabs |
| Desktop capture | `cgrab capture --app Finder` | Captures Finder via host |
| Browser capture | `cgrab capture --focused` | Captures active tab |
| App launch | Open ContextGrabber.app | Menu bar icon appears |
| Host path resolution | `cgrab doctor --format json \| jq .hostBinary` | Points to installed app |

### Known Issues to Watch

- **Unsigned installer warning**: macOS will show "unidentified developer" warning. Right-click → Open to bypass.
- **Permission grants**: fresh install will need Accessibility/Screen Recording grants for the new binary path at `/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost`
- **Existing install conflict**: if a dev build of `ContextGrabberHost` already has permission grants, the installed `.app` may need separate grants (different binary path)
- **`/usr/local/bin` permissions**: some systems may not have `/usr/local/bin` writable without sudo. The `.pkg` installer handles this via system-level install.

## Deferred

- **Phase 4: Homebrew Cask** — requires a tap repo and hosting the `.pkg` artifact (e.g., GitHub Releases)
- **Phase 5: Release automation** — CI build + smoke test pipeline
- **Phase 6: Signing + notarization** — requires Apple Developer account and certificates
- **Universal binary**: `lipo` to combine arm64 + x86_64 builds (nice-to-have, most users are on Apple Silicon)
