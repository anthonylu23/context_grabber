#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${CONTEXT_GRABBER_SAFARI_APP_NAME:-ContextGrabberSafari}"
PROJECT_PATH="$REPO_ROOT/apps/safari-container/$APP_NAME/$APP_NAME.xcodeproj"
CONFIGURATION="${CONTEXT_GRABBER_SAFARI_CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${CONTEXT_GRABBER_SAFARI_DERIVED_DATA:-/tmp/context-grabber-safari-container-dd}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required but was not found on PATH." >&2
  exit 1
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Safari container project not found at: $PROJECT_PATH" >&2
  echo "Run 'bun run safari:container:sync' first." >&2
  exit 1
fi

echo "[safari-container] building $PROJECT_PATH"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[safari-container] build succeeded"
