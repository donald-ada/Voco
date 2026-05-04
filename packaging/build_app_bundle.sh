#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/build_app_bundle.sh --profile <debug|release>

Builds target/Voco.app for local development.
USAGE
}

PROFILE="debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

case "${PROFILE}" in
  debug)
    RUST_BUILD_ARGS=(build --workspace)
    RUST_BIN_DIR="debug"
    SWIFT_CONFIG="debug"
    ;;
  release)
    RUST_BUILD_ARGS=(build --workspace --release)
    RUST_BIN_DIR="release"
    SWIFT_CONFIG="release"
    ;;
  *)
    echo "invalid profile: ${PROFILE}" >&2
    usage
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUNDLE_PATH="${REPO_ROOT}/target/Voco.app"
CONTENTS_DIR="${BUNDLE_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
PLIST_TEMPLATE="${REPO_ROOT}/packaging/Voco.app/Contents/Info.plist.tmpl"
INFO_PLIST="${CONTENTS_DIR}/Info.plist"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "missing required file: ${path}" >&2
    exit 66
  fi
}

require_executable() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "missing executable: ${path}" >&2
    exit 66
  fi
}

require_file "${PLIST_TEMPLATE}"

cd "${REPO_ROOT}"
cargo "${RUST_BUILD_ARGS[@]}"
echo "ok: built Rust workspace: ${PROFILE}"

cd "${REPO_ROOT}/hud"
swift build -c "${SWIFT_CONFIG}"
echo "ok: built Swift HUD: ${SWIFT_CONFIG}"

RUST_OUTPUT_DIR="${REPO_ROOT}/target/${RUST_BIN_DIR}"
HUD_BINARY="${REPO_ROOT}/hud/.build/${SWIFT_CONFIG}/voco-hud"

require_executable "${RUST_OUTPUT_DIR}/voco"
require_executable "${RUST_OUTPUT_DIR}/voco-daemon"
require_executable "${HUD_BINARY}"

rm -rf "${BUNDLE_PATH}"
mkdir -p "${MACOS_DIR}"

cp "${PLIST_TEMPLATE}" "${INFO_PLIST}"
echo "ok: wrote target/Voco.app/Contents/Info.plist"

cp "${RUST_OUTPUT_DIR}/voco" "${MACOS_DIR}/voco"
echo "ok: copied target/${RUST_BIN_DIR}/voco"

cp "${RUST_OUTPUT_DIR}/voco-daemon" "${MACOS_DIR}/voco-daemon"
echo "ok: copied target/${RUST_BIN_DIR}/voco-daemon"

cp "${HUD_BINARY}" "${MACOS_DIR}/voco-hud"
echo "ok: copied hud/.build/${SWIFT_CONFIG}/voco-hud"

chmod 755 "${MACOS_DIR}/voco" "${MACOS_DIR}/voco-daemon" "${MACOS_DIR}/voco-hud"

require_file "${INFO_PLIST}"
require_executable "${MACOS_DIR}/voco"
require_executable "${MACOS_DIR}/voco-daemon"
require_executable "${MACOS_DIR}/voco-hud"
plutil -lint "${INFO_PLIST}" >/dev/null
codesign --force --deep --sign - "${BUNDLE_PATH}" >/dev/null
codesign --verify --deep --strict "${BUNDLE_PATH}"
echo "ok: ad-hoc signed Voco.app bundle"

echo "ok: verified Voco.app bundle: target/Voco.app"
