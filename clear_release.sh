#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
RELEASE_DIR="${ROOT_DIR}/release"

clear_dir() {
  local dir="$1"

  if [[ -d "${dir}" ]]; then
    find "${dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    echo "Cleared: ${dir}"
  else
    mkdir -p "${dir}"
    echo "Created empty release directory: ${dir}"
  fi
}

clear_dir "${DIST_DIR}"
clear_dir "${RELEASE_DIR}"
