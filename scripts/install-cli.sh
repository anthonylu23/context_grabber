#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install Context Grabber CLI as `cgrab`.

Usage:
  scripts/install-cli.sh [--dest <path>]

Options:
  --dest <path>   Installation directory for cgrab.
                  Default: $(go env GOPATH)/bin
  -h, --help      Show this help text.
EOF
}

expand_path() {
  local raw_path="$1"
  case "$raw_path" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s/%s\n' "$HOME" "${raw_path#~/}"
      ;;
    *)
      printf '%s\n' "$raw_path"
      ;;
  esac
}

if ! command -v go >/dev/null 2>&1; then
  echo "go is required but was not found on PATH." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_DEST="$(go env GOPATH)/bin"
DEST="$DEFAULT_DEST"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --dest" >&2
        exit 1
      fi
      DEST="$(expand_path "$2")"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$DEST"
if [[ ! -d "$DEST" ]]; then
  echo "failed to create destination directory: $DEST" >&2
  exit 1
fi
if [[ ! -w "$DEST" ]]; then
  echo "destination is not writable: $DEST" >&2
  exit 1
fi

DEST="$(cd "$DEST" && pwd)"
echo "[cgrab] building CLI from $REPO_ROOT/cgrab"
(
  cd "$REPO_ROOT/cgrab"
  go build -o "$DEST/cgrab" .
)

echo "[cgrab] installed to $DEST/cgrab"
echo
if [[ ":$PATH:" != *":$DEST:"* ]]; then
  echo "[cgrab] PATH update needed:"
  echo "  export PATH=\"$DEST:\$PATH\""
  echo "Add that to your shell profile (for zsh: ~/.zshrc), then restart your shell."
  echo
fi

echo "[cgrab] verify with:"
echo "  command -v cgrab"
echo "  cgrab --version"
echo "  cgrab doctor --format json"
