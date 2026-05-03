# Voco Phase 6-B App Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a repeatable development `target/Voco.app` bundle containing `voco`, `voco-daemon`, `voco-hud`, and a valid macOS `Info.plist`.

**Architecture:** Keep packaging as a focused shell layer under `packaging/` instead of adding product CLI surface. The bundle script builds the existing Rust workspace and Swift HUD, renders a static plist template, copies binaries into `Contents/MacOS`, and verifies the bundle with macOS plist tooling. Runtime behavior does not change in this phase.

**Tech Stack:** Bash, Cargo, SwiftPM, `plutil`, `/usr/libexec/PlistBuddy`, GitHub Actions on `macos-14`.

---

## File Structure

- Create: `packaging/Voco.app/Contents/Info.plist.tmpl` — canonical `Voco.app` plist template.
- Create: `packaging/build_app_bundle.sh` — repeatable bundle build script.
- Create: `packaging/tests/app_bundle_smoke.sh` — shell smoke test for the generated bundle.
- Modify: `.github/workflows/ci.yml` — run Swift HUD tests/build and app bundle smoke on macOS CI.
- Modify: `README.md` — document development app bundle usage.
- Modify: `packaging/README.md` — document Phase 6-A LaunchAgent and Phase 6-B app bundle assets.
- Modify: `docs/superpowers/specs/2026-05-03-voco-phase-6b-app-bundle-design.md` — correct the Rust debug build command.

## Task 1: Bundle Smoke Test

**Files:**
- Create: `packaging/tests/app_bundle_smoke.sh`

- [ ] **Step 1: Create the failing smoke test**

Create `packaging/tests/app_bundle_smoke.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUNDLE_PATH="${REPO_ROOT}/target/Voco.app"
INFO_PLIST="${BUNDLE_PATH}/Contents/Info.plist"
MACOS_DIR="${BUNDLE_PATH}/Contents/MacOS"

"${REPO_ROOT}/packaging/build_app_bundle.sh" --profile debug

test -d "${BUNDLE_PATH}"
test -f "${INFO_PLIST}"
test -x "${MACOS_DIR}/voco"
test -x "${MACOS_DIR}/voco-daemon"
test -x "${MACOS_DIR}/voco-hud"

plutil -lint "${INFO_PLIST}" >/dev/null

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${INFO_PLIST}")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${INFO_PLIST}")"
LS_UI_ELEMENT="$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "${INFO_PLIST}")"
MIC_USAGE="$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "${INFO_PLIST}")"

if [[ "${BUNDLE_ID}" != "com.voco.app" ]]; then
  echo "unexpected CFBundleIdentifier: ${BUNDLE_ID}" >&2
  exit 1
fi

if [[ "${EXECUTABLE}" != "voco-daemon" ]]; then
  echo "unexpected CFBundleExecutable: ${EXECUTABLE}" >&2
  exit 1
fi

if [[ "${LS_UI_ELEMENT}" != "true" ]]; then
  echo "unexpected LSUIElement: ${LS_UI_ELEMENT}" >&2
  exit 1
fi

if [[ -z "${MIC_USAGE}" ]]; then
  echo "NSMicrophoneUsageDescription must not be empty" >&2
  exit 1
fi

echo "ok: Voco.app bundle smoke passed"
```

- [ ] **Step 2: Make the smoke test executable**

Run:

```bash
chmod 755 packaging/tests/app_bundle_smoke.sh
```

Expected: command exits with status 0.

- [ ] **Step 3: Run the smoke test and confirm it fails for the right reason**

Run:

```bash
packaging/tests/app_bundle_smoke.sh
```

Expected: FAIL because `packaging/build_app_bundle.sh` does not exist yet.

- [ ] **Step 4: Commit the red test**

```bash
git add packaging/tests/app_bundle_smoke.sh
git commit -m "test(packaging): add app bundle smoke test"
```

## Task 2: Info.plist Template

**Files:**
- Create: `packaging/Voco.app/Contents/Info.plist.tmpl`

- [ ] **Step 1: Create the plist template directory**

Run:

```bash
mkdir -p packaging/Voco.app/Contents
```

Expected: directory exists.

- [ ] **Step 2: Add the Info.plist template**

Create `packaging/Voco.app/Contents/Info.plist.tmpl`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>

  <key>CFBundleDisplayName</key>
  <string>Voco</string>

  <key>CFBundleExecutable</key>
  <string>voco-daemon</string>

  <key>CFBundleIdentifier</key>
  <string>com.voco.app</string>

  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>

  <key>CFBundleName</key>
  <string>Voco</string>

  <key>CFBundlePackageType</key>
  <string>APPL</string>

  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>

  <key>CFBundleVersion</key>
  <string>0.1.0</string>

  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>

  <key>LSUIElement</key>
  <true/>

  <key>NSMicrophoneUsageDescription</key>
  <string>Voco needs microphone access to transcribe your speech into text.</string>
</dict>
</plist>
```

- [ ] **Step 3: Verify the template is valid plist XML**

Run:

```bash
plutil -lint packaging/Voco.app/Contents/Info.plist.tmpl
```

Expected: `OK`.

- [ ] **Step 4: Commit the template**

```bash
git add packaging/Voco.app/Contents/Info.plist.tmpl
git commit -m "feat(packaging): add Voco app plist template"
```

## Task 3: Bundle Build Script

**Files:**
- Create: `packaging/build_app_bundle.sh`

- [ ] **Step 1: Create the build script**

Create `packaging/build_app_bundle.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: packaging/build_app_bundle.sh --profile <debug|release>

Builds target/Voco.app for local development.
USAGE
}

PROFILE="debug"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

case "${PROFILE}" in
  debug)
    RUST_BUILD_ARGS=(build --workspace)
    RUST_BIN_DIR="debug"
    SWIFT_CONFIG="debug"
    ;;
  release)
    RUST_BUILD_ARGS=(build --workspace --release)
    RUST_BIN_DIR="release"
    SWIFT_CONFIG="release"
    ;;
  *)
    echo "invalid profile: ${PROFILE}" >&2
    usage
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUNDLE_PATH="${REPO_ROOT}/target/Voco.app"
CONTENTS_DIR="${BUNDLE_PATH}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
PLIST_TEMPLATE="${REPO_ROOT}/packaging/Voco.app/Contents/Info.plist.tmpl"
INFO_PLIST="${CONTENTS_DIR}/Info.plist"

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "missing required file: ${path}" >&2
    exit 66
  fi
}

require_executable() {
  local path="$1"
  if [[ ! -x "${path}" ]]; then
    echo "missing executable: ${path}" >&2
    exit 66
  fi
}

require_file "${PLIST_TEMPLATE}"

cd "${REPO_ROOT}"
cargo "${RUST_BUILD_ARGS[@]}"
echo "✓ built Rust workspace: ${PROFILE}"

cd "${REPO_ROOT}/hud"
swift build -c "${SWIFT_CONFIG}"
echo "✓ built Swift HUD: ${SWIFT_CONFIG}"

RUST_OUTPUT_DIR="${REPO_ROOT}/target/${RUST_BIN_DIR}"
HUD_BINARY="${REPO_ROOT}/hud/.build/${SWIFT_CONFIG}/voco-hud"

require_executable "${RUST_OUTPUT_DIR}/voco"
require_executable "${RUST_OUTPUT_DIR}/voco-daemon"
require_executable "${HUD_BINARY}"

rm -rf "${BUNDLE_PATH}"
mkdir -p "${MACOS_DIR}"

cp "${PLIST_TEMPLATE}" "${INFO_PLIST}"
echo "✓ wrote target/Voco.app/Contents/Info.plist"

cp "${RUST_OUTPUT_DIR}/voco" "${MACOS_DIR}/voco"
echo "✓ copied target/${RUST_BIN_DIR}/voco"

cp "${RUST_OUTPUT_DIR}/voco-daemon" "${MACOS_DIR}/voco-daemon"
echo "✓ copied target/${RUST_BIN_DIR}/voco-daemon"

cp "${HUD_BINARY}" "${MACOS_DIR}/voco-hud"
echo "✓ copied hud/.build/${SWIFT_CONFIG}/voco-hud"

chmod 755 "${MACOS_DIR}/voco" "${MACOS_DIR}/voco-daemon" "${MACOS_DIR}/voco-hud"

require_file "${INFO_PLIST}"
require_executable "${MACOS_DIR}/voco"
require_executable "${MACOS_DIR}/voco-daemon"
require_executable "${MACOS_DIR}/voco-hud"
plutil -lint "${INFO_PLIST}" >/dev/null

echo "✓ verified Voco.app bundle: target/Voco.app"
```

- [ ] **Step 2: Make the build script executable**

Run:

```bash
chmod 755 packaging/build_app_bundle.sh
```

Expected: command exits with status 0.

- [ ] **Step 3: Run the bundle smoke test and confirm it passes**

Run:

```bash
packaging/tests/app_bundle_smoke.sh
```

Expected: PASS and output ends with `ok: Voco.app bundle smoke passed`.

- [ ] **Step 4: Verify release profile argument reaches the build script parser**

Run:

```bash
packaging/build_app_bundle.sh --profile release
```

Expected: PASS and `target/Voco.app/Contents/MacOS/voco-daemon` exists.

- [ ] **Step 5: Verify invalid profiles fail before building**

Run:

```bash
packaging/build_app_bundle.sh --profile staging
```

Expected: FAIL with `invalid profile: staging`.

- [ ] **Step 6: Commit the build script**

```bash
git add packaging/build_app_bundle.sh
git commit -m "feat(packaging): build development app bundle"
```

## Task 4: Documentation

**Files:**
- Modify: `README.md`
- Modify: `packaging/README.md`

- [ ] **Step 1: Update README with development bundle instructions**

Modify `README.md` by adding this section after `LaunchAgent Install`:

````markdown
## Development App Bundle

Build a local unsigned development bundle:

```bash
packaging/build_app_bundle.sh --profile debug
```

The bundle is written to:

```text
target/Voco.app
```

This bundle contains `voco`, `voco-daemon`, and `voco-hud` under `Contents/MacOS`.
It is not signed, notarized, installed under `/Applications`, or used by the
LaunchAgent installer yet.
````

- [ ] **Step 2: Update packaging README**

Replace `packaging/README.md` with:

````markdown
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
````

- [ ] **Step 3: Verify documentation mentions both Phase 6-A and 6-B assets**

Run:

```bash
rg -n "Development App Bundle|build_app_bundle|Voco.app|LaunchAgent|not signed|notarized|deferred" README.md packaging/README.md
```

Expected: output includes the new README section and the packaging README sections.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md packaging/README.md
git commit -m "docs(packaging): document development app bundle"
```

## Task 5: CI Integration

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add Swift and packaging checks to CI**

Modify `.github/workflows/ci.yml` so the job steps become:

```yaml
      - name: fmt
        run: cargo fmt --all -- --check
      - name: clippy
        run: cargo clippy --workspace --all-targets -- -D warnings
      - name: test
        run: cargo test --workspace --all-targets
      - name: build release
        run: cargo build --release --workspace
      - name: swift test
        run: swift test
        working-directory: hud
      - name: swift build
        run: swift build
        working-directory: hud
      - name: app bundle smoke
        run: packaging/tests/app_bundle_smoke.sh
```

- [ ] **Step 2: Run the packaging smoke locally**

Run:

```bash
packaging/tests/app_bundle_smoke.sh
```

Expected: PASS.

- [ ] **Step 3: Commit CI integration**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: verify Swift HUD and app bundle"
```

## Task 6: Final Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-03-voco-phase-6b-app-bundle.md`

- [ ] **Step 1: Run Swift verification**

Run:

```bash
cd hud && swift test && swift build && cd ..
```

Expected: Swift tests pass and `voco-hud` builds.

- [ ] **Step 2: Run Rust formatting**

Run:

```bash
cargo fmt --all --check
```

Expected: PASS.

- [ ] **Step 3: Run Rust tests**

Run:

```bash
cargo test --workspace
```

Expected: PASS.

- [ ] **Step 4: Run Rust clippy**

Run:

```bash
cargo clippy --workspace --all-targets -- -D warnings
```

Expected: PASS.

- [ ] **Step 5: Run app bundle debug smoke**

Run:

```bash
packaging/tests/app_bundle_smoke.sh
```

Expected: PASS and `target/Voco.app` contains all three executables.

- [ ] **Step 6: Lint rendered Info.plist**

Run:

```bash
plutil -lint target/Voco.app/Contents/Info.plist
```

Expected: `OK`.

- [ ] **Step 7: Check for whitespace errors**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 8: Mark verification in this plan**

Update this plan with a dated verification note under this task:

```markdown
Verification note (2026-05-03):

- `cd hud && swift test && swift build && cd ..` passed.
- `cargo fmt --all --check` passed.
- `cargo test --workspace` passed.
- `cargo clippy --workspace --all-targets -- -D warnings` passed.
- `packaging/tests/app_bundle_smoke.sh` passed.
- `plutil -lint target/Voco.app/Contents/Info.plist` passed.
- `git diff --check` passed.
```

- [ ] **Step 9: Commit verification update**

```bash
git add docs/superpowers/plans/2026-05-03-voco-phase-6b-app-bundle.md
git commit -m "docs: mark Phase 6-B app bundle verification"
```

- [ ] **Step 10: Finish branch or confirm direct master completion**

If work happened on a feature branch, merge or open a PR using `superpowers:finishing-a-development-branch`.

If work happened directly on `master`, confirm:

```bash
git status --short --branch
git log --oneline -8
```

Expected: `master` is clean and recent commits include Phase 6-B app bundle work.

## Self-Review

- Spec coverage: bundle script, plist template, binary copy layout, plist validation, documentation, and non-signing scope are covered by Tasks 1-6.
- Placeholder scan: no unresolved placeholder markers or unspecified implementation steps.
- Type and path consistency: all tasks use `target/Voco.app`, `packaging/build_app_bundle.sh`, `packaging/tests/app_bundle_smoke.sh`, and `packaging/Voco.app/Contents/Info.plist.tmpl`.
