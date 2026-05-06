#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/notarize_native_dmg.sh --dmg <path>

Submits a Developer ID signed native Voco DMG for notarization, waits for the
result, staples the ticket, and validates the stapled disk image.

Credentials must be provided with either:
  VOCO_NOTARYTOOL_PROFILE

or all of:
  VOCO_NOTARYTOOL_APPLE_ID
  VOCO_NOTARYTOOL_TEAM_ID
  VOCO_NOTARYTOOL_PASSWORD
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

DMG_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      DMG_PATH="$2"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${DMG_PATH}" ]]; then
  echo "missing required --dmg <path>" >&2
  usage
  exit 64
fi

if [[ "${DMG_PATH}" != /* ]]; then
  DMG_PATH="${REPO_ROOT}/${DMG_PATH}"
fi

if [[ ! -f "${DMG_PATH}" ]]; then
  fail "missing DMG to notarize: ${DMG_PATH}; run packaging/build_native_dmg.sh --profile release --signing-style developer-id first"
fi

NOTARY_PROFILE="${VOCO_NOTARYTOOL_PROFILE:-}"
NOTARY_APPLE_ID="${VOCO_NOTARYTOOL_APPLE_ID:-}"
NOTARY_TEAM_ID="${VOCO_NOTARYTOOL_TEAM_ID:-}"
NOTARY_PASSWORD="${VOCO_NOTARYTOOL_PASSWORD:-}"

if [[ -n "${NOTARY_PROFILE}" ]]; then
  NOTARY_ARGS=(xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait)
elif [[ -n "${NOTARY_APPLE_ID}" && -n "${NOTARY_TEAM_ID}" && -n "${NOTARY_PASSWORD}" ]]; then
  NOTARY_ARGS=(xcrun notarytool submit "${DMG_PATH}" --apple-id "${NOTARY_APPLE_ID}" --team-id "${NOTARY_TEAM_ID}" --password "${NOTARY_PASSWORD}" --wait)
else
  cat >&2 <<'EOF'
missing notarization credentials
set VOCO_NOTARYTOOL_PROFILE for an xcrun notarytool keychain profile
or set all of VOCO_NOTARYTOOL_APPLE_ID, VOCO_NOTARYTOOL_TEAM_ID, and VOCO_NOTARYTOOL_PASSWORD

Create a reusable profile with:
  xcrun notarytool store-credentials "voco-release" --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
EOF
  exit 65
fi

require_tool xcrun
require_tool spctl
require_tool codesign

if ! codesign --verify --strict "${DMG_PATH}"; then
  fail "DMG is not code-signed or signature verification failed before notarization: ${DMG_PATH}"
fi

echo "ok: submitting DMG for notarization: ${DMG_PATH}"
if ! "${NOTARY_ARGS[@]}"; then
  fail "xcrun notarytool submit failed for DMG: ${DMG_PATH}; inspect the submission with xcrun notarytool history or xcrun notarytool log"
fi

if ! xcrun stapler staple "${DMG_PATH}"; then
  fail "xcrun stapler staple failed for DMG: ${DMG_PATH}"
fi

if ! xcrun stapler validate "${DMG_PATH}"; then
  fail "xcrun stapler validate failed for DMG: ${DMG_PATH}"
fi

if ! spctl --assess --type open --verbose=4 "${DMG_PATH}"; then
  fail "spctl Gatekeeper open assessment failed for DMG: ${DMG_PATH}"
fi

echo "ok: notarized and stapled native DMG: ${DMG_PATH}"
