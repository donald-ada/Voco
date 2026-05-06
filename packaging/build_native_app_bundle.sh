#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/build_native_app_bundle.sh --profile <debug|release>

Builds target/native/Voco.app from the Swift native app package.
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
    SWIFT_CONFIG="debug"
    ;;
  release)
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
NATIVE_DIR="${REPO_ROOT}/native"
BUNDLE_PATH="${REPO_ROOT}/target/native/Voco.app"
CONTENTS_DIR="${BUNDLE_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
INFO_PLIST="${CONTENTS_DIR}/Info.plist"
PLIST_TEMPLATE="${NATIVE_DIR}/Resources/Info.plist"
BINARY="${NATIVE_DIR}/.build/${SWIFT_CONFIG}/Voco"

if [[ ! -f "${PLIST_TEMPLATE}" ]]; then
  echo "missing required file: ${PLIST_TEMPLATE}" >&2
  exit 66
fi

swift build --package-path "${NATIVE_DIR}" -c "${SWIFT_CONFIG}" --product Voco
echo "ok: built native Swift app: ${SWIFT_CONFIG}"

if [[ ! -x "${BINARY}" ]]; then
  echo "missing executable: ${BINARY}" >&2
  exit 66
fi

rm -rf "${BUNDLE_PATH}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${PLIST_TEMPLATE}" "${INFO_PLIST}"
cp "${BINARY}" "${MACOS_DIR}/Voco"
chmod 755 "${MACOS_DIR}/Voco"

plutil -lint "${INFO_PLIST}" >/dev/null
codesign --force --deep --sign - "${BUNDLE_PATH}" >/dev/null
codesign --verify --deep --strict "${BUNDLE_PATH}"

echo "ok: verified native Voco.app bundle: target/native/Voco.app"
