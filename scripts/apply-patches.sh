#!/bin/sh
set -eu

usage() {
  cat <<'USAGE'
Usage: scripts/apply-patches.sh [repo-path]

Applies patches listed in patches/series to the upstream repo (default: ./vibe-kanban).

USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_REPO="${1:-${REPO_ROOT}/vibe-kanban}"
SERIES_FILE="${REPO_ROOT}/patches/series"

if [ ! -d "${TARGET_REPO}/.git" ]; then
  echo "Target repo not found or not a git repo: ${TARGET_REPO}"
  exit 1
fi

if [ ! -f "${SERIES_FILE}" ]; then
  echo "Series file not found: ${SERIES_FILE}"
  exit 1
fi

APPLIED=0
while IFS= read -r patch; do
  # Skip empty lines and comments
  case "${patch}" in
    ""|\#*) continue ;;
  esac

  PATCH_PATH="${REPO_ROOT}/patches/${patch}"
  if [ ! -f "${PATCH_PATH}" ]; then
    echo "Patch not found: ${PATCH_PATH}"
    exit 1
  fi
  git -C "${TARGET_REPO}" apply --whitespace=nowarn "${PATCH_PATH}"
  echo "Applied patch: ${patch}"
  APPLIED=1
done < "${SERIES_FILE}"

if [ "${APPLIED}" -eq 0 ]; then
  echo "No patches to apply."
fi
