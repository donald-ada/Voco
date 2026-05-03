# Voco

Terminal-controlled local/cloud STT voice input tool for macOS.

See `docs/superpowers/specs/2026-05-01-voco-design.md` for the full design.

## Status

Phase 5 development branch: Phase 4 hotkey recording and text injection are implemented; Phase 5 adds a hidden Swift HUD helper.

## Build

```sh
cargo build --release
```

## Phase 5 HUD Development

Build the Swift HUD helper before running the daemon from source:

```bash
cd hud
swift build
cd ..
cargo build --workspace
```

During development, `voco-daemon` resolves `hud/.build/debug/voco-hud` and starts it hidden. The HUD window remains hidden while idle and appears only while recording, transcribing, or showing an error.

## License

MIT
