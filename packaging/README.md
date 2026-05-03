# packaging/

Packaging templates and development bundle scripts.

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

Run the bundle smoke test:

```bash
packaging/tests/app_bundle_smoke.sh
```

Signing, notarization, DMG/pkg creation, `/Applications` installation, and
LaunchAgent integration with the app bundle are deferred.
