---
title: Voco Phase 6-B — Development App Bundle
date: 2026-05-03
status: design-approved
target_platform: macOS 14+ development bundle
scope: Local Voco.app bundle skeleton
---

# Voco Phase 6-B — Development App Bundle 设计文档

## 1. Goal

Phase 6-B adds a repeatable development build path for `Voco.app`.

The output is a local `.app` bundle that can be inspected by macOS tooling and contains the three executable artifacts Voco already builds today:

- `voco`
- `voco-daemon`
- `voco-hud`

This phase does not change the runtime process model. The Rust daemon still owns hotkey/audio/ASR/injection and still starts the separate Swift HUD helper when launched from source. Phase 6-B only creates the bundle skeleton needed before install, signing, notarization, or distribution work.

## 2. Scope

### In Scope

- Add a repeatable packaging script under `packaging/`.
- Add an `Info.plist` template for `Voco.app`.
- Build or reuse debug/release Rust binaries from `target/<profile>/`.
- Build or reuse the Swift HUD binary from `hud/.build/<configuration>/`.
- Copy binaries into:

```text
target/Voco.app/Contents/MacOS/
```

- Render:

```text
target/Voco.app/Contents/Info.plist
```

- Make copied executables executable.
- Add shell-level verification that the bundle contains expected files and that `plutil -lint` accepts the rendered plist.
- Document the development bundle command in `README.md` and `packaging/README.md`.

### Out of Scope

- Code signing.
- Notarization.
- DMG or pkg creation.
- Installing the `.app` under `/Applications`.
- Changing `voco daemon install` to point at `Voco.app/Contents/MacOS/voco-daemon`.
- Replacing the Phase 5 separate Swift HUD helper.
- Merging Rust and Swift into a single process.
- Adding a menu bar UI.

## 3. User-Facing Behavior

The developer command is:

```bash
packaging/build_app_bundle.sh --profile debug
```

The script creates:

```text
target/Voco.app
```

Expected successful output includes the bundle path and the copied binary paths:

```text
✓ built Rust workspace: debug
✓ built Swift HUD: debug
✓ wrote target/Voco.app/Contents/Info.plist
✓ copied target/debug/voco
✓ copied target/debug/voco-daemon
✓ copied hud/.build/debug/voco-hud
✓ verified Voco.app bundle
```

Release profile is supported:

```bash
packaging/build_app_bundle.sh --profile release
```

For SwiftPM, `--profile release` maps to Swift configuration `release`; every other accepted value maps to Rust and Swift `debug` or `release` exactly. Invalid profile names fail before any build command runs.

## 4. Bundle Layout

The generated bundle layout is:

```text
target/Voco.app/
└── Contents/
    ├── Info.plist
    └── MacOS/
        ├── voco
        ├── voco-daemon
        └── voco-hud
```

The bundle does not include resources in this phase. An empty `Resources/` directory is not required because there are no icons, localizations, entitlements, or model assets being packaged yet.

## 5. Info.plist Contract

The template path is:

```text
packaging/Voco.app/Contents/Info.plist.tmpl
```

The rendered plist includes:

```xml
<key>CFBundleIdentifier</key>
<string>com.voco.app</string>
<key>CFBundleName</key>
<string>Voco</string>
<key>CFBundleDisplayName</key>
<string>Voco</string>
<key>CFBundleExecutable</key>
<string>voco-daemon</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
<key>LSUIElement</key>
<true/>
<key>NSMicrophoneUsageDescription</key>
<string>Voco needs microphone access to transcribe your speech into text.</string>
```

`CFBundleExecutable` points at `voco-daemon` because the app bundle represents the background voice input service, not the CLI. The CLI is still included in `Contents/MacOS/voco` for development inspection and future install plumbing.

## 6. Packaging Script

Create:

```text
packaging/build_app_bundle.sh
```

Responsibilities:

- Resolve the repository root from the script path.
- Parse `--profile debug` and `--profile release`.
- Run `cargo build --workspace --profile <profile>` for Rust.
- Run `swift build -c <configuration>` inside `hud/`.
- Remove any previous `target/Voco.app` before recreating it.
- Create `Contents/MacOS`.
- Render the plist template to `Contents/Info.plist`.
- Copy the three binaries.
- Run `chmod 755` on copied binaries.
- Verify:
  - `target/Voco.app/Contents/Info.plist` exists;
  - all three executables exist and are executable;
  - `plutil -lint target/Voco.app/Contents/Info.plist` succeeds.

The script fails loud: command failures stop the script, missing binaries print the exact missing path, and invalid profile names print usage.

## 7. Testing Strategy

### Automated Checks

Add focused shell smoke coverage that runs the packaging script with `--profile debug` and verifies the expected bundle files.

The smoke test must not launch the app, request TCC permissions, install LaunchAgents, or write outside the repository. It only inspects files under `target/Voco.app`.

Required checks:

```bash
test -x target/Voco.app/Contents/MacOS/voco
test -x target/Voco.app/Contents/MacOS/voco-daemon
test -x target/Voco.app/Contents/MacOS/voco-hud
plutil -lint target/Voco.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" target/Voco.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :LSUIElement" target/Voco.app/Contents/Info.plist
```

### Full Verification

Before completion:

```bash
cd hud && swift test && swift build && cd ..
cargo fmt --all --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
packaging/build_app_bundle.sh --profile debug
plutil -lint target/Voco.app/Contents/Info.plist
git diff --check
```

## 8. Documentation Updates

Update `README.md` with a short Development App Bundle section:

```bash
packaging/build_app_bundle.sh --profile debug
open target/Voco.app
```

The documentation must state that this is a development bundle and is not signed, notarized, or installed as a LaunchAgent.

Update `packaging/README.md` to list:

- LaunchAgent template from Phase 6-A.
- Development `Voco.app` bundle script from Phase 6-B.
- Deferred signing/notarization/installer work.

## 9. Open Decisions Resolved

- Build output path: `target/Voco.app`.
- Bundle identifier: `com.voco.app`.
- Bundle executable: `voco-daemon`.
- Included development binaries: `voco`, `voco-daemon`, `voco-hud`.
- No icon in Phase 6-B.
- No signing or installation in Phase 6-B.
