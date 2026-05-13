#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VENDOR_ROOT="${REPO_ROOT}/native/Vendor/SherpaOnnx"
LINK_DIR="${VENDOR_ROOT}/lib"

SHERPA_ONNX_VERSION="${VOCO_SHERPA_ONNX_VERSION:-1.13.0}"
CACHE_ROOT="${VOCO_SHERPA_ONNX_CACHE_DIR:-${HOME}/Library/Caches/Voco/sherpa-onnx}/${SHERPA_ONNX_VERSION}"

case "$(uname -m)" in
  arm64)
    HOST_ARCH="arm64"
    ;;
  x86_64)
    HOST_ARCH="x86_64"
    ;;
  *)
    echo "unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

ARCH_CACHE_ROOT="${CACHE_ROOT}/${HOST_ARCH}"
ARCH_LIB_DIR="${ARCH_CACHE_ROOT}/lib"
TARGET_SHERPA_LIB="${ARCH_LIB_DIR}/libsherpa-onnx.a"
TARGET_ONNX_LIB="${ARCH_LIB_DIR}/libonnxruntime.a"
SOURCE_TARBALL_URL="https://github.com/k2-fsa/sherpa-onnx/archive/refs/tags/v${SHERPA_ONNX_VERSION}.tar.gz"

require_tool() {
  local tool_name="$1"
  if ! command -v "${tool_name}" >/dev/null 2>&1; then
    echo "missing required tool: ${tool_name}" >&2
    exit 1
  fi
}

link_runtime() {
  mkdir -p "${LINK_DIR}"
  ln -sfn "${TARGET_SHERPA_LIB}" "${LINK_DIR}/libsherpa-onnx.a"
  ln -sfn "${TARGET_ONNX_LIB}" "${LINK_DIR}/libonnxruntime.a"
}

if [[ -f "${TARGET_SHERPA_LIB}" && -f "${TARGET_ONNX_LIB}" ]]; then
  link_runtime
  echo "ok: reusing cached SherpaOnnx runtime (${SHERPA_ONNX_VERSION}, ${HOST_ARCH})"
  exit 0
fi

for tool_name in curl tar cmake libtool xcodebuild; do
  require_tool "${tool_name}"
done

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voco-sherpa-build.XXXXXX")"
cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

ARCHIVE_PATH="${TEMP_DIR}/sherpa-onnx-v${SHERPA_ONNX_VERSION}.tar.gz"
SOURCE_ROOT="${TEMP_DIR}/source"
BUILD_ROOT="${TEMP_DIR}/build"
INSTALL_ROOT="${TEMP_DIR}/install"
STAGING_ROOT="${TEMP_DIR}/staging"
PARALLELISM="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)"

echo "info: downloading SherpaOnnx source v${SHERPA_ONNX_VERSION} for ${HOST_ARCH}"
curl --fail --location --silent --show-error "${SOURCE_TARBALL_URL}" --output "${ARCHIVE_PATH}"

mkdir -p "${SOURCE_ROOT}"
tar -xzf "${ARCHIVE_PATH}" -C "${SOURCE_ROOT}"
SOURCE_DIR="$(find "${SOURCE_ROOT}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [[ -z "${SOURCE_DIR}" ]]; then
  echo "failed to extract SherpaOnnx source archive: ${ARCHIVE_PATH}" >&2
  exit 1
fi

mkdir -p "${BUILD_ROOT}"
cmake \
  -S "${SOURCE_DIR}" \
  -B "${BUILD_ROOT}" \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF \
  -DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
  -DCMAKE_OSX_ARCHITECTURES="${HOST_ARCH}" \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_ROOT}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
  -DSHERPA_ONNX_ENABLE_TESTS=OFF \
  -DSHERPA_ONNX_ENABLE_CHECK=OFF \
  -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
  -DSHERPA_ONNX_ENABLE_JNI=OFF \
  -DSHERPA_ONNX_ENABLE_C_API=ON \
  -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF

echo "info: building SherpaOnnx runtime (this can take a while on first run)"
cmake --build "${BUILD_ROOT}" --parallel "${PARALLELISM}"
cmake --install "${BUILD_ROOT}"

COMPONENT_LIBS=(
  "${INSTALL_ROOT}/lib/libsherpa-onnx-c-api.a"
  "${INSTALL_ROOT}/lib/libsherpa-onnx-core.a"
  "${INSTALL_ROOT}/lib/libkaldi-native-fbank-core.a"
  "${INSTALL_ROOT}/lib/libkissfft-float.a"
  "${INSTALL_ROOT}/lib/libsherpa-onnx-fstfar.a"
  "${INSTALL_ROOT}/lib/libsherpa-onnx-fst.a"
  "${INSTALL_ROOT}/lib/libsherpa-onnx-kaldifst-core.a"
  "${INSTALL_ROOT}/lib/libkaldi-decoder-core.a"
  "${INSTALL_ROOT}/lib/libucd.a"
  "${INSTALL_ROOT}/lib/libpiper_phonemize.a"
  "${INSTALL_ROOT}/lib/libespeak-ng.a"
  "${INSTALL_ROOT}/lib/libssentencepiece_core.a"
)

for component_lib in "${COMPONENT_LIBS[@]}"; do
  if [[ ! -f "${component_lib}" ]]; then
    echo "missing expected SherpaOnnx static library: ${component_lib}" >&2
    exit 1
  fi
done

if [[ ! -f "${INSTALL_ROOT}/lib/libonnxruntime.a" ]]; then
  echo "missing expected ONNX Runtime static library: ${INSTALL_ROOT}/lib/libonnxruntime.a" >&2
  exit 1
fi

mkdir -p "${STAGING_ROOT}/lib"
libtool -static -o "${STAGING_ROOT}/lib/libsherpa-onnx.a" "${COMPONENT_LIBS[@]}"
cp "${INSTALL_ROOT}/lib/libonnxruntime.a" "${STAGING_ROOT}/lib/libonnxruntime.a"

mkdir -p "${ARCH_CACHE_ROOT}"
rm -rf "${ARCH_LIB_DIR}"
mv "${STAGING_ROOT}/lib" "${ARCH_LIB_DIR}"

link_runtime
echo "ok: prepared SherpaOnnx runtime (${SHERPA_ONNX_VERSION}, ${HOST_ARCH})"
