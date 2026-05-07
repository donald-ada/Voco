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

if [[ ! -s "${RESOURCES_DIR}/VocoMenuBarIconTemplate.svg" ]]; then
  echo "missing menu bar icon: ${RESOURCES_DIR}/VocoMenuBarIconTemplate.svg" >&2
  exit 1
fi

for font_file in \
  IBMPlexSans-Regular.ttf \
  IBMPlexSans-Medium.ttf \
  IBMPlexSans-SemiBold.ttf \
  IBMPlexSans-Bold.ttf \
  IBMPlexMono-Regular.ttf \
  IBMPlexMono-Medium.ttf \
  IBMPlexMono-SemiBold.ttf
do
  if [[ ! -s "${RESOURCES_DIR}/Fonts/${font_file}" ]]; then
    echo "missing settings font: ${RESOURCES_DIR}/Fonts/${font_file}" >&2
    exit 1
  fi
done

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

ICON_PNG="${REPO_ROOT}/target/native/icon-work/Voco.iconset/icon_512x512@2x.png"
if [[ ! -f "${ICON_PNG}" ]]; then
  echo "missing generated icon PNG: ${ICON_PNG}" >&2
  exit 1
fi

python3 - "${ICON_PNG}" <<'PY'
import struct
import sys
import zlib

path = sys.argv[1]
with open(path, "rb") as icon_file:
    data = icon_file.read()

if not data.startswith(b"\x89PNG\r\n\x1a\n"):
    print(f"generated icon is not a PNG: {path}", file=sys.stderr)
    sys.exit(1)

offset = 8
ihdr = None
idat = []
while offset < len(data):
    if offset + 8 > len(data):
        print(f"truncated PNG chunk in {path}", file=sys.stderr)
        sys.exit(1)
    length = struct.unpack(">I", data[offset:offset + 4])[0]
    chunk_type = data[offset + 4:offset + 8]
    chunk_data = data[offset + 8:offset + 8 + length]
    offset += 12 + length
    if chunk_type == b"IHDR":
        ihdr = chunk_data
    elif chunk_type == b"IDAT":
        idat.append(chunk_data)
    elif chunk_type == b"IEND":
        break

if ihdr is None or not idat:
    print(f"missing PNG image data in {path}", file=sys.stderr)
    sys.exit(1)

width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(">IIBBBBB", ihdr)
if bit_depth != 8 or color_type not in (2, 6) or compression != 0 or filter_method != 0 or interlace != 0:
    print(f"unsupported generated icon PNG format: bit_depth={bit_depth}, color_type={color_type}, interlace={interlace}", file=sys.stderr)
    sys.exit(1)

channels = 4 if color_type == 6 else 3
stride = width * channels
raw = zlib.decompress(b"".join(idat))

def paeth(left, up, upper_left):
    p = left + up - upper_left
    pa = abs(p - left)
    pb = abs(p - up)
    pc = abs(p - upper_left)
    if pa <= pb and pa <= pc:
        return left
    if pb <= pc:
        return up
    return upper_left

rows = []
cursor = 0
previous = bytearray(stride)
for _ in range(height):
    filter_type = raw[cursor]
    cursor += 1
    current = bytearray(raw[cursor:cursor + stride])
    cursor += stride
    for i in range(stride):
        left = current[i - channels] if i >= channels else 0
        up = previous[i]
        upper_left = previous[i - channels] if i >= channels else 0
        if filter_type == 1:
            current[i] = (current[i] + left) & 0xff
        elif filter_type == 2:
            current[i] = (current[i] + up) & 0xff
        elif filter_type == 3:
            current[i] = (current[i] + ((left + up) // 2)) & 0xff
        elif filter_type == 4:
            current[i] = (current[i] + paeth(left, up, upper_left)) & 0xff
        elif filter_type != 0:
            print(f"unsupported PNG filter type: {filter_type}", file=sys.stderr)
            sys.exit(1)
    rows.append(current)
    previous = current

def rgba_at(x, y):
    start = x * channels
    row = rows[y]
    red, green, blue = row[start:start + 3]
    alpha = row[start + 3] if channels == 4 else 255
    return red, green, blue, alpha

sample_points = {
    "top-left": (0, 0),
    "top": (width // 2, 0),
    "left": (0, height // 2),
    "right": (width - 1, height // 2),
    "bottom": (width // 2, height - 1),
    "inner-top-left": (32, 32),
    "inner-top": (width // 2, 32),
    "inner-left": (32, height // 2),
}
white_points = []
for name, (x, y) in sample_points.items():
    red, green, blue, alpha = rgba_at(x, y)
    if alpha > 0 and min(red, green, blue) >= 245:
        white_points.append(f"{name}=rgba({red},{green},{blue},{alpha})")

if white_points:
    print("generated app icon has a white outer canvas: " + ", ".join(white_points), file=sys.stderr)
    sys.exit(1)
PY

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
