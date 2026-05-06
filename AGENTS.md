# Repository Guidelines

## Project Structure & Module Organization

Voco is a macOS voice input tool with a Rust workspace and a Swift HUD helper.
Rust crates live under `crates/`: `voco-cli` owns command-line flows, `voco-daemon`
owns background orchestration, `voco-config` stores configuration schema and IO,
`voco-ipc` defines protocol/client/server code, and audio/ASR/hotkey/injection
logic is split into dedicated crates. SwiftUI HUD code is in `hud/Sources`, with
XCTest coverage in `hud/Tests`. Packaging templates and bundle smoke tests live
in `packaging/`; design specs and implementation plans live in `docs/superpowers/`.

## Build, Test, and Development Commands

- `cargo build --workspace`: builds all Rust crates in debug mode.
- `cargo build --release --workspace`: builds optimized release binaries.
- `cargo fmt --all -- --check`: verifies Rust formatting.
- `cargo clippy --workspace --all-targets -- -D warnings`: runs Rust lint gates.
- `cargo test --workspace --all-targets`: runs Rust unit and integration tests.
- `swift test` and `swift build` from `hud/`: test and build the HUD helper.
- `packaging/build_app_bundle.sh --profile debug`: creates `target/Voco.app`.
- `packaging/tests/app_bundle_smoke.sh`: verifies the generated app bundle shape.

For local daemon work, build first, then run `target/debug/voco daemon start`,
`target/debug/voco status`, and `target/debug/voco daemon stop`.

## Coding Style & Naming Conventions

Rust uses edition 2021 with the pinned stable toolchain in `rust-toolchain.toml`.
Run `cargo fmt --all` before committing. Prefer crate-local modules and existing
workspace dependencies over ad hoc helpers. Use snake_case for Rust modules,
functions, and tests; use PascalCase for Rust types and Swift types. Swift code
follows Swift Package Manager defaults and keeps HUD core logic in
`VocoHUDCore` for testability.

## Testing Guidelines

Add or update tests with behavior changes. Rust integration tests belong in
`crates/<crate>/tests`; focused unit tests may stay beside implementation code.
Swift tests belong in `hud/Tests/VocoHUDTests`. Live microphone or network tests
must be ignored or explicitly opt-in, and should fail with clear error messages
when required environment or macOS permissions are missing.

## Commit & Pull Request Guidelines

Recent commits use short imperative subjects such as `Add notch transcript island`
or `Polish notch HUD edge blending`. Keep subjects concise and scoped. PRs should
include a summary, verification commands run, user-visible behavior changes, and
screenshots or recordings for HUD/UI changes. Link related issues or specs when
applicable, especially changes tied to `docs/superpowers/`.

## Security & Configuration Tips

Do not commit credentials, local ASR tokens, generated bundles, or `target/`
artifacts. User-level installs should not require `sudo`; LaunchAgent output is
expected under `~/Library/LaunchAgents/com.voco.daemon.plist`.
