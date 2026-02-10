#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIBE_DIR="${ROOT_DIR}/vibe-kanban"
SERIES_FILE="${ROOT_DIR}/patches/series"

# Optional local credentials file (intentionally gitignored).
# If present, it should export NPM_TOKEN/R2_* and other required env vars.
CREDENTIALS_FILE="${ROOT_DIR}/scripts/publish-credentials.bashrc"
if [ -f "${CREDENTIALS_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${CREDENTIALS_FILE}"
fi

PATCHES_APPLIED=0
TMP_DIR=""
DOWNLOAD_JS_BAK=""
PKG_JSON_BAK=""
README_BAK=""
NPMRC_BAK=""

cleanup() {
  set +e

  if [ -n "${DOWNLOAD_JS_BAK}" ] && [ -f "${DOWNLOAD_JS_BAK}" ]; then
    cp "${DOWNLOAD_JS_BAK}" "${VIBE_DIR}/npx-cli/bin/download.js"
  fi
  if [ -n "${PKG_JSON_BAK}" ] && [ -f "${PKG_JSON_BAK}" ]; then
    cp "${PKG_JSON_BAK}" "${VIBE_DIR}/npx-cli/package.json"
  fi
  if [ -n "${README_BAK}" ] && [ -f "${README_BAK}" ]; then
    cp "${README_BAK}" "${VIBE_DIR}/npx-cli/README.md"
  fi

  if [ -n "${NPMRC_BAK}" ] && [ -f "${NPMRC_BAK}" ]; then
    rm -f "${NPMRC_BAK}"
  fi

  if [ "${PATCHES_APPLIED}" -eq 1 ]; then
    if [ -f "${SERIES_FILE}" ]; then
      PATCH_LIST=()
      while IFS= read -r patch_line; do
        PATCH_LIST+=("${patch_line}")
      done < <(grep -v '^[[:space:]]*$' "${SERIES_FILE}" | grep -v '^[[:space:]]*#')

      for ((idx=${#PATCH_LIST[@]}-1; idx>=0; idx--)); do
        PATCH_PATH="${ROOT_DIR}/patches/${PATCH_LIST[$idx]}"
        if [ -f "${PATCH_PATH}" ]; then
          git -C "${VIBE_DIR}" apply -R "${PATCH_PATH}" >/dev/null 2>&1 || true
        fi
      done
    fi
  fi

  if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
    rm -rf "${TMP_DIR}"
  fi
}

trap cleanup EXIT

log() {
  printf '[publish] %s\n' "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

NODE_CMD="node"
PY_CMD="python3"

detect_runtime_cmds() {
  if ! have_cmd node && have_cmd nodejs; then
    NODE_CMD="nodejs"
  fi
  if ! have_cmd python3 && have_cmd python; then
    PY_CMD="python"
  fi
}

if [ "$(uname -s)" != "Darwin" ]; then
  die "This script must be run on macOS."
fi

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if have_cmd sudo; then
    SUDO="sudo"
  fi
fi

BREW_UPDATED=0

brew_update() {
  if [ "${BREW_UPDATED}" -eq 1 ]; then
    return
  fi
  brew update
  BREW_UPDATED=1
}

brew_install_formula() {
  local formula="$1"
  if brew list --formula "${formula}" >/dev/null 2>&1; then
    return
  fi
  brew_update
  brew install "${formula}"
}

ensure_system_packages() {
  if [ "${SKIP_SYSTEM_DEPS:-0}" = "1" ]; then
    log "Skipping system dependency installation due to SKIP_SYSTEM_DEPS=1."
    return
  fi

  local missing=0
  local required_cmds=(git curl zip npm)
  for cmd in "${required_cmds[@]}"; do
    if ! have_cmd "${cmd}"; then
      missing=1
      break
    fi
  done

  if (! have_cmd node && ! have_cmd nodejs) || (! have_cmd python3 && ! have_cmd python); then
    missing=1
  fi

  if ! have_cmd cmake || ! have_cmd pkg-config || ! have_cmd make || (! have_cmd gcc && ! have_cmd clang); then
    missing=1
  fi

  if [ "${missing}" -eq 0 ]; then
    return
  fi

  if ! have_cmd brew; then
    die "Missing dependencies and Homebrew is not available. Install deps manually or set SKIP_SYSTEM_DEPS=1."
  fi

  if ! xcode-select -p >/dev/null 2>&1; then
    die "Xcode Command Line Tools are required. Run: xcode-select --install"
  fi

  log "Installing system build dependencies via Homebrew..."

  if ! have_cmd git; then
    brew_install_formula git
  fi
  if ! have_cmd curl; then
    brew_install_formula curl
  fi
  if ! have_cmd zip; then
    brew_install_formula zip
  fi
  if (! have_cmd node && ! have_cmd nodejs) || ! have_cmd npm; then
    brew_install_formula node
  fi
  if (! have_cmd python3 && ! have_cmd python); then
    brew_install_formula python
  fi
  if ! have_cmd cmake; then
    brew_install_formula cmake
  fi
  if ! have_cmd pkg-config; then
    brew_install_formula pkg-config
  fi

  if ! have_cmd make || (! have_cmd gcc && ! have_cmd clang); then
    die "C/C++ toolchain still missing after dependency install. Ensure Xcode Command Line Tools are installed."
  fi
}

ensure_rustup() {
  if have_cmd rustup; then
    if [ -f "${HOME}/.cargo/env" ]; then
      # shellcheck disable=SC1090
      source "${HOME}/.cargo/env"
    fi
    return
  fi

  if ! have_cmd curl; then
    die "curl is required to install rustup."
  fi

  log "Installing Rust via rustup..."
  curl -sSf https://sh.rustup.rs | sh -s -- -y
  if [ -f "${HOME}/.cargo/env" ]; then
    # shellcheck disable=SC1090
    source "${HOME}/.cargo/env"
  fi
  export PATH="${HOME}/.cargo/bin:${PATH}"
}

ensure_pnpm() {
  if have_cmd pnpm; then
    return
  fi

  if have_cmd corepack; then
    log "Installing pnpm via corepack..."
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@latest --activate
  elif have_cmd npm; then
    log "Installing pnpm via npm..."
    if [ -n "${SUDO}" ]; then
      ${SUDO} npm install -g pnpm
    else
      npm install -g pnpm || {
        npm config set prefix "${HOME}/.local"
        npm install -g pnpm
      }
      export PATH="${HOME}/.local/bin:${PATH}"
    fi
  else
    die "pnpm not available and npm is missing."
  fi
}

ensure_awscli() {
  if have_cmd aws; then
    return
  fi

  if have_cmd brew; then
    log "Installing awscli via Homebrew..."
    brew_install_formula awscli
    return
  fi

  detect_runtime_cmds
  if have_cmd "${PY_CMD}"; then
    log "Installing awscli via pip..."
    "${PY_CMD}" -m pip install --user --upgrade awscli
    export PATH="${HOME}/.local/bin:${PATH}"
  else
    die "python is required to install awscli."
  fi
}

ensure_prereqs() {
  ensure_system_packages
  detect_runtime_cmds
  ensure_rustup
  ensure_pnpm
  ensure_awscli
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Missing required command: $1"
  fi
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: ${name}"
    exit 1
  fi
}

ensure_prereqs

require_cmd git
require_cmd "${NODE_CMD}"
require_cmd npm
require_cmd pnpm
require_cmd cargo
require_cmd rustc
require_cmd zip
require_cmd aws

require_env R2_ACCESS_KEY_ID
require_env R2_SECRET_ACCESS_KEY
require_env R2_ENDPOINT
require_env R2_BUCKET
require_env R2_PUBLIC_URL
require_env VITE_PUBLIC_REACT_VIRTUOSO_LICENSE_KEY

if [ ! -e "${VIBE_DIR}/.git" ]; then
  echo "Missing submodule repo at ${VIBE_DIR}"
  exit 1
fi

if [ -n "$(git -C "${VIBE_DIR}" status -s)" ]; then
  echo "Submodule has uncommitted changes. Please clean it before running this script."
  exit 1
fi

if [ ! -f "${SERIES_FILE}" ]; then
  echo "Patch series file not found: ${SERIES_FILE}"
  exit 1
fi

echo "Applying downstream patches..."
"${ROOT_DIR}/scripts/apply-patches.sh"
PATCHES_APPLIED=1

RELEASE_TAG="${RELEASE_TAG:-}"
# Publishing controls:
# - NPM_TAG: npm dist-tag to publish under (default: latest)
# - NPM_VERSION: override npm package version (semver). If set, RELEASE_TAG defaults to v${NPM_VERSION}.
# - RELEASE_TAG: override binary tag (R2 path + embedded in download.js). If set, VERSION defaults to ${RELEASE_TAG#v}.
# - RELEASE_TAG_MODE: "timestamp" (default) or "git". "git" uses latest upstream git tag v* if present.
# - BASE_VERSION_OVERRIDE: overrides base version used when auto-generating timestamp release tags.
NPM_TAG="${NPM_TAG:-latest}"
NPM_VERSION="${NPM_VERSION:-}"
RELEASE_TAG_MODE="${RELEASE_TAG_MODE:-timestamp}"
BASE_VERSION_OVERRIDE="${BASE_VERSION_OVERRIDE:-}"

if [[ "${NPM_VERSION}" == v* ]]; then
  die "NPM_VERSION should not include a leading 'v' (got: ${NPM_VERSION}). Use e.g. 0.1.8-20260210120000."
fi

if [ -n "${NPM_VERSION}" ] && [ -n "${RELEASE_TAG}" ]; then
  if [ "${RELEASE_TAG#v}" != "${NPM_VERSION}" ] && [ "${RELEASE_TAG}" != "${NPM_VERSION}" ]; then
    die "NPM_VERSION (${NPM_VERSION}) does not match RELEASE_TAG (${RELEASE_TAG}). Either set one, or make them consistent."
  fi
fi

if [ -z "${RELEASE_TAG}" ]; then
  if [ -n "${NPM_VERSION}" ]; then
    RELEASE_TAG="v${NPM_VERSION}"
  else
    case "${RELEASE_TAG_MODE}" in
      git)
        RELEASE_TAG="$(git -C "${VIBE_DIR}" tag -l 'v[0-9]*' --sort=creatordate | tail -n 1)"
        ;;
      timestamp)
        RELEASE_TAG=""
        ;;
      *)
        die "Invalid RELEASE_TAG_MODE: ${RELEASE_TAG_MODE}. Expected 'timestamp' or 'git'."
        ;;
    esac

    if [ -z "${RELEASE_TAG}" ]; then
      if [ -n "${BASE_VERSION_OVERRIDE}" ]; then
        BASE_VERSION="${BASE_VERSION_OVERRIDE}"
      else
        BASE_VERSION="$(${NODE_CMD} -p "require('${VIBE_DIR}/package.json').version")"
      fi
      RELEASE_TAG="v${BASE_VERSION}-$(date +%Y%m%d%H%M%S)"
    fi
  fi
fi

VERSION="${NPM_VERSION:-${RELEASE_TAG#v}}"

echo "Using release tag: ${RELEASE_TAG}"
echo "Using npm version: ${VERSION}"
echo "Using npm dist-tag: ${NPM_TAG}"

TMP_DIR="$(mktemp -d)"
DOWNLOAD_JS_BAK="${TMP_DIR}/download.js.bak"
PKG_JSON_BAK="${TMP_DIR}/package.json.bak"
README_BAK="${TMP_DIR}/README.md.bak"

cp "${VIBE_DIR}/npx-cli/bin/download.js" "${DOWNLOAD_JS_BAK}"
cp "${VIBE_DIR}/npx-cli/package.json" "${PKG_JSON_BAK}"
cp "${VIBE_DIR}/npx-cli/README.md" "${README_BAK}"

${NODE_CMD} -e "
  const fs = require('fs');
  const path = '${VIBE_DIR}/npx-cli/package.json';
  const pkg = JSON.parse(fs.readFileSync(path, 'utf8'));
  pkg.name = '@iamriajul/vibe-kanban-fork';
  pkg.version = '${VERSION}';
  pkg.publishConfig = { access: 'public' };
  pkg.author = 'iamriajul';
  pkg.repository = { type: 'git', url: 'https://github.com/iamriajul/vibe-kanban' };
  fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + '\\n');
"

sed -i '' "s/npx vibe-kanban/npx @iamriajul\\/vibe-kanban-fork/g" "${VIBE_DIR}/npx-cli/README.md"

echo "Installing dependencies..."
(cd "${VIBE_DIR}" && pnpm install)

echo "Building frontend..."
(cd "${VIBE_DIR}/frontend" && pnpm run build)

HOST_TRIPLE="$(rustc -vV | awk '/host/ {print $2}')"
case "${HOST_TRIPLE}" in
  *apple-darwin)
    ;;
  *)
    die "Rust host target '${HOST_TRIPLE}' is not macOS. Run this script on a macOS host."
    ;;
esac

TARGET_TRIPLE="${MACOS_TARGET:-${HOST_TRIPLE}}"
if [ "${TARGET_TRIPLE}" != "${HOST_TRIPLE}" ]; then
  echo "Adding Rust target ${TARGET_TRIPLE}..."
  rustup target add "${TARGET_TRIPLE}"
fi

echo "Building backend binaries for ${TARGET_TRIPLE}..."
if [ "${TARGET_TRIPLE}" = "${HOST_TRIPLE}" ]; then
  (cd "${VIBE_DIR}" && cargo build --release --bin server --bin mcp_task_server --bin review)
  TARGET_DIR="${VIBE_DIR}/target/release"
else
  (cd "${VIBE_DIR}" && cargo build --release --target "${TARGET_TRIPLE}" --bin server --bin mcp_task_server --bin review)
  TARGET_DIR="${VIBE_DIR}/target/${TARGET_TRIPLE}/release"
fi

if [ ! -f "${TARGET_DIR}/server" ]; then
  echo "Expected binary not found at ${TARGET_DIR}/server"
  exit 1
fi

case "${TARGET_TRIPLE}" in
  x86_64-apple-darwin)
    PLATFORM_DIR="macos-x64"
    ;;
  aarch64-apple-darwin|arm64-apple-darwin)
    PLATFORM_DIR="macos-arm64"
    ;;
  *)
    die "Unsupported macOS target triple: ${TARGET_TRIPLE}. Supported: x86_64-apple-darwin, aarch64-apple-darwin"
    ;;
esac

DIST_DIR="${VIBE_DIR}/npx-cli/dist/${PLATFORM_DIR}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

echo "Packaging binaries..."
WORK_DIR="$(mktemp -d)"

cp "${TARGET_DIR}/server" "${WORK_DIR}/vibe-kanban"
zip -j "${DIST_DIR}/vibe-kanban.zip" "${WORK_DIR}/vibe-kanban" >/dev/null

cp "${TARGET_DIR}/mcp_task_server" "${WORK_DIR}/vibe-kanban-mcp"
zip -j "${DIST_DIR}/vibe-kanban-mcp.zip" "${WORK_DIR}/vibe-kanban-mcp" >/dev/null

cp "${TARGET_DIR}/review" "${WORK_DIR}/vibe-kanban-review"
zip -j "${DIST_DIR}/vibe-kanban-review.zip" "${WORK_DIR}/vibe-kanban-review" >/dev/null

rm -rf "${WORK_DIR}"

echo "Generating manifest..."
PLATFORM_MANIFEST_PATH="${TMP_DIR}/platform-manifest.json"
MANIFEST_PATH="${TMP_DIR}/version-manifest.json"
${NODE_CMD} -e "
  const fs = require('fs');
  const crypto = require('crypto');
  const tag = '${RELEASE_TAG}';
  const platform = '${PLATFORM_DIR}';
  const binaries = ['vibe-kanban', 'vibe-kanban-mcp', 'vibe-kanban-review'];
  const manifest = { version: tag, platforms: { [platform]: {} } };
  for (const bin of binaries) {
    const zipPath = '${DIST_DIR}/' + bin + '.zip';
    if (!fs.existsSync(zipPath)) continue;
    const data = fs.readFileSync(zipPath);
    manifest.platforms[platform][bin] = {
      sha256: crypto.createHash('sha256').update(data).digest('hex'),
      size: data.length,
    };
  }
  fs.writeFileSync('${PLATFORM_MANIFEST_PATH}', JSON.stringify(manifest, null, 2));
"

echo "Uploading to R2..."
export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="${R2_REGION:-auto}"
export AWS_EC2_METADATA_DISABLED=true

EXISTING_MANIFEST_PATH="${TMP_DIR}/existing-manifest.json"
if aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
  "s3://${R2_BUCKET}/binaries/${RELEASE_TAG}/manifest.json" \
  "${EXISTING_MANIFEST_PATH}" >/dev/null 2>&1; then
  echo "Merging with existing manifest for ${RELEASE_TAG}..."
else
  rm -f "${EXISTING_MANIFEST_PATH}"
fi

${NODE_CMD} -e "
  const fs = require('fs');
  const outPath = '${MANIFEST_PATH}';
  const platformPath = '${PLATFORM_MANIFEST_PATH}';
  const existingPath = '${EXISTING_MANIFEST_PATH}';

  const merged = { version: '${RELEASE_TAG}', platforms: {} };
  if (fs.existsSync(existingPath)) {
    try {
      const existing = JSON.parse(fs.readFileSync(existingPath, 'utf8'));
      if (existing && typeof existing === 'object' && existing.platforms && typeof existing.platforms === 'object') {
        merged.platforms = existing.platforms;
      }
    } catch {}
  }

  const platformManifest = JSON.parse(fs.readFileSync(platformPath, 'utf8'));
  merged.version = '${RELEASE_TAG}';
  merged.platforms['${PLATFORM_DIR}'] = platformManifest.platforms?.['${PLATFORM_DIR}'] || {};

  fs.writeFileSync(outPath, JSON.stringify(merged, null, 2));
"

for bin in vibe-kanban vibe-kanban-mcp vibe-kanban-review; do
  ZIP_PATH="${DIST_DIR}/${bin}.zip"
  if [ -f "${ZIP_PATH}" ]; then
    aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
      "${ZIP_PATH}" \
      "s3://${R2_BUCKET}/binaries/${RELEASE_TAG}/${PLATFORM_DIR}/${bin}.zip"
  fi
done

aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
  "${MANIFEST_PATH}" \
  "s3://${R2_BUCKET}/binaries/${RELEASE_TAG}/manifest.json" \
  --content-type "application/json"

echo "{\"latest\": \"${VERSION}\"}" | aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
  - "s3://${R2_BUCKET}/binaries/manifest.json" \
  --content-type "application/json"

echo "Injecting R2 URL and tag into download.js..."
${NODE_CMD} -e "
  const fs = require('fs');
  const path = '${VIBE_DIR}/npx-cli/bin/download.js';
  let data = fs.readFileSync(path, 'utf8');
  data = data.replace(/__R2_PUBLIC_URL__/g, '${R2_PUBLIC_URL}');
  data = data.replace(/__BINARY_TAG__/g, '${RELEASE_TAG}');
  fs.writeFileSync(path, data);
"

echo "Removing local dist artifacts before npm publish..."
rm -rf "${VIBE_DIR}/npx-cli/dist"

echo "Publishing to npm..."
if [ -n "${NPM_TOKEN:-}" ]; then
  NPMRC_BAK="${TMP_DIR}/.npmrc"
  umask 077
  printf "//registry.npmjs.org/:_authToken=%s\n" "${NPM_TOKEN}" > "${NPMRC_BAK}"
fi

if (cd "${VIBE_DIR}/npx-cli" && npm view "@iamriajul/vibe-kanban-fork@${VERSION}" version >/dev/null 2>&1); then
  echo "npm version ${VERSION} already exists; skipping publish."
else
  echo "Publishing to npm with dist-tag: ${NPM_TAG}"
  if [ -n "${NPMRC_BAK}" ]; then
    (cd "${VIBE_DIR}/npx-cli" && NPM_CONFIG_USERCONFIG="${NPMRC_BAK}" npm publish --ignore-scripts --access public --tag "${NPM_TAG}")
  else
    if ! (cd "${VIBE_DIR}/npx-cli" && npm whoami >/dev/null 2>&1); then
      die "NPM_TOKEN is not set and npm is not logged in. Set NPM_TOKEN (recommended) or run: npm login"
    fi
    (cd "${VIBE_DIR}/npx-cli" && npm publish --ignore-scripts --access public --tag "${NPM_TAG}")
  fi
fi

echo "Publish complete."
