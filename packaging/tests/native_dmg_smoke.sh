#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/tests/native_dmg_smoke.sh [--profile <debug|release>]
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
  debug|release)
    ;;
  *)
    echo "invalid profile: ${PROFILE}" >&2
    usage
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DMG_PATH="${REPO_ROOT}/dist/Voco.dmg"
DIST_APP="${REPO_ROOT}/dist/Voco.app"
MOUNT_DIR="${REPO_ROOT}/target/native/dmg-smoke-mount"
DANGEROUS_DMG_DIR="${REPO_ROOT}/target/native/dangerous-output.dmg"
DANGEROUS_SENTINEL="${DANGEROUS_DMG_DIR}/sentinel.txt"
MOUNTED=0

cleanup() {
  if [[ "${MOUNTED}" -eq 1 ]]; then
    hdiutil detach "${MOUNT_DIR}" -quiet || hdiutil detach "${MOUNT_DIR}" -force -quiet || true
  fi
  rm -rf "${MOUNT_DIR}"
  rm -rf "${DANGEROUS_DMG_DIR}"
}

trap cleanup EXIT

rm -rf "${DANGEROUS_DMG_DIR}"
mkdir -p "${DANGEROUS_DMG_DIR}"
printf 'must survive rejected --dmg directory paths\n' > "${DANGEROUS_SENTINEL}"

set +e
DANGEROUS_OUTPUT="$("${REPO_ROOT}/packaging/build_native_dmg.sh" --profile "${PROFILE}" --signing-style adhoc --dmg "${DANGEROUS_DMG_DIR}" 2>&1)"
DANGEROUS_STATUS="$?"
set -e

if [[ "${DANGEROUS_STATUS}" -eq 0 ]]; then
  echo "dangerous --dmg directory path was accepted: ${DANGEROUS_DMG_DIR}" >&2
  exit 1
fi

if [[ ! -f "${DANGEROUS_SENTINEL}" ]]; then
  echo "dangerous --dmg directory path deleted existing directory contents: ${DANGEROUS_DMG_DIR}" >&2
  printf '%s\n' "${DANGEROUS_OUTPUT}" >&2
  exit 1
fi

if ! printf '%s\n' "${DANGEROUS_OUTPUT}" | grep -q '\.dmg'; then
  echo "dangerous --dmg rejection did not explain the .dmg path requirement" >&2
  printf '%s\n' "${DANGEROUS_OUTPUT}" >&2
  exit 1
fi

"${REPO_ROOT}/packaging/build_native_dmg.sh" --profile "${PROFILE}" --signing-style adhoc

if [[ ! -f "${DMG_PATH}" ]]; then
  echo "missing DMG: ${DMG_PATH}" >&2
  exit 1
fi

if [[ ! -d "${DIST_APP}" ]]; then
  echo "missing distributable app copy: ${DIST_APP}" >&2
  exit 1
fi

codesign --verify --deep --strict "${DIST_APP}"
hdiutil verify "${DMG_PATH}" >/dev/null
codesign --verify --strict "${DMG_PATH}"

rm -rf "${MOUNT_DIR}"
mkdir -p "${MOUNT_DIR}"
hdiutil attach "${DMG_PATH}" -nobrowse -readonly -mountpoint "${MOUNT_DIR}" >/dev/null
MOUNTED=1

MOUNTED_APP="${MOUNT_DIR}/Voco.app"
MOUNTED_MACOS_DIR="${MOUNTED_APP}/Contents/MacOS"

if [[ ! -x "${MOUNTED_MACOS_DIR}/Voco" ]]; then
  echo "missing mounted executable: ${MOUNTED_MACOS_DIR}/Voco" >&2
  exit 1
fi

if [[ ! -L "${MOUNT_DIR}/Applications" ]]; then
  echo "missing Applications symlink in mounted DMG: ${MOUNT_DIR}/Applications" >&2
  exit 1
fi

APPLICATIONS_TARGET="$(readlink "${MOUNT_DIR}/Applications")"
if [[ "${APPLICATIONS_TARGET}" != "/Applications" ]]; then
  echo "unexpected Applications symlink target: ${APPLICATIONS_TARGET}" >&2
  exit 1
fi

for entry in "${MOUNTED_MACOS_DIR}"/*; do
  name="$(basename "${entry}")"
  case "${name}" in
    voco|voco-daemon|voco-hud)
      echo "legacy executable must not be present in mounted DMG: ${name}" >&2
      exit 1
      ;;
  esac
done

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${MOUNTED_APP}/Contents/Info.plist")"
if [[ "${BUNDLE_ID}" != "com.voco.app" ]]; then
  echo "unexpected mounted CFBundleIdentifier: ${BUNDLE_ID}" >&2
  exit 1
fi

UNTRACKED_DIST="$(git -C "${REPO_ROOT}" status --short --untracked-files=all -- dist)"
if printf '%s\n' "${UNTRACKED_DIST}" | grep -q '^?? '; then
  echo "native DMG smoke left untracked dist artifacts:" >&2
  printf '%s\n' "${UNTRACKED_DIST}" >&2
  exit 1
fi

echo "ok: native Voco.dmg smoke passed: profile=${PROFILE}"
