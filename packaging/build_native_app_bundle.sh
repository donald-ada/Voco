#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/build_native_app_bundle.sh --profile <debug|release> [--signing-style <adhoc|developer-id>] [--signing-identity <identity>]

Builds target/native/Voco.app from the Swift native app package.

Signing:
  --signing-style adhoc        Local signing path. No Apple credentials required.
  --signing-style developer-id Release signing path. Requires --profile release and a Developer ID Application identity.

Developer ID identity can be passed with --signing-identity or VOCO_DEVELOPER_ID_APPLICATION.
USAGE
}

PROFILE="debug"
SIGNING_STYLE="adhoc"
SIGNING_IDENTITY=""

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
    --signing-identity)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      SIGNING_IDENTITY="$2"
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

case "${SIGNING_STYLE}" in
  adhoc|developer-id)
    ;;
  *)
    echo "invalid signing style: ${SIGNING_STYLE}" >&2
    usage
    exit 64
    ;;
esac

if [[ "${SIGNING_STYLE}" == "developer-id" ]]; then
  if [[ "${PROFILE}" != "release" ]]; then
    echo "developer-id signing requires --profile release" >&2
    exit 64
  fi

  if [[ -z "${SIGNING_IDENTITY}" ]]; then
    SIGNING_IDENTITY="${VOCO_DEVELOPER_ID_APPLICATION:-}"
  fi

  if [[ -z "${SIGNING_IDENTITY}" ]]; then
    cat >&2 <<'EOF'
missing Developer ID Application signing identity
set VOCO_DEVELOPER_ID_APPLICATION or pass --signing-identity "Developer ID Application: ..."
EOF
    exit 65
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NATIVE_DIR="${REPO_ROOT}/native"
BUNDLE_PATH="${REPO_ROOT}/target/native/Voco.app"
CONTENTS_DIR="${BUNDLE_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
INFO_PLIST="${CONTENTS_DIR}/Info.plist"
PLIST_TEMPLATE="${NATIVE_DIR}/Resources/Info.plist"
ICON_SOURCE="${NATIVE_DIR}/Resources/VocoIcon.svg"
MENU_BAR_ICON_SOURCE="${NATIVE_DIR}/Resources/VocoMenuBarIconTemplate.svg"
BINARY="${NATIVE_DIR}/.build/${SWIFT_CONFIG}/Voco"
ICON_WORK_DIR="${REPO_ROOT}/target/native/icon-work"
ICONSET_DIR="${ICON_WORK_DIR}/Voco.iconset"
ICON_BASE_PNG="${ICON_WORK_DIR}/VocoIcon.svg.png"

if [[ ! -f "${PLIST_TEMPLATE}" ]]; then
  echo "missing required file: ${PLIST_TEMPLATE}" >&2
  exit 66
fi

if [[ ! -f "${ICON_SOURCE}" ]]; then
  echo "missing required file: ${ICON_SOURCE}" >&2
  exit 66
fi

if [[ ! -f "${MENU_BAR_ICON_SOURCE}" ]]; then
  echo "missing required file: ${MENU_BAR_ICON_SOURCE}" >&2
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
cp "${MENU_BAR_ICON_SOURCE}" "${RESOURCES_DIR}/VocoMenuBarIconTemplate.svg"
chmod 755 "${MACOS_DIR}/Voco"

rm -rf "${ICON_WORK_DIR}"
mkdir -p "${ICON_WORK_DIR}" "${ICONSET_DIR}"
qlmanage -t -s 1024 -o "${ICON_WORK_DIR}" "${ICON_SOURCE}" >/dev/null
if [[ ! -f "${ICON_BASE_PNG}" ]]; then
  echo "failed to render icon PNG from ${ICON_SOURCE}" >&2
  exit 66
fi

sips -z 16 16 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${ICON_BASE_PNG}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null
iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/Voco.icns"
echo "ok: generated native app icon: target/native/Voco.app/Contents/Resources/Voco.icns"

plutil -lint "${INFO_PLIST}" >/dev/null

if [[ "${SIGNING_STYLE}" == "developer-id" ]]; then
  if ! codesign --force --deep --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${BUNDLE_PATH}" >/dev/null; then
    echo "failed to sign native app with Developer ID Application identity: ${SIGNING_IDENTITY}" >&2
    exit 1
  fi

  if ! codesign --display --verbose=4 "${BUNDLE_PATH}" 2>&1 | grep -q 'flags=.*runtime'; then
    echo "native app Developer ID signature is missing hardened runtime flag: ${BUNDLE_PATH}" >&2
    exit 1
  fi
else
  if ! codesign --force --deep --sign - "${BUNDLE_PATH}" >/dev/null; then
    echo "failed to ad-hoc sign native app: ${BUNDLE_PATH}" >&2
    exit 1
  fi
fi

codesign --verify --deep --strict "${BUNDLE_PATH}"

echo "ok: verified native Voco.app bundle: target/native/Voco.app"
