# Voco

Terminal-controlled local/cloud STT voice input tool for macOS.

See `docs/superpowers/specs/2026-05-01-voco-design.md` for the full design.

## Status

Native rewrite development: Voco now has a native macOS menu bar app with
onboarding, Settings, Diagnostics, Keychain-backed credentials, audio capture,
hotkey recording, Volcengine model transcription, text injection, HUD overlay,
launch at login, and native release packaging. The user-facing install path is
the native `Voco.app` distributed through `dist/Voco.dmg`.

The older Rust CLI/daemon, user LaunchAgent template, and Swift HUD helper
packaging remain in the repository for development reference until the final
feature-parity and manual UX gate passes. They are not the native user install
path.

## Native Build

```sh
cd native
swift build
swift test
```

Build a local native app bundle and run the bundle smoke test:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

## Native Install

Build a native DMG for local smoke testing:

```bash
packaging/build_native_dmg.sh --profile debug --signing-style adhoc
open dist/Voco.dmg
```

For a Developer ID release build:

```bash
VOCO_DEVELOPER_ID_APPLICATION="Developer ID Application: Example Team (TEAMID)" \
packaging/build_native_dmg.sh --profile release --signing-style developer-id
```

Open the DMG, drag `Voco.app` to `/Applications`, then launch Voco from the app.
Grant the requested macOS permissions during onboarding. Login behavior is
managed by the native app through macOS Login Items; the native app does not
install `~/Library/LaunchAgents/com.voco.daemon.plist`.

## Migration Cleanup

If an older development install left this user-level LaunchAgent behind:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

the native Settings window shows a migration warning and offers an explicit
remove action. Cleanup removes only that known plist path, never touches
`/Library/LaunchAgents`, and does not require `sudo`. Any removal failure shows
the exact path and OS error.

## Legacy Development Archive

The commands below are retained for development and historical verification of
the pre-native architecture. Do not use them as the native user install path.

### Development Daemon

Without installing the LaunchAgent, `voco daemon start` keeps the direct-spawn
development workflow:

```bash
target/debug/voco daemon start
target/debug/voco status
target/debug/voco daemon stop
```

### Legacy LaunchAgent Install

Install the legacy user LaunchAgent without `sudo`:

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

### Legacy Development App Bundle

Build and install a local legacy per-user app bundle:

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

No `sudo` is required. This legacy local install flow does not sign, notarize,
create a DMG/pkg, or install under `/Applications`.

### Phase 5 HUD Development

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
