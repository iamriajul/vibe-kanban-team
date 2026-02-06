#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/update-vibe-kanban.sh <tag-or-commit>

Examples:
  scripts/update-vibe-kanban.sh v1.4.0
  scripts/update-vibe-kanban.sh 3a088ff6f705900a8bb2ab29eade7bbf9f5bf76c
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

TARGET="${1:-}"
if [ -z "${TARGET}" ]; then
  usage
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -d "${REPO_ROOT}/vibe-kanban/.git" ]; then
  echo "Submodule not initialized. Run: git submodule update --init --recursive"
  exit 1
fi

git -C "${REPO_ROOT}/vibe-kanban" fetch --tags origin
git -C "${REPO_ROOT}/vibe-kanban" checkout "${TARGET}"

git -C "${REPO_ROOT}" add vibe-kanban

echo "Updated submodule to ${TARGET}."
echo "Next:"
echo "  git status"
echo "  git commit -m \"chore: bump vibe-kanban to ${TARGET}\""
echo "  git push"
echo "Then wait for CI to build the image and deploy using scripts/deploy.sh <commit-sha>."
