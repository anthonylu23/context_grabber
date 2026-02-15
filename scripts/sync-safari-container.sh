#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAFARI_EXTENSION_DIR="$REPO_ROOT/packages/extension-safari"
CONTAINER_PROJECT_ROOT="$REPO_ROOT/apps/safari-container"
TMP_BUNDLE_DIR="${CONTEXT_GRABBER_SAFARI_TMP_BUNDLE_DIR:-/tmp/context-grabber-safari-web-extension-bundle}"
APP_NAME="${CONTEXT_GRABBER_SAFARI_APP_NAME:-ContextGrabberSafari}"
BUNDLE_ID="${CONTEXT_GRABBER_SAFARI_BUNDLE_ID:-com.contextgrabber.ContextGrabberSafari}"
ICONS_DIR="$SAFARI_EXTENSION_DIR/assets/icons"

if ! command -v bun >/dev/null 2>&1; then
  echo "bun is required but was not found on PATH." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required but was not found on PATH." >&2
  exit 1
fi

echo "[safari-container] building Safari extension runtime artifacts"
bun run --cwd "$SAFARI_EXTENSION_DIR" build

echo "[safari-container] preparing temporary WebExtension bundle at: $TMP_BUNDLE_DIR"
rm -rf "$TMP_BUNDLE_DIR"
mkdir -p "$TMP_BUNDLE_DIR"
cp "$SAFARI_EXTENSION_DIR/manifest.json" "$TMP_BUNDLE_DIR/manifest.json"
cp -R "$SAFARI_EXTENSION_DIR/dist" "$TMP_BUNDLE_DIR/dist"

if [[ ! -d "$ICONS_DIR" ]]; then
  echo "Expected icons directory was not found: $ICONS_DIR" >&2
  exit 1
fi

for icon_name in icon-16.png icon-32.png icon-48.png icon-64.png icon-128.png; do
  if [[ ! -f "$ICONS_DIR/$icon_name" ]]; then
    echo "Expected icon file was not found: $ICONS_DIR/$icon_name" >&2
    exit 1
  fi
done

cp -R "$ICONS_DIR" "$TMP_BUNDLE_DIR/icons"

echo "[safari-container] generating Xcode project at: $CONTAINER_PROJECT_ROOT"
xcrun safari-web-extension-converter "$TMP_BUNDLE_DIR" \
  --project-location "$CONTAINER_PROJECT_ROOT" \
  --app-name "$APP_NAME" \
  --bundle-identifier "$BUNDLE_ID" \
  --swift \
  --macos-only \
  --copy-resources \
  --no-open \
  --no-prompt \
  --force

echo "[safari-container] done"
echo "[safari-container] open: $CONTAINER_PROJECT_ROOT/$APP_NAME/$APP_NAME.xcodeproj"
