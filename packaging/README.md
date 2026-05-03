# packaging/

LaunchAgent template and future bundle assets.

## com.voco.daemon.plist.tmpl

`voco daemon install` renders this template to:

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

`Voco.app`, signing, notarization, and installer packaging are deferred.
