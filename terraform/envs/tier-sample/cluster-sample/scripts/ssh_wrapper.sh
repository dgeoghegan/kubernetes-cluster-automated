#!/usr/bin/env bash
set -euo pipefail

# Find repo root no matter where this env lives
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${REPO_ROOT}" ]; then
  echo "Error: not inside a git repo; cannot locate docker/ scripts." >&2
  exit 1
fi

ENV_ROOT=$(realpath "$(pwd)/../")

# Call the real menu, passing the root of the current cluster environment
exec "${REPO_ROOT}/docker/ssh_menu.sh" "$ENV_ROOT"

