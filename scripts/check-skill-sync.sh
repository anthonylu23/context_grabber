#!/usr/bin/env bash
# Verify that all skill file copies match the canonical source.
#
# Canonical source: packages/agent-skills/skill/
# Copies that must match:
#   - cgrab/internal/skills/          (go:embed for CLI fallback)
#   - skills/context-grabber/         (skills.sh ecosystem discovery)
#
# This script should be run in CI to prevent drift between copies.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL="$REPO_ROOT/packages/agent-skills/skill"
EMBEDDED="$REPO_ROOT/cgrab/internal/skills"
SKILLSSH="$REPO_ROOT/skills/context-grabber"

FILES=(
  "SKILL.md"
  "references/cli-reference.md"
  "references/output-schema.md"
  "references/workflows.md"
)

failed=0

check_copy() {
  local label="$1"
  local copy_dir="$2"

  if [ ! -d "$copy_dir" ]; then
    echo "ERROR: $label directory not found: $copy_dir"
    failed=1
    return
  fi

  for file in "${FILES[@]}"; do
    canonical_file="$CANONICAL/$file"
    copy_file="$copy_dir/$file"

    if [ ! -f "$canonical_file" ]; then
      echo "MISSING: canonical file $canonical_file"
      failed=1
      continue
    fi

    if [ ! -f "$copy_file" ]; then
      echo "MISSING: $label file $copy_file"
      failed=1
      continue
    fi

    if ! diff -q "$canonical_file" "$copy_file" > /dev/null 2>&1; then
      echo "DRIFT: $file differs between canonical and $label"
      diff --unified=3 "$canonical_file" "$copy_file" || true
      failed=1
    fi
  done
}

# Verify canonical source exists.
if [ ! -d "$CANONICAL" ]; then
  echo "ERROR: canonical skill directory not found: $CANONICAL"
  exit 1
fi

# Check each copy against canonical.
check_copy "go:embed" "$EMBEDDED"
check_copy "skills.sh" "$SKILLSSH"

if [ "$failed" -eq 0 ]; then
  echo "OK: all skill file copies match canonical source"
else
  echo ""
  echo "FAILED: skill file copies are out of sync with canonical source"
  echo "Canonical: packages/agent-skills/skill/"
  echo "Fix: copy canonical files to cgrab/internal/skills/ and skills/context-grabber/"
  exit 1
fi
