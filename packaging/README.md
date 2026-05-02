# packaging/

LaunchAgent template + bundle assets.

## com.voco.daemon.plist.tmpl

Templated LaunchAgent. Phase 6 will:
1. Substitute `{{VOCO_DAEMON_PATH}}` and `{{HOME}}`
2. Write to `~/Library/LaunchAgents/com.voco.daemon.plist`
3. `launchctl load -w ~/Library/LaunchAgents/com.voco.daemon.plist`

For now (Phase 1) the daemon is started with `voco daemon start`,
which spawns the process directly.
