#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/update-vibe-kanban-remote.sh <tag-or-commit>

Updates the vibe-kanban-remote/ submodule to the specified version.
This submodule is used for remote server Docker image builds.

The vibe-kanban/ submodule (for NPM packages) remains unchanged.

Examples:
  scripts/update-vibe-kanban-remote.sh v0.1.18
  scripts/update-vibe-kanban-remote.sh v0.1.20-20260222120000
  scripts/update-vibe-kanban-remote.sh 3a088ff6f705900a8bb2ab29eade7bbf9f5bf76c

After running this script:
  1. Re-apply patches: ./scripts/apply-patches.sh vibe-kanban-remote
  2. Test the changes
  3. Commit: git commit -m "chore: upgrade remote server to <version>"
  4. Tag: git tag remote-v<version>
  5. Push: git push origin remote-v<version>

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
SUBMODULE_PATH="${REPO_ROOT}/vibe-kanban-remote"

if [ ! -d "${SUBMODULE_PATH}/.git" ]; then
  echo "Error: Submodule not initialized at ${SUBMODULE_PATH}"
  echo "Run: git submodule update --init vibe-kanban-remote"
  exit 1
fi

echo "Updating vibe-kanban-remote/ submodule to ${TARGET}..."

git -C "${SUBMODULE_PATH}" fetch --tags origin
git -C "${SUBMODULE_PATH}" checkout "${TARGET}"

git -C "${REPO_ROOT}" add vibe-kanban-remote

echo ""
echo "✓ Updated vibe-kanban-remote/ submodule to ${TARGET}"
echo ""
echo "Next steps:"
echo "  1. Re-apply patches:"
echo "     ./scripts/apply-patches.sh vibe-kanban-remote"
echo ""
echo "  2. Review changes:"
echo "     git status"
echo "     git diff --cached vibe-kanban-remote"
echo ""
echo "  3. Commit the update:"
echo "     git commit -m \"chore: upgrade remote server to ${TARGET}\""
echo ""
echo "  4. Create a release tag:"
echo "     git tag remote-v0.1.XX"  # Replace XX with version number
echo ""
echo "  5. Push to trigger CI/CD:"
echo "     git push origin remote-v0.1.XX"
echo ""
echo "Note: The vibe-kanban/ submodule (NPM package) remains unchanged."
