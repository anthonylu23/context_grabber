#!/usr/bin/env bash
set -euo pipefail

# stage-macos-artifacts.sh
# Builds ContextGrabber.app and cgrab CLI, stages them for packaging.
#
# Usage: scripts/release/stage-macos-artifacts.sh [--version <semver>]
# Output: prints the staging directory path to stdout (last line)

usage() {
  cat <<'EOF'
Build and stage macOS release artifacts.

Usage:
  scripts/release/stage-macos-artifacts.sh [--version <semver>]

Options:
  --version <semver>  Override version (default: read from VERSION file)
  -h, --help          Show this help text
EOF
}

log() { echo "[stage] $*" >&2; }
die() { echo "[stage] ERROR: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -lt 2 ]] && die "missing value for --version"
      VERSION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# Resolve version
if [[ -z "$VERSION" ]]; then
  VERSION_FILE="$REPO_ROOT/VERSION"
  [[ -f "$VERSION_FILE" ]] || die "VERSION file not found at $VERSION_FILE"
  VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi
[[ -n "$VERSION" ]] || die "version is empty"
log "version: $VERSION"

# Validate prerequisites
command -v swift >/dev/null 2>&1 || die "swift is required"
command -v go >/dev/null 2>&1    || die "go is required"

# Prevent macOS from creating ._* (AppleDouble) resource fork files
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

# Create staging directory
STAGING_DIR="$(mktemp -d -t context-grabber-staging)"
log "staging directory: $STAGING_DIR"

cleanup() {
  if [[ "${STAGE_FAILED:-0}" == "1" ]]; then
    log "cleaning up staging directory after failure"
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT
STAGE_FAILED=1

# ---------------------------------------------------------------------------
# 1. Build Swift app (release)
# ---------------------------------------------------------------------------
log "building Swift app (release)..."
SWIFT_DIR="$REPO_ROOT/apps/macos-host"
swift build -c release --package-path "$SWIFT_DIR" 2>&1 | while IFS= read -r line; do
  echo "  [swift] $line" >&2
done

SWIFT_BIN_PATH="$(swift build -c release --show-bin-path --package-path "$SWIFT_DIR" 2>/dev/null)"
SWIFT_BINARY="$SWIFT_BIN_PATH/ContextGrabberHost"
[[ -f "$SWIFT_BINARY" ]] || die "Swift binary not found at $SWIFT_BINARY"
log "Swift binary: $SWIFT_BINARY"

# SPM resource bundle
RESOURCE_BUNDLE="$SWIFT_BIN_PATH/ContextGrabberHost_ContextGrabberHost.bundle"

# ---------------------------------------------------------------------------
# 2. Create .app bundle
# ---------------------------------------------------------------------------
log "creating .app bundle..."
APP_DIR="$STAGING_DIR/app/ContextGrabber.app"
APP_CONTENTS="$APP_DIR/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"

# Copy binary (strip extended attributes)
ditto --noextattr --norsrc "$SWIFT_BINARY" "$APP_MACOS/ContextGrabberHost"
chmod +x "$APP_MACOS/ContextGrabberHost"

# Copy SPM resource bundle if it exists (use ditto --noextattr to avoid ._* files in pkg)
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  ditto --noextattr --norsrc "$RESOURCE_BUNDLE" "$APP_RESOURCES/$(basename "$RESOURCE_BUNDLE")"
  log "copied resource bundle"
fi

# Generate Info.plist
cat > "$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ContextGrabberHost</string>
    <key>CFBundleIdentifier</key>
    <string>com.contextgrabber.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ContextGrabber</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Context Grabber. All rights reserved.</string>
</dict>
</plist>
PLIST
log "generated Info.plist (version $VERSION)"

# ---------------------------------------------------------------------------
# 3. Build Go CLI
# ---------------------------------------------------------------------------
log "building Go CLI..."
CLI_DIR="$STAGING_DIR/cli"
mkdir -p "$CLI_DIR"

LDFLAGS="-X github.com/anthonylu23/context_grabber/cgrab/cmd.Version=$VERSION"
(
  cd "$REPO_ROOT/cgrab"
  go build -ldflags "$LDFLAGS" -o "$CLI_DIR/cgrab" .
) 2>&1 | while IFS= read -r line; do
  echo "  [go] $line" >&2
done

[[ -f "$CLI_DIR/cgrab" ]] || die "Go CLI binary not found at $CLI_DIR/cgrab"
chmod +x "$CLI_DIR/cgrab"
log "Go CLI built: $CLI_DIR/cgrab"

# ---------------------------------------------------------------------------
# 4. Clean extended attributes + verify staged artifacts
# ---------------------------------------------------------------------------
# Strip extended attributes where possible. Note: com.apple.provenance on
# macOS 15+ cannot be removed by unprivileged processes. pkgbuild will
# serialize these as ._* files in the payload — this is cosmetic and does
# not affect installation behavior.
log "stripping extended attributes..."
find "$STAGING_DIR" -print0 | xargs -0 xattr -c 2>/dev/null || true

log "verifying staged artifacts..."
[[ -f "$APP_MACOS/ContextGrabberHost" ]]  || die "app binary missing"
[[ -f "$APP_CONTENTS/Info.plist" ]]        || die "Info.plist missing"
[[ -f "$CLI_DIR/cgrab" ]]                  || die "CLI binary missing"

# Verify version injection
CLI_VERSION="$("$CLI_DIR/cgrab" --version 2>/dev/null | awk '{print $NF}')" || true
if [[ "$CLI_VERSION" == "$VERSION" ]]; then
  log "CLI version verified: $CLI_VERSION"
else
  log "WARNING: CLI reports version '$CLI_VERSION', expected '$VERSION'"
fi

log "staging complete"
log ""
log "  app:  $APP_DIR"
log "  cli:  $CLI_DIR/cgrab"

STAGE_FAILED=0

# Print staging directory to stdout (consumed by build-macos-package.sh)
echo "$STAGING_DIR"
