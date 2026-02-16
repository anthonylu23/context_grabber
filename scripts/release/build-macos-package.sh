#!/usr/bin/env bash
set -euo pipefail

# build-macos-package.sh
# Builds a .pkg installer from staged artifacts.
#
# Usage: scripts/release/build-macos-package.sh <staging-dir> [--output <path>]
# Output: .pkg file at the specified path

usage() {
  cat <<'EOF'
Build a macOS .pkg installer from staged artifacts.

Usage:
  scripts/release/build-macos-package.sh <staging-dir> [--output <path>]

Arguments:
  staging-dir       Directory created by stage-macos-artifacts.sh

Options:
  --output <path>   Output .pkg path (default: .tmp/context-grabber-macos-<version>.pkg)
  -h, --help        Show this help text
EOF
}

log() { echo "[pkg] $*" >&2; }
die() { echo "[pkg] ERROR: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGING_DIR=""
OUTPUT_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -lt 2 ]] && die "missing value for --output"
      OUTPUT_PATH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      die "unknown option: $1" ;;
    *)
      if [[ -z "$STAGING_DIR" ]]; then
        STAGING_DIR="$1"; shift
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
done

[[ -n "$STAGING_DIR" ]]    || die "staging directory is required (first argument)"
[[ -d "$STAGING_DIR" ]]    || die "staging directory does not exist: $STAGING_DIR"
[[ -d "$STAGING_DIR/app" ]] || die "staging directory missing app/: $STAGING_DIR"
[[ -d "$STAGING_DIR/cli" ]] || die "staging directory missing cli/: $STAGING_DIR"

# Validate prerequisites
command -v pkgbuild >/dev/null 2>&1    || die "pkgbuild is required (part of Xcode command line tools)"
command -v productbuild >/dev/null 2>&1 || die "productbuild is required (part of Xcode command line tools)"

# Prevent pkgbuild from including ._* (AppleDouble) resource fork files
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

# Read version from the staged Info.plist
INFO_PLIST="$STAGING_DIR/app/ContextGrabber.app/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || die "Info.plist not found at $INFO_PLIST"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null)" \
  || die "could not read version from Info.plist"
log "version: $VERSION"

# Set output path
if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_DIR="$REPO_ROOT/.tmp"
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_PATH="$OUTPUT_DIR/context-grabber-macos-${VERSION}.pkg"
fi

# Work directory for intermediate packages
WORK_DIR="$(mktemp -d -t context-grabber-pkg)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# Prepare distribution.xml with version substitution
DIST_TEMPLATE="$REPO_ROOT/packaging/macos/distribution.xml"
[[ -f "$DIST_TEMPLATE" ]] || die "distribution.xml not found at $DIST_TEMPLATE"
DIST_XML="$WORK_DIR/distribution.xml"
sed "s/__VERSION__/$VERSION/g" "$DIST_TEMPLATE" > "$DIST_XML"
log "distribution.xml prepared"

# ---------------------------------------------------------------------------
# 1. Build app component package
# ---------------------------------------------------------------------------
log "building app component package..."
pkgbuild \
  --root "$STAGING_DIR/app" \
  --identifier com.contextgrabber.app \
  --version "$VERSION" \
  --install-location /Applications \
  "$WORK_DIR/app.pkg" 2>&1 | while IFS= read -r line; do
  echo "  [pkgbuild] $line" >&2
done
log "app.pkg built"

# ---------------------------------------------------------------------------
# 2. Build CLI component package
# ---------------------------------------------------------------------------
log "building CLI component package..."
SCRIPTS_DIR="$REPO_ROOT/packaging/macos/scripts"
pkgbuild \
  --root "$STAGING_DIR/cli" \
  --identifier com.contextgrabber.cli \
  --version "$VERSION" \
  --install-location /usr/local/bin \
  --scripts "$SCRIPTS_DIR" \
  "$WORK_DIR/cli.pkg" 2>&1 | while IFS= read -r line; do
  echo "  [pkgbuild] $line" >&2
done
log "cli.pkg built"

# ---------------------------------------------------------------------------
# 3. Combine into product archive
# ---------------------------------------------------------------------------
log "building product archive..."
RESOURCES_DIR="$REPO_ROOT/packaging/macos/resources"
PRODUCTBUILD_ARGS=(
  --distribution "$DIST_XML"
  --package-path "$WORK_DIR"
)

if [[ -d "$RESOURCES_DIR" ]]; then
  PRODUCTBUILD_ARGS+=(--resources "$RESOURCES_DIR")
fi

PRODUCTBUILD_ARGS+=("$OUTPUT_PATH")

productbuild "${PRODUCTBUILD_ARGS[@]}" 2>&1 | while IFS= read -r line; do
  echo "  [productbuild] $line" >&2
done

[[ -f "$OUTPUT_PATH" ]] || die "product archive was not created"

# ---------------------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------------------
PKG_SIZE="$(du -h "$OUTPUT_PATH" | awk '{print $1}')"
log ""
log "package built successfully"
log "  path: $OUTPUT_PATH"
log "  size: $PKG_SIZE"
log "  version: $VERSION"
log ""
log "to install (unsigned):"
log "  open \"$OUTPUT_PATH\""
log "  (right-click → Open if Gatekeeper blocks)"
log ""
log "to inspect:"
log "  pkgutil --payload-files \"$OUTPUT_PATH\""

echo "$OUTPUT_PATH"
