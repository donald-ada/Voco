# Voco

Terminal-controlled local/cloud STT voice input tool for macOS.

See `docs/superpowers/specs/2026-05-01-voco-design.md` for the full design.

## Status

Phase 7 development: Phase 5 hotkey recording, text injection, and hidden Swift HUD helper are implemented. The daemon can be installed as a user-level LaunchAgent, and a generated `Voco.app` can be copied to `~/Applications/Voco.app` for per-user local installs.

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

Render the LaunchAgent from a development `Voco.app` bundle without copying the app:

```bash
packaging/build_app_bundle.sh --profile debug
target/debug/voco daemon install --app-bundle target/Voco.app
target/debug/voco daemon start
target/debug/voco status
```

Without `--app-bundle`, `daemon install` keeps the source-tree/direct binary
install path. `--app-bundle` is the lower-level plist render path and does not
copy the app bundle.

The plist is written to:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

Stop and remove the LaunchAgent:

```bash
target/debug/voco daemon stop
target/debug/voco daemon uninstall
```

## Development App Bundle

Build and install a local per-user app bundle:

```bash
packaging/build_app_bundle.sh --profile release
target/release/voco app install --app-bundle target/Voco.app
target/release/voco daemon start
target/release/voco status
```

`app install` copies the generated bundle to:

```text
~/Applications/Voco.app
```

It also installs or updates `~/Library/LaunchAgents/com.voco.daemon.plist`
so launchd runs:

```text
~/Applications/Voco.app/Contents/MacOS/voco-daemon
```

No `sudo` is required. This local install flow does not sign, notarize,
create a DMG/pkg, or install under `/Applications`.

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
