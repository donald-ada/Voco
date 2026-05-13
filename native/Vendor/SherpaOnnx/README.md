# SherpaOnnx Runtime

This directory vendors the `CSherpaOnnx` module map, shim, and pinned
`c-api.h` header used by the native macOS app.

The static runtime libraries are no longer committed to git. They are prepared
locally on demand by:

```bash
native/scripts/ensure_sherpa_onnx_runtime.sh
```

The script:

1. Downloads `sherpa-onnx` source for the pinned version.
2. Builds a macOS static runtime for the current host architecture.
3. Caches the results under `~/Library/Caches/Voco/sherpa-onnx/`.
4. Recreates `native/Vendor/SherpaOnnx/lib/` as symlinks into that cache.

Generated artifacts:

- `lib/libsherpa-onnx.a`
- `lib/libonnxruntime.a`

The ASR model files are still not vendored here. Users download the recommended
model on demand into Application Support.
