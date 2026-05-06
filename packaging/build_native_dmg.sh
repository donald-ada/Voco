#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/build_native_dmg.sh [--profile <debug|release>] [--signing-style <adhoc|developer-id>] [--app-signing-identity <identity>] [--dmg-signing-identity <identity>] [--dmg <path>] [--volume-name <name>]

Builds a native Voco release disk image.

Outputs by default:
  dist/Voco.app
  dist/Voco.dmg

Signing:
  --signing-style adhoc        Local smoke path. No Apple credentials required.
  --signing-style developer-id Release path. Requires --profile release.

Developer ID app identity:
  --app-signing-identity or VOCO_DEVELOPER_ID_APPLICATION

Developer ID DMG identity:
  --dmg-signing-identity or VOCO_DEVELOPER_ID_DMG, falling back to VOCO_DEVELOPER_ID_APPLICATION
USAGE
}

fail() {
  echo "error: $*" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  if ! command -v "${tool}" >/dev/null 2>&1; then
    fail "missing required tool: ${tool}"
  fi
}

PROFILE="debug"
SIGNING_STYLE="adhoc"
APP_SIGNING_IDENTITY=""
DMG_SIGNING_IDENTITY=""
DMG_PATH=""
VOLUME_NAME="Voco"

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
    --signing-style)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      SIGNING_STYLE="$2"
      shift 2
      ;;
    --app-signing-identity)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      APP_SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --dmg-signing-identity)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      DMG_SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --dmg)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      DMG_PATH="$2"
      shift 2
      ;;
    --volume-name)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      VOLUME_NAME="$2"
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
  debug|release)
    ;;
  *)
    echo "invalid profile: ${PROFILE}" >&2
    usage
    exit 64
    ;;
esac

case "${SIGNING_STYLE}" in
  adhoc|developer-id)
    ;;
  *)
    echo "invalid signing style: ${SIGNING_STYLE}" >&2
    usage
    exit 64
    ;;
esac

if [[ "${SIGNING_STYLE}" == "developer-id" && "${PROFILE}" != "release" ]]; then
  echo "developer-id DMG builds require --profile release" >&2
  exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${DMG_PATH}" ]]; then
  DMG_PATH="${REPO_ROOT}/dist/Voco.dmg"
elif [[ "${DMG_PATH}" != /* ]]; then
  DMG_PATH="${REPO_ROOT}/${DMG_PATH}"
fi

if [[ "${SIGNING_STYLE}" == "developer-id" ]]; then
  if [[ -z "${APP_SIGNING_IDENTITY}" ]]; then
    APP_SIGNING_IDENTITY="${VOCO_DEVELOPER_ID_APPLICATION:-}"
  fi

  if [[ -z "${DMG_SIGNING_IDENTITY}" ]]; then
    DMG_SIGNING_IDENTITY="${VOCO_DEVELOPER_ID_DMG:-${VOCO_DEVELOPER_ID_APPLICATION:-}}"
  fi

  if [[ -z "${APP_SIGNING_IDENTITY}" || -z "${DMG_SIGNING_IDENTITY}" ]]; then
    cat >&2 <<'EOF'
missing Developer ID signing identity for native DMG build
set VOCO_DEVELOPER_ID_APPLICATION for app signing
optionally set VOCO_DEVELOPER_ID_DMG for DMG signing
or pass --app-signing-identity and --dmg-signing-identity explicitly
EOF
    exit 65
  fi
fi

require_tool codesign
require_tool ditto
require_tool hdiutil

BUILD_APP_SCRIPT="${REPO_ROOT}/packaging/build_native_app_bundle.sh"
TARGET_APP="${REPO_ROOT}/target/native/Voco.app"
DIST_DIR="$(dirname "${DMG_PATH}")"
DIST_APP="${DIST_DIR}/Voco.app"
STAGING_DIR="${DIST_DIR}/dmg-root"

if [[ ! -x "${BUILD_APP_SCRIPT}" ]]; then
  fail "missing executable build script: ${BUILD_APP_SCRIPT}"
fi

APP_BUILD_ARGS=("${BUILD_APP_SCRIPT}" --profile "${PROFILE}" --signing-style "${SIGNING_STYLE}")
if [[ "${SIGNING_STYLE}" == "developer-id" ]]; then
  APP_BUILD_ARGS+=(--signing-identity "${APP_SIGNING_IDENTITY}")
fi

echo "ok: building native app bundle for DMG: profile=${PROFILE}, signing=${SIGNING_STYLE}"
"${APP_BUILD_ARGS[@]}"

if [[ ! -d "${TARGET_APP}" ]]; then
  fail "missing built app bundle: ${TARGET_APP}"
fi

rm -rf "${DIST_APP}" "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${DIST_DIR}" "${STAGING_DIR}"

if ! ditto "${TARGET_APP}" "${DIST_APP}"; then
  fail "failed to copy app bundle: ${TARGET_APP} -> ${DIST_APP}"
fi

if ! codesign --verify --deep --strict "${DIST_APP}"; then
  fail "copied app bundle signature verification failed: ${DIST_APP}"
fi

if ! ditto "${DIST_APP}" "${STAGING_DIR}/Voco.app"; then
  fail "failed to stage app bundle for DMG: ${DIST_APP}"
fi

ln -s /Applications "${STAGING_DIR}/Applications"

if ! hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_PATH}"; then
  fail "hdiutil create failed for DMG: ${DMG_PATH}"
fi

if ! hdiutil verify "${DMG_PATH}" >/dev/null; then
  fail "hdiutil verify failed for DMG: ${DMG_PATH}"
fi

if [[ "${SIGNING_STYLE}" == "developer-id" ]]; then
  if ! codesign --force --timestamp --sign "${DMG_SIGNING_IDENTITY}" "${DMG_PATH}"; then
    fail "failed to sign DMG with Developer ID identity: ${DMG_SIGNING_IDENTITY}; command: codesign --force --timestamp --sign <identity> ${DMG_PATH}"
  fi
else
  if ! codesign --force --sign - "${DMG_PATH}"; then
    fail "failed to ad-hoc sign DMG: command: codesign --force --sign - ${DMG_PATH}"
  fi
fi

if ! codesign --verify --strict "${DMG_PATH}"; then
  fail "DMG code signature verification failed: ${DMG_PATH}"
fi

echo "ok: built native distributable app: ${DIST_APP}"
echo "ok: built native DMG: ${DMG_PATH}"

if [[ "${SIGNING_STYLE}" == "developer-id" ]]; then
  cat <<EOF
release verification commands:
  codesign --verify --deep --strict ${DIST_APP}
  spctl --assess --type execute --verbose=4 ${DIST_APP}
  hdiutil verify ${DMG_PATH}
  codesign --verify --strict ${DMG_PATH}
  packaging/notarize_native_dmg.sh --dmg ${DMG_PATH}
  xcrun stapler validate ${DMG_PATH}
  spctl --assess --type open --verbose=4 ${DMG_PATH}
EOF
fi
