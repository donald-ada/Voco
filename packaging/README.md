# packaging/

Native packaging scripts for the Swift/SwiftUI Voco app.

## Native App Bundle

The native Swift/SwiftUI app bundle and DMG are the user-facing install path.
The native app uses macOS Login Items and must not install the legacy
`~/Library/LaunchAgents/com.voco.daemon.plist` plist.

Build the native Swift/SwiftUI app bundle:

```bash
packaging/build_native_app_bundle.sh --profile debug
```

The build script automatically prepares the pinned SherpaOnnx static runtime in
local cache when it is missing.

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

`dist/` is generated output and is ignored by Git. Do not commit app bundles,
disk images, staging directories, or signing/notarization credentials.

Run the native DMG smoke test:

```bash
packaging/tests/native_dmg_smoke.sh
```

To verify the release-profile adhoc path locally:

```bash
packaging/tests/native_dmg_smoke.sh --profile release
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

## GitHub Releases

Pushing a `v*` tag triggers `.github/workflows/release-dmg.yml`, which runs the
native Swift test suite, builds a `release` profile ad-hoc signed `Voco.dmg`,
and publishes `dist/Voco.dmg` to the matching GitHub Release.

## Native Migration Cleanup

Native Voco detects the legacy user LaunchAgent at:

```text
~/Library/LaunchAgents/com.voco.daemon.plist
```

When present, Settings shows a migration warning and an explicit removal action.
The cleanup path removes only that known user-level plist, never touches
`/Library/LaunchAgents`, and never requires `sudo`. If removal fails, the app
surfaces the exact path and the underlying OS error.
