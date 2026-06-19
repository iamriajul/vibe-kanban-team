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
DOWNLOAD_SRC_BAK=""
PKG_JSON_BAK=""
README_BAK=""
NPMRC_BAK=""

cleanup() {
  set +e

  if [ -n "${DOWNLOAD_SRC_BAK}" ] && [ -f "${DOWNLOAD_SRC_BAK}" ]; then
    cp "${DOWNLOAD_SRC_BAK}" "${VIBE_DIR}/npx-cli/src/download.ts"
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

OS_NAME="$(uname -s)"
case "${OS_NAME}" in
  Darwin|Linux)
    ;;
  *)
    die "Unsupported OS: ${OS_NAME}. Supported: Linux, macOS (Darwin)."
    ;;
esac

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if have_cmd sudo; then
    SUDO="sudo"
  fi
fi

BREW_UPDATED=0
BREW_BIN=""

detect_brew() {
  if have_cmd brew; then
    BREW_BIN="$(command -v brew)"
    return 0
  fi

  local candidates=(
    "/opt/homebrew/bin/brew"
    "/usr/local/bin/brew"
    "/home/linuxbrew/.linuxbrew/bin/brew"
  )
  local c=""
  for c in "${candidates[@]}"; do
    if [ -x "${c}" ]; then
      BREW_BIN="${c}"
      return 0
    fi
  done

  return 1
}

brew_shellenv() {
  if [ -z "${BREW_BIN}" ]; then
    return 1
  fi
  # shellcheck disable=SC1090
  eval "$("${BREW_BIN}" shellenv)"
}

install_homebrew() {
  if ! have_cmd curl; then
    die "curl is required to install Homebrew. Install curl manually or set SKIP_SYSTEM_DEPS=1."
  fi

  log "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if ! detect_brew; then
    die "Homebrew install completed, but 'brew' was not found on PATH or standard locations."
  fi
  brew_shellenv
}

ensure_homebrew() {
  if detect_brew; then
    brew_shellenv || true
    return
  fi
  install_homebrew
}

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
  local required_cmds=(git curl zip npm aws)
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

  ensure_homebrew

  log "Installing system build dependencies via Homebrew..."

  brew_install_formula git
  brew_install_formula curl
  brew_install_formula zip
  brew_install_formula node
  brew_install_formula python
  brew_install_formula cmake
  brew_install_formula pkg-config
  brew_install_formula awscli

  if [ "${OS_NAME}" = "Linux" ]; then
    brew_install_formula make
    brew_install_formula gcc
    brew_install_formula openssl@3
    brew_install_formula zlib
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

ensure_prereqs() {
  ensure_system_packages
  detect_runtime_cmds
  ensure_rustup
  ensure_pnpm
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

platform_package_alias() {
  case "$1" in
    linux-x64) printf '%s\n' "vibe-kanban-team-linux-x64" ;;
    macos-arm64) printf '%s\n' "vibe-kanban-team-macos-arm64" ;;
    *) return 1 ;;
  esac
}

platform_package_os() {
  case "$1" in
    linux-*) printf '%s\n' "linux" ;;
    macos-*) printf '%s\n' "darwin" ;;
    windows-*) printf '%s\n' "win32" ;;
    *) return 1 ;;
  esac
}

platform_package_cpu() {
  case "$1" in
    *-x64) printf '%s\n' "x64" ;;
    *-arm64) printf '%s\n' "arm64" ;;
    *) return 1 ;;
  esac
}

configure_npm_publish_auth() {
  if [ "${NPM_PUBLISH_AUTH}" = "token" ]; then
    NPMRC_BAK="${TMP_DIR}/.npmrc"
    umask 077
    printf "//registry.npmjs.org/:_authToken=%s\n" "${NPM_TOKEN}" > "${NPMRC_BAK}"
  else
    echo "Using npm trusted publishing (OIDC)."
    # setup-node writes a token-based .npmrc when registry-url is configured.
    # In OIDC mode, keep npm from falling back to stale token auth.
    unset NODE_AUTH_TOKEN
    unset NPM_CONFIG_USERCONFIG
    unset npm_config_userconfig
  fi
}

npm_with_auth() {
  if [ "${NPM_PUBLISH_AUTH}" = "token" ]; then
    npm --userconfig "${NPMRC_BAK}" "$@"
  else
    npm "$@"
  fi
}

publish_platform_package() {
  local platform_dir="$1"
  local dist_dir="$2"
  local package_alias=""
  local package_os=""
  local package_cpu=""
  local package_version="${VERSION}-${platform_dir}"
  local package_tag="${NPM_TAG}-${platform_dir}"

  if ! package_alias="$(platform_package_alias "${platform_dir}")"; then
    log "Skipping npm platform package for unsupported platform ${platform_dir}."
    return
  fi
  package_os="$(platform_package_os "${platform_dir}")"
  package_cpu="$(platform_package_cpu "${platform_dir}")"

  local package_dir="${TMP_DIR}/platform-package-${platform_dir}"
  rm -rf "${package_dir}"
  mkdir -p "${package_dir}/dist/${platform_dir}"
  cp "${dist_dir}"/*.zip "${package_dir}/dist/${platform_dir}/"

  ${NODE_CMD} - "${package_dir}/package.json" "${package_version}" "${package_os}" "${package_cpu}" <<'NODE'
const fs = require('fs');

const [path, version, os, cpu] = process.argv.slice(2);
const pkg = {
  name: 'vibe-kanban-team',
  version,
  description: `Platform binaries for vibe-kanban-team (${os}-${cpu})`,
  license: 'UNLICENSED',
  private: false,
  os: [os],
  cpu: [cpu],
  files: ['dist'],
  repository: {
    type: 'git',
    url: 'git+https://github.com/iamriajul/vibe-kanban-team.git',
  },
  publishConfig: {
    access: 'public',
    registry: 'https://registry.npmjs.org',
  },
};

fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + '\n');
NODE

  printf '# %s\n\nPlatform binaries for vibe-kanban-team.\n' "${package_alias}" > "${package_dir}/README.md"

  configure_npm_publish_auth
  if (cd "${package_dir}" && npm_with_auth view "vibe-kanban-team@${package_version}" version >/dev/null 2>&1); then
    echo "npm platform package vibe-kanban-team@${package_version} already exists; skipping publish."
  else
    echo "Publishing npm platform package vibe-kanban-team@${package_version} for alias ${package_alias} with dist-tag: ${package_tag}"
    (cd "${package_dir}" && npm_with_auth publish --ignore-scripts --access public --tag "${package_tag}")
  fi
}

cleanup_old_binary_artifacts() {
  if [ "${R2_CLEANUP_BINARY_ARTIFACTS:-1}" != "1" ]; then
    log "Skipping R2 binary cleanup because R2_CLEANUP_BINARY_ARTIFACTS=${R2_CLEANUP_BINARY_ARTIFACTS:-1}."
    return
  fi

  local keep_count="${R2_CLEANUP_KEEP_BUILDS:-10}"
  local max_age_days="${R2_CLEANUP_MAX_AGE_DAYS:-7}"

  if ! [[ "${keep_count}" =~ ^[0-9]+$ ]] || [ "${keep_count}" -lt 1 ]; then
    die "R2_CLEANUP_KEEP_BUILDS must be a positive integer."
  fi
  if ! [[ "${max_age_days}" =~ ^[0-9]+$ ]]; then
    die "R2_CLEANUP_MAX_AGE_DAYS must be a non-negative integer."
  fi

  require_cmd aws
  require_env R2_ACCESS_KEY_ID
  require_env R2_SECRET_ACCESS_KEY
  require_env R2_ENDPOINT
  require_env R2_BUCKET

  export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
  export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
  export AWS_DEFAULT_REGION="${R2_REGION:-auto}"
  export AWS_EC2_METADATA_DISABLED=true

  local list_path="${TMP_DIR}/r2-binary-objects.json"
  local delete_list_path="${TMP_DIR}/r2-binary-delete-list.txt"

  aws --endpoint-url "${R2_ENDPOINT}" s3api list-objects-v2 \
    --bucket "${R2_BUCKET}" \
    --prefix "binaries/" \
    --output json > "${list_path}"

  ${NODE_CMD} - "${list_path}" "${delete_list_path}" "${keep_count}" "${max_age_days}" <<'NODE'
const fs = require('fs');

const [listPath, outPath, keepCountRaw, maxAgeDaysRaw] = process.argv.slice(2);
const keepCount = Number.parseInt(keepCountRaw, 10);
const maxAgeDays = Number.parseInt(maxAgeDaysRaw, 10);
const data = JSON.parse(fs.readFileSync(listPath, 'utf8'));
const cutoff = Date.now() - maxAgeDays * 24 * 60 * 60 * 1000;
const builds = [];

for (const object of data.Contents || []) {
  const key = object.Key || '';
  const match = key.match(/^binaries\/([^/]+)\/manifest\.json$/);
  if (!match) continue;

  const lastModified = Date.parse(object.LastModified || '');
  if (!Number.isFinite(lastModified)) continue;

  builds.push({
    tag: match[1],
    key,
    lastModified,
  });
}

builds.sort((a, b) => b.lastModified - a.lastModified || b.tag.localeCompare(a.tag));

const protectedTags = new Set(builds.slice(0, keepCount).map((build) => build.tag));
const deleteTags = builds
  .filter((build) => build.lastModified < cutoff && !protectedTags.has(build.tag))
  .map((build) => build.tag);

fs.writeFileSync(outPath, deleteTags.join('\n') + (deleteTags.length ? '\n' : ''));
NODE

  if [ ! -s "${delete_list_path}" ]; then
    log "R2 binary cleanup found nothing older than ${max_age_days} days outside the newest ${keep_count} builds."
    return
  fi

  while IFS= read -r old_tag; do
    if [ -z "${old_tag}" ]; then
      continue
    fi
    log "Deleting R2 binary build binaries/${old_tag}/"
    aws --endpoint-url "${R2_ENDPOINT}" s3 rm \
      "s3://${R2_BUCKET}/binaries/${old_tag}/" \
      --recursive
  done < "${delete_list_path}"
}

ensure_prereqs

require_cmd git
require_cmd "${NODE_CMD}"
require_cmd npm
require_cmd pnpm

PUBLISH_BINARY_ARTIFACTS="${PUBLISH_BINARY_ARTIFACTS:-1}"
PUBLISH_R2_BINARY_ARTIFACTS="${PUBLISH_R2_BINARY_ARTIFACTS:-1}"
PUBLISH_PLATFORM_NPM_PACKAGE="${PUBLISH_PLATFORM_NPM_PACKAGE:-0}"
PUBLISH_NPM_PACKAGE="${PUBLISH_NPM_PACKAGE:-1}"
UPDATE_LATEST_BINARY_POINTER="${UPDATE_LATEST_BINARY_POINTER:-1}"

case "${PUBLISH_BINARY_ARTIFACTS}" in
  0|1) ;;
  *) die "PUBLISH_BINARY_ARTIFACTS must be 0 or 1" ;;
esac

case "${PUBLISH_R2_BINARY_ARTIFACTS}" in
  0|1) ;;
  *) die "PUBLISH_R2_BINARY_ARTIFACTS must be 0 or 1" ;;
esac

case "${PUBLISH_PLATFORM_NPM_PACKAGE}" in
  0|1) ;;
  *) die "PUBLISH_PLATFORM_NPM_PACKAGE must be 0 or 1" ;;
esac

case "${PUBLISH_NPM_PACKAGE}" in
  0|1) ;;
  *) die "PUBLISH_NPM_PACKAGE must be 0 or 1" ;;
esac

case "${UPDATE_LATEST_BINARY_POINTER}" in
  0|1) ;;
  *) die "UPDATE_LATEST_BINARY_POINTER must be 0 or 1" ;;
esac

if [ "${PUBLISH_BINARY_ARTIFACTS}" -eq 0 ] &&
   [ "${PUBLISH_PLATFORM_NPM_PACKAGE}" -eq 0 ] &&
   [ "${PUBLISH_NPM_PACKAGE}" -eq 0 ]; then
  die "Nothing to do: enable PUBLISH_BINARY_ARTIFACTS, PUBLISH_PLATFORM_NPM_PACKAGE, and/or PUBLISH_NPM_PACKAGE"
fi

if [ "${PUBLISH_PLATFORM_NPM_PACKAGE}" -eq 1 ] && [ "${PUBLISH_BINARY_ARTIFACTS}" -eq 0 ]; then
  die "PUBLISH_PLATFORM_NPM_PACKAGE=1 requires PUBLISH_BINARY_ARTIFACTS=1"
fi

NPM_PUBLISH_AUTH="${NPM_PUBLISH_AUTH:-}"
if [ "${PUBLISH_NPM_PACKAGE}" -eq 1 ] || [ "${PUBLISH_PLATFORM_NPM_PACKAGE}" -eq 1 ]; then
  if [ -z "${NPM_PUBLISH_AUTH}" ]; then
    if [ -n "${NPM_TOKEN:-}" ]; then
      NPM_PUBLISH_AUTH="token"
    else
      NPM_PUBLISH_AUTH="oidc"
    fi
  fi

  case "${NPM_PUBLISH_AUTH}" in
    token)
      require_env NPM_TOKEN
      ;;
    oidc)
      if [ "${GITHUB_ACTIONS:-}" = "true" ] &&
         { [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; }; then
        die "NPM_PUBLISH_AUTH=oidc requires GitHub Actions id-token: write permission"
      fi
      ;;
    *)
      die "NPM_PUBLISH_AUTH must be 'oidc' or 'token'"
      ;;
  esac
fi

if [ "${PUBLISH_BINARY_ARTIFACTS}" -eq 1 ]; then
  require_cmd cargo
  require_cmd rustc
  require_cmd zip

  require_env VITE_PUBLIC_REACT_VIRTUOSO_LICENSE_KEY

  if [ "${PUBLISH_R2_BINARY_ARTIFACTS}" -eq 1 ]; then
    require_cmd aws
    require_env R2_ACCESS_KEY_ID
    require_env R2_SECRET_ACCESS_KEY
    require_env R2_ENDPOINT
    require_env R2_BUCKET
    require_env R2_PUBLIC_URL
  fi
fi

if [ "${PUBLISH_NPM_PACKAGE}" -eq 1 ]; then
  require_env R2_PUBLIC_URL
  if [ "${UPDATE_LATEST_BINARY_POINTER}" -eq 1 ] || [ "${R2_CLEANUP_BINARY_ARTIFACTS:-1}" = "1" ]; then
    require_cmd aws
    require_env R2_ACCESS_KEY_ID
    require_env R2_SECRET_ACCESS_KEY
    require_env R2_ENDPOINT
    require_env R2_BUCKET
  fi
fi

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

# Versioning (two modes only):
# - Automatic: detect from upstream package.json when NPM_VERSION is unset.
# - Manual: set NPM_VERSION to override.
if [ -n "${RELEASE_TAG:-}" ] || [ -n "${RELEASE_TAG_MODE:-}" ] || [ -n "${BASE_VERSION_OVERRIDE:-}" ]; then
  die "RELEASE_TAG/RELEASE_TAG_MODE/BASE_VERSION_OVERRIDE are no longer supported. Use NPM_VERSION (manual) or omit it (auto-detect)."
fi

NPM_TAG="${NPM_TAG:-latest}"
NPM_VERSION="${NPM_VERSION:-}"

if [[ "${NPM_VERSION}" == v* ]]; then
  die "NPM_VERSION should not include a leading 'v' (got: ${NPM_VERSION}). Use e.g. 0.1.7 or 0.1.7-rc.1."
fi

VERSION=""
if [ -n "${NPM_VERSION}" ]; then
  VERSION="${NPM_VERSION}"
else
  VERSION="$(${NODE_CMD} -p "require('${VIBE_DIR}/package.json').version")"
fi

if [ -z "${VERSION}" ] || [ "${VERSION}" = "undefined" ] || [ "${VERSION}" = "null" ]; then
  die "Failed to determine package version. Set NPM_VERSION to override."
fi

# Binaries use a v-prefixed tag (historical; download.js expects a leading "v").
# NPM uses semver without the leading "v".
BINARY_TAG="v${VERSION}"

echo "Using version: ${VERSION}"
echo "Using binary tag: ${BINARY_TAG}"
echo "Using npm dist-tag: ${NPM_TAG}"
echo "Publish binary artifacts: ${PUBLISH_BINARY_ARTIFACTS}"
echo "Publish R2 binary artifacts: ${PUBLISH_R2_BINARY_ARTIFACTS}"
echo "Publish platform npm package: ${PUBLISH_PLATFORM_NPM_PACKAGE}"
echo "Publish npm package: ${PUBLISH_NPM_PACKAGE}"
echo "Update latest binary pointer: ${UPDATE_LATEST_BINARY_POINTER}"

echo "Applying downstream patches..."
"${ROOT_DIR}/scripts/apply-patches.sh" vibe-kanban
PATCHES_APPLIED=1

TMP_DIR="$(mktemp -d)"
DOWNLOAD_SRC_BAK="${TMP_DIR}/download.ts.bak"
PKG_JSON_BAK="${TMP_DIR}/package.json.bak"
README_BAK="${TMP_DIR}/README.md.bak"

cp "${VIBE_DIR}/npx-cli/src/download.ts" "${DOWNLOAD_SRC_BAK}"
cp "${VIBE_DIR}/npx-cli/package.json" "${PKG_JSON_BAK}"
cp "${VIBE_DIR}/npx-cli/README.md" "${README_BAK}"

${NODE_CMD} -e "
  const fs = require('fs');
  const path = '${VIBE_DIR}/npx-cli/package.json';
  const pkg = JSON.parse(fs.readFileSync(path, 'utf8'));
  pkg.name = 'vibe-kanban-team';
  pkg.version = '${VERSION}';
  pkg.publishConfig = { access: 'public', registry: 'https://registry.npmjs.org' };
  pkg.author = 'iamriajul';
  pkg.repository = { type: 'git', url: 'git+https://github.com/iamriajul/vibe-kanban-team.git' };
  pkg.optionalDependencies = {
    'vibe-kanban-team-linux-x64': 'npm:vibe-kanban-team@${VERSION}-linux-x64',
    'vibe-kanban-team-macos-arm64': 'npm:vibe-kanban-team@${VERSION}-macos-arm64',
  };
  fs.writeFileSync(path, JSON.stringify(pkg, null, 2) + '\\n');
"

${NODE_CMD} -e "
  const fs = require('fs');
  const path = '${VIBE_DIR}/npx-cli/README.md';
  let data = fs.readFileSync(path, 'utf8');
  data = data.replace(/npx vibe-kanban/g, 'npx vibe-kanban-team');
  fs.writeFileSync(path, data);
"

echo "Installing dependencies..."
(cd "${VIBE_DIR}" && pnpm install)

if [ "${PUBLISH_BINARY_ARTIFACTS}" -eq 1 ]; then
  echo "Building frontend..."
  if [ -d "${VIBE_DIR}/packages/local-web" ]; then
    (cd "${VIBE_DIR}" && pnpm --filter @vibe/local-web run build)
  elif [ -d "${VIBE_DIR}/frontend" ]; then
    (cd "${VIBE_DIR}/frontend" && pnpm run build)
  else
    die "Frontend source directory not found. Expected '${VIBE_DIR}/packages/local-web' or '${VIBE_DIR}/frontend'."
  fi

  HOST_TRIPLE="$(rustc -vV | awk '/host/ {print $2}')"

  TARGET_TRIPLE="${TARGET_TRIPLE:-}"
  if [ -z "${TARGET_TRIPLE}" ]; then
    case "${OS_NAME}" in
      Darwin)
        TARGET_TRIPLE="${MACOS_TARGET:-${HOST_TRIPLE}}"
        ;;
      Linux)
        TARGET_TRIPLE="${LINUX_TARGET:-${HOST_TRIPLE}}"
        ;;
    esac
  fi

  case "${OS_NAME}" in
    Darwin)
      case "${HOST_TRIPLE}" in
        *apple-darwin)
          ;;
        *)
          die "Rust host target '${HOST_TRIPLE}' is not macOS. Run this script on a macOS host."
          ;;
      esac
      case "${TARGET_TRIPLE}" in
        *apple-darwin)
          ;;
        *)
          die "Unsupported macOS target triple: ${TARGET_TRIPLE}. Expected an *-apple-darwin triple."
          ;;
      esac
      ;;
    Linux)
      # Best-effort sanity check only; cross builds are still allowed.
      case "${TARGET_TRIPLE}" in
        *linux*)
          ;;
        *)
          log "Warning: target triple '${TARGET_TRIPLE}' does not look like Linux."
          ;;
      esac
      ;;
  esac

  if [ "${TARGET_TRIPLE}" != "${HOST_TRIPLE}" ]; then
    echo "Adding Rust target ${TARGET_TRIPLE}..."
    rustup target add "${TARGET_TRIPLE}"
  fi

  echo "Resolving MCP binary target..."
  MCP_BIN_TARGET="$(
    cd "${VIBE_DIR}" && cargo metadata --no-deps --format-version 1 | ${NODE_CMD} -e '
      let data = "";
      process.stdin.on("data", chunk => data += chunk);
      process.stdin.on("end", () => {
        const metadata = JSON.parse(data);
        const binTargets = new Set();
        for (const pkg of metadata.packages || []) {
          for (const target of pkg.targets || []) {
            if ((target.kind || []).includes("bin")) {
              binTargets.add(target.name);
            }
          }
        }
        if (binTargets.has("vibe-kanban-mcp")) {
          process.stdout.write("vibe-kanban-mcp");
        } else if (binTargets.has("mcp_task_server")) {
          process.stdout.write("mcp_task_server");
        }
      });
    '
  )"
  if [ -z "${MCP_BIN_TARGET}" ]; then
    die "Unable to detect MCP binary target. Expected 'vibe-kanban-mcp' or 'mcp_task_server'."
  fi
  echo "Using MCP binary target: ${MCP_BIN_TARGET}"

  echo "Building backend binaries for ${TARGET_TRIPLE}..."
  if [ "${TARGET_TRIPLE}" = "${HOST_TRIPLE}" ]; then
    (cd "${VIBE_DIR}" && cargo build --release --bin server --bin "${MCP_BIN_TARGET}" --bin review)
    TARGET_DIR="${VIBE_DIR}/target/release"
  else
    (cd "${VIBE_DIR}" && cargo build --release --target "${TARGET_TRIPLE}" --bin server --bin "${MCP_BIN_TARGET}" --bin review)
    TARGET_DIR="${VIBE_DIR}/target/${TARGET_TRIPLE}/release"
  fi

  if [ ! -f "${TARGET_DIR}/server" ]; then
    echo "Expected binary not found at ${TARGET_DIR}/server"
    exit 1
  fi
  if [ ! -f "${TARGET_DIR}/${MCP_BIN_TARGET}" ]; then
    echo "Expected binary not found at ${TARGET_DIR}/${MCP_BIN_TARGET}"
    exit 1
  fi
  if [ ! -f "${TARGET_DIR}/review" ]; then
    echo "Expected binary not found at ${TARGET_DIR}/review"
    exit 1
  fi

  PLATFORM_DIR=""
  case "${OS_NAME}" in
    Linux)
      PLATFORM_DIR="linux-x64"
      if [[ "${TARGET_TRIPLE}" == *"aarch64"* ]] || [[ "${TARGET_TRIPLE}" == *"arm64"* ]]; then
        PLATFORM_DIR="linux-arm64"
      fi
      ;;
    Darwin)
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
      ;;
  esac

  DIST_DIR="${VIBE_DIR}/npx-cli/dist/${PLATFORM_DIR}"
  rm -rf "${DIST_DIR}"
  mkdir -p "${DIST_DIR}"

  echo "Packaging binaries..."
  WORK_DIR="$(mktemp -d)"

  cp "${TARGET_DIR}/server" "${WORK_DIR}/vibe-kanban"
  zip -j "${DIST_DIR}/vibe-kanban.zip" "${WORK_DIR}/vibe-kanban" >/dev/null

  cp "${TARGET_DIR}/${MCP_BIN_TARGET}" "${WORK_DIR}/vibe-kanban-mcp"
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
    const tag = '${BINARY_TAG}';
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

  if [ "${PUBLISH_PLATFORM_NPM_PACKAGE}" -eq 1 ]; then
    publish_platform_package "${PLATFORM_DIR}" "${DIST_DIR}"
  fi

  if [ "${PUBLISH_R2_BINARY_ARTIFACTS}" -eq 1 ]; then
    echo "Uploading to R2..."
    export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
    export AWS_DEFAULT_REGION="${R2_REGION:-auto}"
    export AWS_EC2_METADATA_DISABLED=true

    EXISTING_MANIFEST_PATH="${TMP_DIR}/existing-manifest.json"
    if aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
      "s3://${R2_BUCKET}/binaries/${BINARY_TAG}/manifest.json" \
      "${EXISTING_MANIFEST_PATH}" >/dev/null 2>&1; then
      echo "Merging with existing manifest for ${BINARY_TAG}..."
    else
      rm -f "${EXISTING_MANIFEST_PATH}"
    fi

    ${NODE_CMD} -e "
      const fs = require('fs');
      const outPath = '${MANIFEST_PATH}';
      const platformPath = '${PLATFORM_MANIFEST_PATH}';
      const existingPath = '${EXISTING_MANIFEST_PATH}';

      const merged = { version: '${BINARY_TAG}', platforms: {} };
      if (fs.existsSync(existingPath)) {
        try {
          const existing = JSON.parse(fs.readFileSync(existingPath, 'utf8'));
          if (existing && typeof existing === 'object' && existing.platforms && typeof existing.platforms === 'object') {
            merged.platforms = existing.platforms;
          }
        } catch {}
      }

      const platformManifest = JSON.parse(fs.readFileSync(platformPath, 'utf8'));
      merged.version = '${BINARY_TAG}';
      merged.platforms['${PLATFORM_DIR}'] = platformManifest.platforms?.['${PLATFORM_DIR}'] || {};

      fs.writeFileSync(outPath, JSON.stringify(merged, null, 2));
    "

    for bin in vibe-kanban vibe-kanban-mcp vibe-kanban-review; do
      ZIP_PATH="${DIST_DIR}/${bin}.zip"
      if [ -f "${ZIP_PATH}" ]; then
        aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
          "${ZIP_PATH}" \
          "s3://${R2_BUCKET}/binaries/${BINARY_TAG}/${PLATFORM_DIR}/${bin}.zip"
      fi
    done

    aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
      "${MANIFEST_PATH}" \
      "s3://${R2_BUCKET}/binaries/${BINARY_TAG}/manifest.json" \
      --content-type "application/json"

    # Only update the "latest" pointer when publishing under the npm "latest" dist-tag.
    if [ "${NPM_TAG}" = "latest" ] && [ "${UPDATE_LATEST_BINARY_POINTER}" -eq 1 ]; then
      echo "{\"latest\": \"${VERSION}\"}" | aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
        - "s3://${R2_BUCKET}/binaries/manifest.json" \
        --content-type "application/json"
    elif [ "${NPM_TAG}" = "latest" ]; then
      log "Skipping binaries/manifest.json update because UPDATE_LATEST_BINARY_POINTER=0."
    else
      log "Skipping binaries/manifest.json update because NPM_TAG=${NPM_TAG} (not 'latest')."
    fi
  else
    log "Skipping R2 binary artifact upload because PUBLISH_R2_BINARY_ARTIFACTS=0."
  fi
fi

if [ "${PUBLISH_BINARY_ARTIFACTS}" -eq 0 ]; then
  # Final publish jobs can update the global pointer after all platform uploads finish.
  if [ "${NPM_TAG}" = "latest" ] && [ "${UPDATE_LATEST_BINARY_POINTER}" -eq 1 ]; then
    export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"
    export AWS_DEFAULT_REGION="${R2_REGION:-auto}"
    export AWS_EC2_METADATA_DISABLED=true

    echo "{\"latest\": \"${VERSION}\"}" | aws --endpoint-url "${R2_ENDPOINT}" s3 cp \
      - "s3://${R2_BUCKET}/binaries/manifest.json" \
      --content-type "application/json"
  elif [ "${NPM_TAG}" = "latest" ]; then
    log "Skipping binaries/manifest.json update because UPDATE_LATEST_BINARY_POINTER=0."
  else
    log "Skipping binaries/manifest.json update because NPM_TAG=${NPM_TAG} (not 'latest')."
  fi

  if [ "${UPDATE_LATEST_BINARY_POINTER}" -eq 1 ]; then
    cleanup_old_binary_artifacts
  fi
fi

if [ "${PUBLISH_NPM_PACKAGE}" -eq 1 ]; then
  echo "Injecting R2 URL and tag into download.ts..."
  ${NODE_CMD} -e "
    const fs = require('fs');
    const path = '${VIBE_DIR}/npx-cli/src/download.ts';
    let data = fs.readFileSync(path, 'utf8');
    data = data.replace(/__R2_PUBLIC_URL__/g, '${R2_PUBLIC_URL}');
    data = data.replace(/__BINARY_TAG__/g, '${BINARY_TAG}');
    fs.writeFileSync(path, data);
  "

  echo "Building npx-cli..."
  (cd "${VIBE_DIR}/npx-cli" && npm install && npm run build)

  echo "Removing local dist artifacts before npm publish..."
  rm -rf "${VIBE_DIR}/npx-cli/dist"

  echo "Publishing to npm..."
  configure_npm_publish_auth

  if (cd "${VIBE_DIR}/npx-cli" && npm_with_auth view "vibe-kanban-team@${VERSION}" version >/dev/null 2>&1); then
    echo "npm version ${VERSION} already exists; skipping publish."
  else
    echo "Publishing to npm with dist-tag: ${NPM_TAG}"
    (cd "${VIBE_DIR}/npx-cli" && npm_with_auth publish --ignore-scripts --access public --tag "${NPM_TAG}")
  fi
else
  log "Skipping npm package publish because PUBLISH_NPM_PACKAGE=0."
fi

echo "Publish complete."
