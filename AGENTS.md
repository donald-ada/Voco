# Repository Guidelines

## Language

All assistant responses to the user must be in Chinese. Keep code identifiers,
commands, API names, and file paths in their original form.

User-facing README content should support both Chinese and English unless the
user explicitly asks for one language only.

## Project Structure

Voco is a macOS voice input app. The current product is the native SwiftUI menu
bar app under `native/`.

- `native/Sources/VocoApp`: AppKit/SwiftUI UI, settings window, menu bar,
  Keychain integration, permissions, HUD overlay, Dock/menu bar presentation,
  statistics dashboard, and macOS adapters.
- `native/Sources/VocoAppCore`: testable app workflow, settings models,
  transcription models, hotkey/audio/permission/injection state, recent session
  history, and statistics aggregation.
- `native/Tests`: XCTest coverage for app adapters, UI support logic, model
  behavior, workflow behavior, persistence, typography, and statistics.
- `packaging/`: app bundle, DMG, signing, and smoke test scripts.
- `prototypes/`: local UI prototypes used for design exploration.

Avoid adding new user-facing behavior to non-native app paths. Keep current
development focused on the native macOS app.

## Build, Test, and Development Commands

- `swift build --package-path native`: builds the macOS app.
- `swift test --package-path native`: runs native app and core XCTest suites.
- `packaging/build_native_app_bundle.sh --profile debug`: creates
  `target/native/Voco.app`.
- `packaging/tests/native_app_bundle_smoke.sh`: verifies the generated app
  bundle, resources, signing shape, and launch smoke.
- `packaging/build_native_dmg.sh --profile debug --signing-style adhoc`: creates
  `dist/Voco.dmg` for local smoke testing.
- `packaging/build_native_dmg.sh --profile release --signing-style developer-id`:
  creates a Developer ID release DMG when signing identity variables are set.

For UI changes, build the native bundle and launch `target/native/Voco.app` when
the user needs to inspect the result locally.

## Coding Style

Native Swift code follows Swift Package Manager defaults. Prefer keeping
testable behavior in `VocoAppCore` so SwiftUI views, AppKit adapters, Keychain
adapters, and persistence code remain thin.

Use PascalCase for Swift types and lowerCamelCase for Swift properties,
methods, and test helpers. Keep view files pragmatic: small helper views are
acceptable near the feature they support, but split code when a file starts
mixing unrelated workflows.

Prefer existing project models and helpers over new ad hoc utilities. For
structured data, use typed models instead of string parsing.

## UI Guidelines

The settings workbench uses a restrained native macOS dashboard style. Preserve
the existing spacing, typography, card radius, subtle borders, and compact
information density.

For the statistics dashboard:

- Keep the left content column and right information column independent.
- Use adaptive layout for compact chart rows; do not force two cards into one
  row when the width is insufficient.
- Keep repeated chart rows and bars on stable dimensions to avoid resize
  jank.
- Prefer `Canvas` for simple high-frequency charts when it reduces SwiftUI view
  tree churn.
- Do not show design-process notes, field-mapping notes, or implementation
  rationale inside the app UI.

## Testing Guidelines

Add or update tests with behavior changes. Use a failing test first when a
change can be expressed as model, policy, layout-policy, or adapter behavior.

- `native/Tests/VocoAppCoreTests`: model and workflow behavior.
- `native/Tests/VocoAppTests`: app adapters, persistence, typography, UI support
  logic, window behavior, and layout policy.

Live microphone or network tests must be skipped by default or explicitly
opt-in. They should fail loudly with clear messages when required credentials,
environment variables, or macOS permissions are missing.

Before claiming work is complete, run the narrow relevant test first, then run
the broader verification that matches the change. For app-facing changes, prefer:

```bash
swift test --package-path native
packaging/build_native_app_bundle.sh --profile debug
packaging/tests/native_app_bundle_smoke.sh
git diff --check
```

## Documentation Guidelines

Keep `README.md` focused on the current product, installation, permissions,
development commands, and project structure. Do not add retired architecture
notes or inactive implementation paths unless the user explicitly asks for
archive documentation.

When updating documentation, keep commands runnable from the repository root and
avoid mentioning generated artifacts as files to commit.

## Security & Configuration

Do not commit credentials, local ASR tokens, generated bundles, DMGs, or
`target/` artifacts.

Volcengine credentials are entered through `Settings > Model` and stored in
macOS Keychain. The app should not read user credentials from local config files.

User-level installs should not require `sudo`. Launch-at-login is managed by
macOS Login Items from the native app.

## Commit & Pull Request Guidelines

Use concise imperative commit subjects such as `Add statistics dashboard` or
`Polish settings layout`. PRs should include a summary, verification commands,
user-visible behavior changes, and screenshots or recordings for UI changes.
