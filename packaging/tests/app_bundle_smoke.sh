#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUNDLE_PATH="${REPO_ROOT}/target/Voco.app"
INFO_PLIST="${BUNDLE_PATH}/Contents/Info.plist"
MACOS_DIR="${BUNDLE_PATH}/Contents/MacOS"

"${REPO_ROOT}/packaging/build_app_bundle.sh" --profile debug

test -d "${BUNDLE_PATH}"
test -f "${INFO_PLIST}"
test -x "${MACOS_DIR}/voco"
test -x "${MACOS_DIR}/voco-daemon"
test -x "${MACOS_DIR}/voco-hud"

plutil -lint "${INFO_PLIST}" >/dev/null

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${INFO_PLIST}")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${INFO_PLIST}")"
LS_UI_ELEMENT="$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "${INFO_PLIST}")"
MIC_USAGE="$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "${INFO_PLIST}")"

if [[ "${BUNDLE_ID}" != "com.voco.app" ]]; then
  echo "unexpected CFBundleIdentifier: ${BUNDLE_ID}" >&2
  exit 1
fi

if [[ "${EXECUTABLE}" != "voco-daemon" ]]; then
  echo "unexpected CFBundleExecutable: ${EXECUTABLE}" >&2
  exit 1
fi

if [[ "${LS_UI_ELEMENT}" != "true" ]]; then
  echo "unexpected LSUIElement: ${LS_UI_ELEMENT}" >&2
  exit 1
fi

if [[ -z "${MIC_USAGE}" ]]; then
  echo "NSMicrophoneUsageDescription must not be empty" >&2
  exit 1
fi

echo "ok: Voco.app bundle smoke passed"
