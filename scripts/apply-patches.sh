#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: scripts/apply-patches.sh [TARGET_SUBMODULE]

Applies patches to the specified Vibe Kanban submodule.

Arguments:
  TARGET_SUBMODULE   Path to submodule (vibe-kanban or vibe-kanban-remote)
                     Default: vibe-kanban

Patch Categories:
  common/    - Applied to both submodules
  frontend/  - Applied only to vibe-kanban/
  remote/    - Applied only to vibe-kanban-remote/

Examples:
  ./scripts/apply-patches.sh vibe-kanban          # Apply frontend patches
  ./scripts/apply-patches.sh vibe-kanban-remote   # Apply remote patches

USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_REPO="${1:-${REPO_ROOT}/vibe-kanban}"

# Determine target name from path
TARGET_NAME="$(basename "${TARGET_REPO}")"

# Validate target repository
if ! git -C "${TARGET_REPO}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: Target repo not found or not a git repo: ${TARGET_REPO}"
  exit 1
fi

# Determine which patch category to use based on target
case "${TARGET_NAME}" in
  vibe-kanban)
    PATCH_CATEGORY="frontend"
    ;;
  vibe-kanban-remote)
    PATCH_CATEGORY="remote"
    ;;
  *)
    echo "Error: Unknown target '${TARGET_NAME}'. Expected 'vibe-kanban' or 'vibe-kanban-remote'"
    exit 1
    ;;
esac

echo "Applying patches to ${TARGET_NAME} (category: ${PATCH_CATEGORY})"

# Function to apply patches from a series file
apply_patch_series() {
  local series_file="$1"
  local patch_dir="$2"
  local category_name="$3"

  if [ ! -f "${series_file}" ]; then
    echo "Warning: Series file not found: ${series_file}"
    return 0
  fi

  local applied=0
  while IFS= read -r patch; do
    # Skip empty lines and comments
    case "${patch}" in
      ""|\#*) continue ;;
    esac

    PATCH_PATH="${patch_dir}/${patch}"
    if [ ! -f "${PATCH_PATH}" ]; then
      echo "Error: Patch not found: ${PATCH_PATH}"
      exit 1
    fi

    echo "  [${category_name}] Applying: ${patch}"
    if ! git -C "${TARGET_REPO}" apply --whitespace=nowarn "${PATCH_PATH}"; then
      echo "Error: Failed to apply patch: ${patch}"
      echo "You may need to resolve conflicts manually or update the patch for the current version."
      exit 1
    fi
    applied=$((applied + 1))
  done < "${series_file}"

  if [ "${applied}" -gt 0 ]; then
    echo "  [${category_name}] Applied ${applied} patch(es)"
  fi
}

# Apply common patches first (if any)
COMMON_SERIES="${REPO_ROOT}/patches/common/series"
COMMON_DIR="${REPO_ROOT}/patches/common"
if [ -f "${COMMON_SERIES}" ]; then
  echo "Step 1/2: Applying common patches..."
  apply_patch_series "${COMMON_SERIES}" "${COMMON_DIR}" "common"
else
  echo "Step 1/2: No common patches to apply"
fi

# Apply category-specific patches
CATEGORY_SERIES="${REPO_ROOT}/patches/${PATCH_CATEGORY}/series"
CATEGORY_DIR="${REPO_ROOT}/patches/${PATCH_CATEGORY}"
if [ -f "${CATEGORY_SERIES}" ]; then
  echo "Step 2/2: Applying ${PATCH_CATEGORY} patches..."
  apply_patch_series "${CATEGORY_SERIES}" "${CATEGORY_DIR}" "${PATCH_CATEGORY}"
else
  echo "Step 2/2: No ${PATCH_CATEGORY} patches to apply"
fi

echo "Patch application complete for ${TARGET_NAME}"
