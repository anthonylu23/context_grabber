# Distribution + Packaging Implementation Plan

## Goal

Build a working unsigned `.pkg` installer that installs both `ContextGrabber.app` and `cgrab` CLI on macOS. Phases 1-5 are complete: packaging contract, build scripts, dogfood validation, Homebrew Cask, and release automation. Signing/notarization is deferred (Phase 6).

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
- **Go CLI**: inject at build time via `-ldflags "-X github.com/anthonylu23/context_grabber/cgrab/cmd.Version=0.1.0"`
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

## Phase 1: Packaging Contract ✓

Completed. Implementation:

1. Created `VERSION` file at repo root with `0.1.0`
2. Go CLI reads version via `-ldflags "-X github.com/anthonylu23/context_grabber/cgrab/cmd.Version=$VERSION"`
3. Swift app version set via generated `Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`)

## Phase 2: Packaging Scripts ✓

All scripts and metadata files have been created and tested.

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
4. Build Go CLI: `go build -ldflags "-X github.com/anthonylu23/context_grabber/cgrab/cmd.Version=$VERSION" -o cgrab .` from `cgrab/`
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
    <pkg-ref id="com.contextgrabber.app" version="__VERSION__" onConclusion="none">app.pkg</pkg-ref>
    <pkg-ref id="com.contextgrabber.cli" version="__VERSION__" onConclusion="none">cli.pkg</pkg-ref>
</installer-gui-script>
```

### `packaging/macos/scripts/postinstall`

```bash
#!/bin/bash
# Resolve active console user and create CLI storage directory there.
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null)"
if [[ -z "$CONSOLE_USER" || "$CONSOLE_USER" == "root" || "$CONSOLE_USER" == "loginwindow" ]]; then
  exit 0
fi
REAL_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[[ -z "$REAL_HOME" ]] && exit 0
mkdir -p "$REAL_HOME/contextgrabber"
chown "$CONSOLE_USER" "$REAL_HOME/contextgrabber"
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
| Installer runs | `open .tmp/context-grabber-macos-<version>.pkg` | macOS installer GUI opens |
| App installed | `ls /Applications/ContextGrabber.app` | App bundle exists |
| CLI installed | `command -v cgrab` | `/usr/local/bin/cgrab` |
| CLI version | `cgrab --version` | `0.1.0` |
| CLI diagnostics | `cgrab doctor` | Reports capabilities |
| CLI list | `cgrab list --tabs` | Enumerates browser tabs |
| Desktop capture | `cgrab capture --app Finder` | Captures Finder via host |
| Browser capture | `cgrab capture --focused` | Captures active tab |
| App launch | Open ContextGrabber.app | Menu bar icon appears |
| Host path resolution | `cgrab doctor --format json \| jq .hostBinaryPath` | Points to installed app |

### Known Issues to Watch

- **Unsigned installer warning**: macOS will show "unidentified developer" warning. Right-click → Open to bypass.
- **Permission grants**: fresh install will need Accessibility/Screen Recording grants for the new binary path at `/Applications/ContextGrabber.app/Contents/MacOS/ContextGrabberHost`
- **Existing install conflict**: if a dev build of `ContextGrabberHost` already has permission grants, the installed `.app` may need separate grants (different binary path)
- **`/usr/local/bin` permissions**: some systems may not have `/usr/local/bin` writable without sudo. The `.pkg` installer handles this via system-level install.
- **AppleDouble payload noise on newer macOS**: `com.apple.provenance` xattrs can still materialize as `._*` entries in pkg payloads. Current impact is cosmetic.

## Phase 4: Homebrew Cask ✓

Completed. Implementation:

1. Created GitHub Release `v0.1.0` with `.pkg` asset
2. Created Homebrew tap repo: `anthonylu23/homebrew-context-grabber`
3. Cask formula: `Casks/context-grabber.rb` (passes `brew style` and `brew audit`)
4. Install: `brew tap anthonylu23/context-grabber && brew install --cask context-grabber`
5. Uninstall: `brew uninstall --cask context-grabber`

## Phase 5: Release Automation ✓

Completed. Implementation:

1. Created `.github/workflows/release.yml` — tag-triggered release workflow:
   - Triggers on `v*` tags pushed to the repo
   - Validates tag version matches `VERSION` file (prevents drift)
   - Runs on `macos-15` runner (required for `swift build`, `pkgbuild`, `productbuild`)
   - Calls existing `stage-macos-artifacts.sh` and `build-macos-package.sh` scripts
   - Smoke tests: package payload structure, CLI version injection, Info.plist fields, binary architecture, postinstall user/home resolution
   - Computes SHA256 checksum and includes it in release notes
   - Creates GitHub Release with install instructions and asset upload via `gh release create`

### Release Flow

```
git tag v0.2.0 && git push origin v0.2.0
  → release.yml triggers
  → validates VERSION file = 0.2.0
  → builds Swift app + Go CLI
  → stages + packages .pkg
  → runs smoke tests (payload, version, plist, arch)
  → creates GitHub Release with .pkg + SHA256
```

### Smoke Tests

| Test | Validates |
|------|-----------|
| Package payload structure | `ContextGrabberHost`, `Info.plist`, `cgrab` all present in `.pkg` |
| CLI version injection | Staged `cgrab --version` matches `VERSION` file |
| Info.plist fields | `CFBundleShortVersionString`, `CFBundleIdentifier`, `LSUIElement` correct |
| Binary architecture | App binary is Mach-O executable |

### Release Checklist (Manual)

Before tagging a release:
1. Update `VERSION` file to new semver
2. Commit the version bump
3. Tag: `git tag v<version>`
4. Push: `git push origin v<version>`
5. After release: update Homebrew cask SHA256 in `anthonylu23/homebrew-context-grabber`

## Deferred

- **Phase 6: Signing + notarization** — requires Apple Developer account and certificates
- **Universal binary**: `lipo` to combine arm64 + x86_64 builds (nice-to-have, most users are on Apple Silicon)
- **Homebrew cask auto-update**: auto-PR to tap repo with new SHA256 on release (requires a separate GH Action or script)
