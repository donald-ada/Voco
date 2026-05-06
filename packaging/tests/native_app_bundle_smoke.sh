#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUNDLE_PATH="${REPO_ROOT}/target/native/Voco.app"
INFO_PLIST="${BUNDLE_PATH}/Contents/Info.plist"
MACOS_DIR="${BUNDLE_PATH}/Contents/MacOS"
RESOURCES_DIR="${BUNDLE_PATH}/Contents/Resources"

"${REPO_ROOT}/packaging/build_native_app_bundle.sh" --profile debug

test -d "${BUNDLE_PATH}"
test -f "${INFO_PLIST}"
test -x "${MACOS_DIR}/Voco"
if [[ ! -f "${RESOURCES_DIR}/Voco.icns" ]]; then
  echo "missing app icon: ${RESOURCES_DIR}/Voco.icns" >&2
  exit 1
fi

for entry in "${MACOS_DIR}"/*; do
  name="$(basename "${entry}")"
  case "${name}" in
    voco|voco-daemon|voco-hud)
      echo "legacy executable must not be present: ${name}" >&2
      exit 1
      ;;
  esac
done

plutil -lint "${INFO_PLIST}" >/dev/null
codesign --verify --deep --strict "${BUNDLE_PATH}"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${INFO_PLIST}")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${INFO_PLIST}")"
ICON_FILE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "${INFO_PLIST}")"
LS_UI_ELEMENT="$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "${INFO_PLIST}")"
MIC_USAGE="$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "${INFO_PLIST}")"

if [[ "${BUNDLE_ID}" != "com.voco.app" ]]; then
  echo "unexpected CFBundleIdentifier: ${BUNDLE_ID}" >&2
  exit 1
fi

if [[ "${EXECUTABLE}" != "Voco" ]]; then
  echo "unexpected CFBundleExecutable: ${EXECUTABLE}" >&2
  exit 1
fi

if [[ "${ICON_FILE}" != "Voco" ]]; then
  echo "unexpected CFBundleIconFile: ${ICON_FILE}" >&2
  exit 1
fi

if ! file "${RESOURCES_DIR}/Voco.icns" | grep -q "Mac OS X icon"; then
  echo "unexpected icon file type: $(file "${RESOURCES_DIR}/Voco.icns")" >&2
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

"${MACOS_DIR}/Voco" &
APP_PID="$!"
sleep 1
if ! kill -0 "${APP_PID}" 2>/dev/null; then
  wait "${APP_PID}" || true
  echo "native app exited during launch" >&2
  exit 1
fi
kill "${APP_PID}" 2>/dev/null || true
wait "${APP_PID}" 2>/dev/null || true

echo "ok: native Voco.app bundle smoke passed"
