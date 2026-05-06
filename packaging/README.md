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

Build a local ad-hoc signed DMG for smoke testing:

```bash
packaging/build_native_dmg.sh --profile debug --signing-style adhoc
```

The generated release staging artifacts are:

```text
dist/Voco.app
dist/Voco.dmg
```

Run the native DMG smoke test:

```bash
packaging/tests/native_dmg_smoke.sh
```

The DMG smoke test uses only local ad-hoc signing. It does not require
Developer ID certificates, Apple ID credentials, or network access. It verifies
the copied app signature, the DMG checksum, the DMG code signature, and the
mounted volume shape:

```text
Voco.app
Applications -> /Applications
```

Build a Developer ID signed release DMG:

```bash
VOCO_DEVELOPER_ID_APPLICATION="Developer ID Application: Example Team (TEAMID)" \
packaging/build_native_dmg.sh --profile release --signing-style developer-id
```

The app bundle is signed with hardened runtime and timestamping. DMG signing
uses `VOCO_DEVELOPER_ID_DMG` when set, otherwise it falls back to
`VOCO_DEVELOPER_ID_APPLICATION`:

```bash
VOCO_DEVELOPER_ID_APPLICATION="Developer ID Application: Example Team (TEAMID)" \
VOCO_DEVELOPER_ID_DMG="Developer ID Application: Example Team (TEAMID)" \
packaging/build_native_dmg.sh --profile release --signing-style developer-id
```

Missing release signing inputs fail before the build starts. Set the env vars
above or pass `--app-signing-identity` and `--dmg-signing-identity`.

Notarize and staple the signed DMG with a stored notarytool profile:

```bash
VOCO_NOTARYTOOL_PROFILE="voco-release" \
packaging/notarize_native_dmg.sh --dmg dist/Voco.dmg
```

Or use Apple ID credentials directly:

```bash
VOCO_NOTARYTOOL_APPLE_ID="user@example.com" \
VOCO_NOTARYTOOL_TEAM_ID="TEAMID" \
VOCO_NOTARYTOOL_PASSWORD="app-specific-password" \
packaging/notarize_native_dmg.sh --dmg dist/Voco.dmg
```

Create a stored profile with:

```bash
xcrun notarytool store-credentials "voco-release" --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
```

Release verification commands:

```bash
codesign --verify --deep --strict dist/Voco.app
spctl --assess --type execute --verbose=4 dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
xcrun stapler validate dist/Voco.dmg
spctl --assess --type open --verbose=4 dist/Voco.dmg
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

Native signing, notarization, and DMG creation are handled by the native app
commands above. Legacy pkg creation and `/Applications` installation remain
deferred.
