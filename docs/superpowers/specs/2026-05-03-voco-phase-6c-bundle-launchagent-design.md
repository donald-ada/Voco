---
title: Voco Phase 6-C — Bundle-Aware LaunchAgent Install
date: 2026-05-03
status: design-approved
target_platform: macOS 14+ user LaunchAgent
scope: Explicit Voco.app LaunchAgent install path
---

# Voco Phase 6-C — Bundle-Aware LaunchAgent Install 设计文档

## 1. Goal

Phase 6-C lets `voco daemon install` install a LaunchAgent that runs `voco-daemon` from a generated `Voco.app` bundle.

Phase 6-A made LaunchAgent lifecycle management real. Phase 6-B made `target/Voco.app` reproducible. Phase 6-C connects those two pieces with an explicit CLI option:

```bash
target/debug/voco daemon install --app-bundle target/Voco.app
```

This phase keeps source-tree development behavior intact. Running `voco daemon install` without `--app-bundle` continues to use the existing binary discovery path.

## 2. Scope

### In Scope

- Add `--app-bundle <path>` to `voco daemon install`.
- Validate the provided bundle path before rendering the LaunchAgent plist.
- Resolve the daemon binary as:

```text
<bundle>/Contents/MacOS/voco-daemon
```

- Resolve the LaunchAgent working directory as:

```text
<bundle>/Contents/MacOS
```

- Keep `voco daemon start`, `stop`, `restart`, `logs`, and `status` unchanged.
- Keep direct binary install behavior unchanged when `--app-bundle` is omitted.
- Add tests for bundle validation and rendered plist path selection.
- Update README and packaging docs with the bundle install flow.

### Out of Scope

- Auto-detecting `target/Voco.app` when `--app-bundle` is omitted.
- Copying `Voco.app` into `/Applications`.
- Code signing.
- Notarization.
- DMG/pkg creation.
- Changing the LaunchAgent label.
- Changing IPC socket, log, config, or credential paths.
- Running the app bundle through Finder or `open`.
- Replacing the separate Swift HUD helper process.

## 3. User-Facing Behavior

### Existing Behavior Remains

```bash
target/debug/voco daemon install
```

This keeps the Phase 6-A behavior: locate `voco-daemon` next to the current `voco` executable or on `PATH`, choose the source tree as `WorkingDirectory` when markers are present, and render `~/Library/LaunchAgents/com.voco.daemon.plist`.

### Bundle Install

```bash
packaging/build_app_bundle.sh --profile debug
target/debug/voco daemon install --app-bundle target/Voco.app
```

Expected successful output:

```text
✓ installed LaunchAgent: /Users/me/Library/LaunchAgents/com.voco.daemon.plist
  daemon: /path/to/Voco/target/Voco.app/Contents/MacOS/voco-daemon
  working directory: /path/to/Voco/target/Voco.app/Contents/MacOS
  start it with: voco daemon start
```

For idempotent installs, `installed` may be `updated` or `already installed`, matching the existing Phase 6-A wording. The daemon and working directory lines are still printed so the user can verify what was installed.

## 4. Bundle Validation

The command fails before writing the plist if any validation fails.

Required checks:

- Bundle path exists and is a directory.
- `Contents/Info.plist` exists and is a file.
- `Contents/MacOS/voco-daemon` exists and is executable.
- `Info.plist` has `CFBundleIdentifier = com.voco.app`.
- `Info.plist` has `CFBundleExecutable = voco-daemon`.

Error messages must name the exact failing path or plist key.

Examples:

```text
app bundle not found: target/Voco.app
missing app bundle Info.plist: target/Voco.app/Contents/Info.plist
missing executable in app bundle: target/Voco.app/Contents/MacOS/voco-daemon
unexpected CFBundleIdentifier in target/Voco.app/Contents/Info.plist: com.example.Other
unexpected CFBundleExecutable in target/Voco.app/Contents/Info.plist: OtherDaemon
```

The implementation should parse plist XML structurally rather than grepping. A small dependency is acceptable if the standard library path becomes brittle; however, because the existing project avoids extra packaging dependencies, the preferred first pass is a focused plist reader based on macOS `/usr/libexec/PlistBuddy` for CLI runtime and simple testable path logic in Rust. If tests need pure unit coverage, factor path resolution separately from plist probing.

## 5. CLI Shape

`DaemonAction::Install` changes from a unit variant to a struct-like variant:

```rust
Install {
    app_bundle: Option<PathBuf>,
}
```

The CLI help should expose:

```text
voco daemon install [--app-bundle <PATH>]
```

`--app-bundle` is install-only. It is not accepted for `start`, `stop`, or `restart`; those commands continue to consult whether the plist exists.

## 6. Internal Design

### Bundle Path Model

Add an internal type in `crates/voco-cli/src/commands/daemon/launch_agent.rs` or a sibling private module:

```rust
pub struct AppBundle {
    pub bundle_path: PathBuf,
    pub info_plist_path: PathBuf,
    pub daemon_path: PathBuf,
    pub working_dir: PathBuf,
}
```

Responsibilities:

- Canonicalize the supplied bundle path when possible.
- Derive `Contents/Info.plist`.
- Derive `Contents/MacOS`.
- Derive `Contents/MacOS/voco-daemon`.
- Validate existence and executability.
- Validate required plist keys.

### LaunchAgent Discovery

Keep the existing direct install:

```rust
let daemon_path = locate_daemon_binary()?;
LaunchAgent::discover(daemon_path)
```

Add a bundle install path:

```rust
let bundle = AppBundle::discover(path)?;
LaunchAgent::from_paths(bundle.daemon_path, bundle.working_dir)
```

The exact constructor name is flexible, but the result must produce the same `LaunchAgentPaths` shape used by `render_plist`.

### Working Directory

When `--app-bundle` is used, `WorkingDirectory` is always `Contents/MacOS`.

Reasoning:

- It makes daemon relative lookup stable inside the bundle.
- It avoids accidentally depending on the source repository root.
- It keeps the LaunchAgent self-contained from a path perspective, even though the bundle is still unsigned and development-only.

The daemon already resolves `voco-hud` next to its current executable before checking source-tree fallbacks, so a bundle install can find `Contents/MacOS/voco-hud` without changing daemon HUD code.

## 7. Error Handling

All bundle validation errors are fatal and happen before `install_plist`.

Rules:

- Missing path errors include the path.
- Plist key errors include the key name, expected value, and actual value when readable.
- Plist read/probe failures include the command or parser error.
- Existing LaunchAgent install/update error behavior remains unchanged.

No fallback from bundle install to direct binary install is allowed. If the user explicitly requested `--app-bundle`, an invalid bundle should fail loudly rather than silently installing a different daemon.

## 8. Testing Strategy

### Unit Tests

Required coverage:

- `DaemonAction` parses `daemon install --app-bundle target/Voco.app`.
- App bundle path resolution derives:
  - `Contents/Info.plist`;
  - `Contents/MacOS`;
  - `Contents/MacOS/voco-daemon`.
- Missing bundle directory fails.
- Missing `Info.plist` fails.
- Missing `voco-daemon` fails.
- Non-executable `voco-daemon` fails.
- Wrong `CFBundleIdentifier` fails.
- Wrong `CFBundleExecutable` fails.
- Bundle install renders plist with daemon path under `Voco.app/Contents/MacOS`.
- Bundle install renders `WorkingDirectory` as `Voco.app/Contents/MacOS`.
- Direct install behavior remains unchanged when `--app-bundle` is omitted.

### Integration / Smoke

Manual smoke on a development Mac:

```bash
target/debug/voco daemon uninstall || true
packaging/build_app_bundle.sh --profile debug
target/debug/voco daemon install --app-bundle target/Voco.app
plutil -lint ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" ~/Library/LaunchAgents/com.voco.daemon.plist
/usr/libexec/PlistBuddy -c "Print :WorkingDirectory" ~/Library/LaunchAgents/com.voco.daemon.plist
target/debug/voco daemon start
target/debug/voco status
target/debug/voco daemon stop
target/debug/voco daemon uninstall
```

Expected:

- plist lints cleanly;
- `ProgramArguments:0` points at `target/Voco.app/Contents/MacOS/voco-daemon`;
- `WorkingDirectory` points at `target/Voco.app/Contents/MacOS`;
- daemon starts through `launchctl`;
- IPC status reports running/idle;
- uninstall removes the plist.

### Full Verification

Before completion:

```bash
cd hud && swift test && swift build && cd ..
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
packaging/tests/app_bundle_smoke.sh
target/debug/voco daemon install --app-bundle target/Voco.app
plutil -lint ~/Library/LaunchAgents/com.voco.daemon.plist
target/debug/voco daemon uninstall
git diff --check
```

## 9. Documentation Updates

Update `README.md`:

- Add bundle-aware LaunchAgent install command.
- State that plain `daemon install` remains source-tree/direct binary mode.
- State that `--app-bundle` does not sign or copy the app.

Update `packaging/README.md`:

- Add the sequence:

```bash
packaging/build_app_bundle.sh --profile debug
target/debug/voco daemon install --app-bundle target/Voco.app
```

- Keep signing/notarization/DMG/pkg as deferred.

## 10. Open Decisions Resolved

- Bundle install is explicit: no auto-detection.
- CLI option name: `--app-bundle`.
- Bundle daemon path: `Contents/MacOS/voco-daemon`.
- Bundle working directory: `Contents/MacOS`.
- Direct install remains supported.
- Invalid explicit bundle install fails instead of falling back.
