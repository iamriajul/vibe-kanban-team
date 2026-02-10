#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIBE_DIR="${ROOT_DIR}/vibe-kanban"
SERIES_FILE="${ROOT_DIR}/patches/series"

source "${ROOT_DIR}/scripts/publish-credentials.bashrc"

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
      mapfile -t PATCH_LIST < <(grep -v '^[[:space:]]*$' "${SERIES_FILE}" | grep -v '^[[:space:]]*#')
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

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if have_cmd sudo; then
    SUDO="sudo"
  fi
fi

PKG_MANAGER=""
PKG_UPDATED=0

detect_pkg_manager() {
  if have_cmd apt-get; then
    echo "apt"
  elif have_cmd dnf; then
    echo "dnf"
  elif have_cmd yum; then
    echo "yum"
  elif have_cmd pacman; then
    echo "pacman"
  elif have_cmd apk; then
    echo "apk"
  elif have_cmd zypper; then
    echo "zypper"
  else
    echo ""
  fi
}

pkg_update() {
  local pm="$1"
  if [ "${PKG_UPDATED}" -eq 1 ]; then
    return
  fi
  case "${pm}" in
    apt)
      ${SUDO} apt-get update -y
      ;;
    dnf)
      ${SUDO} dnf makecache -y
      ;;
    yum)
      ${SUDO} yum makecache -y
      ;;
    pacman)
      ${SUDO} pacman -Sy --noconfirm
      ;;
    apk)
      ${SUDO} apk update
      ;;
    zypper)
      ${SUDO} zypper --non-interactive refresh
      ;;
    *)
      ;;
  esac
  PKG_UPDATED=1
}

pkg_install() {
  local pm="$1"
  shift
  local pkgs=("$@")
  pkg_update "${pm}"
  case "${pm}" in
    apt)
      DEBIAN_FRONTEND=noninteractive ${SUDO} apt-get install -y --no-install-recommends "${pkgs[@]}"
      ;;
    dnf)
      ${SUDO} dnf install -y "${pkgs[@]}"
      ;;
    yum)
      ${SUDO} yum install -y "${pkgs[@]}"
      ;;
    pacman)
      ${SUDO} pacman -S --noconfirm --needed "${pkgs[@]}"
      ;;
    apk)
      ${SUDO} apk add --no-cache "${pkgs[@]}"
      ;;
    zypper)
      ${SUDO} zypper --non-interactive install -y "${pkgs[@]}"
      ;;
    *)
      die "Unsupported package manager for auto-install."
      ;;
  esac
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

  if ! have_cmd cmake || ! have_cmd pkg-config || (! have_cmd gcc && ! have_cmd clang) || ! have_cmd make; then
    missing=1
  fi

  if [ "${missing}" -eq 0 ]; then
    return
  fi

  PKG_MANAGER="$(detect_pkg_manager)"
  if [ -z "${PKG_MANAGER}" ]; then
    die "No supported package manager found. Install deps manually or set SKIP_SYSTEM_DEPS=1."
  fi

  log "Installing system build dependencies via ${PKG_MANAGER}..."
  case "${PKG_MANAGER}" in
    apt)
      pkg_install apt git curl ca-certificates zip nodejs npm python3 python3-pip \
        build-essential clang cmake pkg-config libssl-dev zlib1g-dev
      ;;
    dnf)
      pkg_install dnf git curl ca-certificates zip nodejs npm python3 python3-pip \
        gcc gcc-c++ make clang cmake pkgconfig openssl-devel zlib-devel
      ;;
    yum)
      pkg_install yum git curl ca-certificates zip nodejs npm python3 python3-pip \
        gcc gcc-c++ make clang cmake pkgconfig openssl-devel zlib-devel
      ;;
    pacman)
      pkg_install pacman git curl ca-certificates zip nodejs npm python python-pip \
        base-devel clang cmake pkgconf openssl zlib
      ;;
    apk)
      pkg_install apk git curl ca-certificates zip nodejs npm python3 py3-pip \
        build-base clang cmake pkgconf openssl-dev zlib-dev
      ;;
    zypper)
      pkg_install zypper git curl ca-certificates zip nodejs npm python3 python3-pip \
        gcc gcc-c++ make clang cmake pkg-config libopenssl-devel zlib-devel
      ;;
    *)
      die "Unsupported package manager: ${PKG_MANAGER}"
      ;;
  esac
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

require_env NPM_TOKEN
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
scripts/apply-patches.sh
PATCHES_APPLIED=1

RELEASE_TAG="${RELEASE_TAG:-}"
if [ -z "${RELEASE_TAG}" ]; then
  RELEASE_TAG="$(git -C "${VIBE_DIR}" tag -l 'v[0-9]*' --sort=creatordate | tail -n 1)"
fi
if [ -z "${RELEASE_TAG}" ]; then
  BASE_VERSION="$(${NODE_CMD} -p "require('${VIBE_DIR}/package.json').version")"
  RELEASE_TAG="v${BASE_VERSION}-$(date +%Y%m%d%H%M%S)"
fi

VERSION="${RELEASE_TAG#v}"

echo "Using release tag: ${RELEASE_TAG}"
echo "Using npm version: ${VERSION}"

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

sed -i "s/npx vibe-kanban/npx @iamriajul\\/vibe-kanban-fork/g" "${VIBE_DIR}/npx-cli/README.md"

echo "Installing dependencies..."
(cd "${VIBE_DIR}" && pnpm install)

echo "Building frontend..."
(cd "${VIBE_DIR}/frontend" && pnpm run build)

HOST_TRIPLE="$(rustc -vV | awk '/host/ {print $2}')"
LINUX_TARGET="${LINUX_TARGET:-x86_64-unknown-linux-gnu}"

TARGET_TRIPLE="${LINUX_TARGET}"
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

PLATFORM_DIR="linux-x64"
if [[ "${TARGET_TRIPLE}" == *"aarch64"* ]]; then
  PLATFORM_DIR="linux-arm64"
fi

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
NPMRC_BAK="${TMP_DIR}/.npmrc"
umask 077
printf "//registry.npmjs.org/:_authToken=%s\n" "${NPM_TOKEN}" > "${NPMRC_BAK}"

(cd "${VIBE_DIR}/npx-cli" && NPM_CONFIG_USERCONFIG="${NPMRC_BAK}" npm publish --ignore-scripts --access public)

echo "Publish complete."
