# Voco

Terminal-controlled local/cloud STT voice input tool for macOS.

See `docs/superpowers/specs/2026-05-01-voco-design.md` for the full design.

## Status

Phase 6-A development: Phase 5 hotkey recording, text injection, and hidden Swift HUD helper are implemented. Phase 6-A adds a user-level LaunchAgent so the daemon can be installed under `~/Library/LaunchAgents` and managed by `launchctl`.

## Build

```sh
cargo build --workspace
cd hud && swift build && cd ..
```

## Development Daemon

Without installing the LaunchAgent, `voco daemon start` keeps the direct-spawn development workflow:

```bash
target/debug/voco daemon start
target/debug/voco status
target/debug/voco daemon stop
```

## LaunchAgent Install

Install the user LaunchAgent without `sudo`:

```bash
target/debug/voco daemon install
target/debug/voco daemon start
target/debug/voco status
```

The plist is written to:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

Stop and remove the LaunchAgent:

```bash
target/debug/voco daemon stop
target/debug/voco daemon uninstall
```

`Voco.app` bundling, signing, notarization, and installer packaging remain future work.

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
