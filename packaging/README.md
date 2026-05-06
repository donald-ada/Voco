# packaging/

Packaging templates and development bundle scripts.

## Native App Shell

Build the native Swift/SwiftUI app shell:

```bash
packaging/build_native_app_bundle.sh --profile debug
```

The generated bundle is:

```text
target/native/Voco.app
```

It contains only the native app executable:

```text
Contents/Info.plist
Contents/MacOS/Voco
```

It does not contain the legacy CLI, daemon, or HUD helper binaries:

```text
Contents/MacOS/voco
Contents/MacOS/voco-daemon
Contents/MacOS/voco-hud
```

Run the native app bundle smoke test:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

This native app shell is the starting point for the rewrite. The older
LaunchAgent and development app bundle workflows remain documented below while
the native rewrite reaches feature parity.

## LaunchAgent

`com.voco.daemon.plist.tmpl` is rendered by:

```bash
target/debug/voco daemon install
```

The rendered plist is written to:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

Template variables:

```text
{{VOCO_DAEMON_PATH}} absolute path to voco-daemon
{{HOME}}             user home directory
{{WORKING_DIR}}      daemon working directory
```

Phase 6-A uses a user-level LaunchAgent and does not require `sudo`.

## Development App Bundle

Build an unsigned local `Voco.app` bundle:

```bash
packaging/build_app_bundle.sh --profile debug
```

The generated bundle is:

```text
target/Voco.app
```

It contains:

```text
Contents/Info.plist
Contents/MacOS/voco
Contents/MacOS/voco-daemon
Contents/MacOS/voco-hud
```

Install the generated bundle for the current user:

```bash
target/debug/voco app install --app-bundle target/Voco.app
```

The command copies the bundle to:

```text
~/Applications/Voco.app
```

and renders `~/Library/LaunchAgents/com.voco.daemon.plist` so
`ProgramArguments:0` points at:

```text
~/Applications/Voco.app/Contents/MacOS/voco-daemon
```

For development-only plist rendering without copying the app, this lower-level
command remains available:

```bash
target/debug/voco daemon install --app-bundle target/Voco.app
```

Run the bundle smoke test:

```bash
packaging/tests/app_bundle_smoke.sh
```

Signing, notarization, DMG/pkg creation, and `/Applications` installation are
deferred.
