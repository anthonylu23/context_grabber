#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-check}"
PACKAGES=()
for package_dir in packages/*; do
  if [[ -d "${package_dir}" && -f "${package_dir}/package.json" ]]; then
    PACKAGES+=("${package_dir}")
  fi
done

if [[ "${#PACKAGES[@]}" -eq 0 ]]; then
  echo "No workspace packages found under packages/." >&2
  exit 1
fi

run_for_packages() {
  local script_name="$1"

  for package_dir in "${PACKAGES[@]}"; do
    echo "==> ${script_name} :: ${package_dir}"
    bun run --cwd "${package_dir}" "${script_name}"
  done
}

case "${ACTION}" in
  typecheck)
    run_for_packages typecheck
    ;;
  test)
    run_for_packages test
    ;;
  check)
    bun run lint
    run_for_packages typecheck
    run_for_packages test
    ;;
  *)
    echo "Unknown action: ${ACTION}" >&2
    echo "Usage: $0 [typecheck|test|check]" >&2
    exit 1
    ;;
esac
