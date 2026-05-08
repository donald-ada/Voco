# Repository Guidelines

## Project Structure & Module Organization

Voco is a macOS voice input tool. The current user-facing product is the native
SwiftUI menu bar app under `native/`: `native/Sources/VocoApp` owns AppKit/SwiftUI
UI, menu bar, Keychain, permissions, HUD overlay, Dock/menu bar presentation,
and macOS integration; `native/Sources/VocoAppCore` owns testable workflow,
settings, transcription, hotkey, audio, permission, and injection models.
Native XCTest coverage lives under `native/Tests`.

The older Rust workspace under `crates/` remains for legacy daemon/CLI reference:
`voco-cli` owns command-line flows, `voco-daemon` owns background orchestration,
`voco-config` stores legacy configuration schema and IO, `voco-ipc` defines
protocol/client/server code, and audio/ASR/hotkey/injection logic is split into
dedicated crates. The standalone Swift HUD helper under `hud/` is also legacy
reference now that the native app owns the HUD overlay. Packaging scripts and
bundle/DMG smoke tests live in `packaging/`.

## Build, Test, and Development Commands

- `swift build --package-path native`: builds the native SwiftUI app.
- `swift test --package-path native`: runs native app and core XCTest suites.
- `packaging/build_native_app_bundle.sh --profile debug`: creates
  `target/native/Voco.app`.
- `packaging/tests/native_app_bundle_smoke.sh`: verifies the native app bundle.
- `packaging/build_native_dmg.sh --profile debug --signing-style adhoc`: creates
  `dist/Voco.dmg` for local smoke testing.
- `cargo build --workspace`: builds all Rust crates in debug mode.
- `cargo build --release --workspace`: builds optimized release binaries.
- `cargo fmt --all -- --check`: verifies Rust formatting.
- `cargo clippy --workspace --all-targets -- -D warnings`: runs Rust lint gates.
- `cargo test --workspace --all-targets`: runs Rust unit and integration tests.
- `swift test` and `swift build` from `hud/`: test and build the legacy HUD helper.
- `packaging/build_app_bundle.sh --profile debug`: creates the legacy
  `target/Voco.app` bundle.
- `packaging/tests/app_bundle_smoke.sh`: verifies the legacy bundle shape.

For local daemon work, build first, then run `target/debug/voco daemon start`,
`target/debug/voco status`, and `target/debug/voco daemon stop`.

## Coding Style & Naming Conventions

Rust uses edition 2021 with the pinned stable toolchain in `rust-toolchain.toml`.
Run `cargo fmt --all` before committing Rust changes. Prefer crate-local modules
and existing workspace dependencies over ad hoc helpers. Use snake_case for Rust
modules, functions, and tests; use PascalCase for Rust and Swift types. Native
Swift code follows Swift Package Manager defaults and keeps behavior in
`VocoAppCore` where practical so UI, AppKit adapters, and persistence remain
thin and testable.

## Testing Guidelines

Add or update tests with behavior changes. Native Swift tests belong in
`native/Tests/VocoAppCoreTests` for model/workflow behavior and
`native/Tests/VocoAppTests` for app adapters, persistence, typography, and UI
support logic. Rust integration tests belong in `crates/<crate>/tests`; focused
unit tests may stay beside implementation code. Legacy HUD tests belong in
`hud/Tests/VocoHUDTests`. Live microphone or network tests must be skipped or
explicitly opt-in, and should fail with clear error messages when required
environment, credentials, or macOS permissions are missing.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects such as `Add notch transcript island`
or `Polish notch HUD edge blending`. Keep subjects concise and scoped. PRs should
include a summary, verification commands run, user-visible behavior changes, and
screenshots or recordings for HUD/UI changes. Link related issues or specs when
applicable, especially changes tied to `docs/superpowers/`.

## Security & Configuration Tips

Do not commit credentials, local ASR tokens, generated bundles, DMGs, or
`target/` artifacts. Native Volcengine credentials are entered through the
Settings > Model UI and stored in macOS Keychain; the native app should not read
local config files for user credentials. User-level installs should not require
`sudo`. The native app uses macOS Login Items for launch-at-login; the legacy
LaunchAgent path `~/Library/LaunchAgents/com.voco.daemon.plist` is retained only
for migration cleanup and legacy daemon development.
