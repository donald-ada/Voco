# Voco Native Release Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a native release packaging path that can build `Voco.app`, create `Voco.dmg`, and notarize/staple the DMG when Developer ID credentials are available.

**Architecture:** Keep the existing debug/ad-hoc app bundle flow available for local smoke tests, then add explicit release signing and DMG scripts around the native Swift app bundle. Release-only paths require Developer ID and notarization inputs and fail before doing destructive work when inputs are missing.

**Tech Stack:** Bash, SwiftPM, macOS `codesign`, `spctl`, `hdiutil`, `xcrun notarytool`, `xcrun stapler`, existing shell smoke tests.

---

## File Structure

- Modify: `packaging/build_native_app_bundle.sh` - add signing style and hardened runtime release signing inputs while preserving debug ad-hoc defaults.
- Create: `packaging/build_native_dmg.sh` - build/copy `dist/Voco.app`, stage an `/Applications` symlink, create `dist/Voco.dmg`, and sign the DMG when requested.
- Create: `packaging/notarize_native_dmg.sh` - submit `dist/Voco.dmg` to Apple notary service, wait for completion, staple, and validate.
- Create: `packaging/tests/native_dmg_smoke.sh` - credential-free local smoke test for an ad-hoc DMG and mounted volume shape.
- Modify: `packaging/README.md` - document debug DMG, release signing, notarization, and failure modes.
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-release-packaging.md` - append verification evidence before completion.

## Task 1: Native Release Bundle Build Flags

**Files:**
- Modify: `packaging/build_native_app_bundle.sh`
- Test: `packaging/tests/native_app_bundle_smoke.sh`

- [ ] **Step 1: Preserve the existing debug smoke baseline**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
```

Expected: PASS, proving the default debug/ad-hoc path still works before release flags are added.

- [ ] **Step 2: Add explicit signing style flags**

Add arguments to `packaging/build_native_app_bundle.sh`:

```text
--profile <debug|release>
--signing-style <adhoc|developer-id>
--signing-identity <identity>
```

Expected behavior:

```text
debug + adhoc: default local behavior, no Developer ID inputs required
release + adhoc: local release build smoke path, no timestamp or notarization assumptions
release + developer-id: require Developer ID Application identity
```

Missing release identity must fail with:

```text
missing Developer ID Application signing identity
set VOCO_DEVELOPER_ID_APPLICATION or pass --signing-identity "Developer ID Application: ..."
```

- [ ] **Step 3: Verify bundle flag behavior**

Run:

```bash
packaging/build_native_app_bundle.sh --profile release --signing-style adhoc
codesign --verify --deep --strict target/native/Voco.app
```

Expected: PASS without Apple credentials.

## Task 2: Developer ID Signing Inputs

**Files:**
- Modify: `packaging/build_native_app_bundle.sh`
- Create: `packaging/build_native_dmg.sh`

- [ ] **Step 1: Require explicit app signing identity for Developer ID app bundles**

Use `VOCO_DEVELOPER_ID_APPLICATION` when `--signing-style developer-id` is selected and `--signing-identity` is omitted.

Run:

```bash
env -u VOCO_DEVELOPER_ID_APPLICATION packaging/build_native_app_bundle.sh --profile release --signing-style developer-id
```

Expected: FAIL before signing with a message naming `VOCO_DEVELOPER_ID_APPLICATION` and `--signing-identity`.

- [ ] **Step 2: Support a separate DMG signing identity**

`packaging/build_native_dmg.sh --signing-style developer-id` must read `VOCO_DEVELOPER_ID_DMG` first and fall back to `VOCO_DEVELOPER_ID_APPLICATION`.

Run:

```bash
env -u VOCO_DEVELOPER_ID_DMG -u VOCO_DEVELOPER_ID_APPLICATION packaging/build_native_dmg.sh --profile release --signing-style developer-id
```

Expected: FAIL before building with a message naming `VOCO_DEVELOPER_ID_APPLICATION`, `VOCO_DEVELOPER_ID_DMG`, and `--dmg-signing-identity`.

## Task 3: Hardened Runtime Verification

**Files:**
- Modify: `packaging/build_native_app_bundle.sh`
- Create: `packaging/build_native_dmg.sh`

- [ ] **Step 1: Sign Developer ID app bundles with hardened runtime**

When `--signing-style developer-id` is selected, sign `target/native/Voco.app` with:

```bash
codesign --force --deep --options runtime --timestamp --sign "${identity}" target/native/Voco.app
```

Expected: `codesign --display --verbose=4 target/native/Voco.app` reports `runtime` in the flags.

- [ ] **Step 2: Add release verification commands to the DMG script output**

After a Developer ID DMG build, print the follow-up verification commands:

```bash
codesign --verify --deep --strict dist/Voco.app
spctl --assess --type execute --verbose=4 dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
```

Expected: release operators can copy the commands exactly after the script finishes.

## Task 4: DMG Creation with Applications Alias

**Files:**
- Create: `packaging/build_native_dmg.sh`
- Create: `packaging/tests/native_dmg_smoke.sh`

- [ ] **Step 1: Run the missing smoke test RED**

Run:

```bash
packaging/tests/native_dmg_smoke.sh
```

Expected: FAIL because the script does not exist yet.

- [ ] **Step 2: Build a local DMG**

`packaging/build_native_dmg.sh --profile debug --signing-style adhoc` must:

```text
build target/native/Voco.app
copy it to dist/Voco.app
stage dist/dmg-root/Voco.app
stage dist/dmg-root/Applications -> /Applications
create dist/Voco.dmg with hdiutil
verify dist/Voco.dmg with hdiutil verify
```

Expected: `dist/Voco.dmg` is present and mountable without Apple credentials.

- [ ] **Step 3: Assert mounted DMG structure in smoke**

`packaging/tests/native_dmg_smoke.sh` must attach the DMG read-only and check:

```text
<mount>/Voco.app/Contents/MacOS/Voco is executable
<mount>/Applications is a symlink to /Applications
no legacy voco, voco-daemon, or voco-hud executable is present
```

Expected: PASS for an ad-hoc debug DMG.

## Task 5: DMG Signing

**Files:**
- Create: `packaging/build_native_dmg.sh`
- Test: `packaging/tests/native_dmg_smoke.sh`

- [ ] **Step 1: Keep ad-hoc DMG signing local**

For `--signing-style adhoc`, attempt:

```bash
codesign --force --sign - dist/Voco.dmg
```

Then verify with:

```bash
codesign --verify --strict dist/Voco.dmg
```

If ad-hoc disk image signing is unsupported on the host, fail loudly with the exact command and path.

- [ ] **Step 2: Sign Developer ID DMGs with timestamp**

For `--signing-style developer-id`, run:

```bash
codesign --force --timestamp --sign "${dmg_identity}" dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
```

Expected: missing identity errors identify the env vars and CLI flags that can fix the issue.

## Task 6: Notarization and Stapling

**Files:**
- Create: `packaging/notarize_native_dmg.sh`
- Modify: `packaging/README.md`

- [ ] **Step 1: Validate notarization inputs before network calls**

`packaging/notarize_native_dmg.sh` accepts:

```text
--dmg <path>
```

It must use either:

```text
VOCO_NOTARYTOOL_PROFILE
```

or all of:

```text
VOCO_NOTARYTOOL_APPLE_ID
VOCO_NOTARYTOOL_TEAM_ID
VOCO_NOTARYTOOL_PASSWORD
```

Expected: missing inputs fail before `notarytool submit` and list the exact accepted env var combinations.

- [ ] **Step 2: Submit, staple, and validate**

Run when credentials are available:

```bash
packaging/notarize_native_dmg.sh --dmg dist/Voco.dmg
xcrun stapler validate dist/Voco.dmg
spctl --assess --type open --verbose=4 dist/Voco.dmg
```

Expected: notary submission succeeds, stapler validates, and Gatekeeper assessment passes.

## Task 7: Release Verification Smoke Tests

**Files:**
- Create: `packaging/tests/native_dmg_smoke.sh`
- Modify: `packaging/README.md`

- [ ] **Step 1: Run credential-free verification**

Run:

```bash
packaging/tests/native_app_bundle_smoke.sh
packaging/tests/native_dmg_smoke.sh
git diff --check
```

Expected: all commands pass without Apple credentials.

- [ ] **Step 2: Run Developer ID verification when credentials exist**

Run:

```bash
codesign --verify --deep --strict dist/Voco.app
spctl --assess --type execute --verbose=4 dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
xcrun stapler validate dist/Voco.dmg
spctl --assess --type open --verbose=4 dist/Voco.dmg
```

Expected: all commands pass for a signed and notarized release DMG.

## Task 8: Documentation and Failure Messages

**Files:**
- Modify: `packaging/README.md`
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-release-packaging.md`

- [ ] **Step 1: Document local and release commands**

Add README sections for:

```text
debug native DMG build
release Developer ID app and DMG build
notarization with keychain profile
notarization with Apple ID/team/password
release verification commands
```

Expected: docs clearly say debug smoke tests do not require Developer ID credentials.

- [ ] **Step 2: Record final verification evidence**

Append completion notes to this plan with:

```text
RED result for missing native_dmg_smoke.sh
GREEN result for native_app_bundle_smoke.sh
GREEN result for native_dmg_smoke.sh
GREEN result for git diff --check
Developer ID/notarization verification status
```

Expected: the task can be audited from the plan without generated artifacts committed.

---

## Completion Notes

Implementation commits created before this verification note:

```text
77fc90d docs(native): plan release packaging
47c37d0 feat(packaging): build native dmg
a71c093 feat(packaging): verify native release artifacts
```

This verification note is committed separately as:

```text
docs(native): mark release packaging verification
```

RED evidence:

```text
packaging/tests/native_dmg_smoke.sh
exit 127: zsh:1: no such file or directory: packaging/tests/native_dmg_smoke.sh

packaging/tests/native_dmg_smoke.sh after adding the smoke test only
exit 1: packaging/build_native_dmg.sh: No such file or directory

packaging/notarize_native_dmg.sh --dmg dist/Voco.dmg
exit 127: zsh:1: no such file or directory: packaging/notarize_native_dmg.sh
```

Credential failure evidence:

```text
env -u VOCO_DEVELOPER_ID_APPLICATION packaging/build_native_app_bundle.sh --profile release --signing-style developer-id
exit 65:
missing Developer ID Application signing identity
set VOCO_DEVELOPER_ID_APPLICATION or pass --signing-identity "Developer ID Application: ..."

env -u VOCO_DEVELOPER_ID_DMG -u VOCO_DEVELOPER_ID_APPLICATION packaging/build_native_dmg.sh --profile release --signing-style developer-id
exit 65:
missing Developer ID signing identity for native DMG build
set VOCO_DEVELOPER_ID_APPLICATION for app signing
optionally set VOCO_DEVELOPER_ID_DMG for DMG signing
or pass --app-signing-identity and --dmg-signing-identity explicitly

env -u VOCO_NOTARYTOOL_PROFILE -u VOCO_NOTARYTOOL_APPLE_ID -u VOCO_NOTARYTOOL_TEAM_ID -u VOCO_NOTARYTOOL_PASSWORD packaging/notarize_native_dmg.sh --dmg dist/Voco.dmg
exit 65:
missing notarization credentials
set VOCO_NOTARYTOOL_PROFILE for an xcrun notarytool keychain profile
or set all of VOCO_NOTARYTOOL_APPLE_ID, VOCO_NOTARYTOOL_TEAM_ID, and VOCO_NOTARYTOOL_PASSWORD
```

GREEN evidence:

```text
packaging/build_native_app_bundle.sh --profile release --signing-style adhoc
ok: verified native Voco.app bundle: target/native/Voco.app

packaging/tests/native_app_bundle_smoke.sh
ok: native Voco.app bundle smoke passed

packaging/tests/native_dmg_smoke.sh
hdiutil: verify: checksum of "/private/tmp/voco-native-release-packaging/dist/Voco.dmg" is VALID
ok: native Voco.dmg smoke passed

git diff --check
exit 0
```

Developer ID and notarization verification status:

```text
VOCO_DEVELOPER_ID_APPLICATION=missing
VOCO_DEVELOPER_ID_DMG=missing
VOCO_NOTARYTOOL_PROFILE=missing
VOCO_NOTARYTOOL_APPLE_ID=missing
VOCO_NOTARYTOOL_TEAM_ID=missing
VOCO_NOTARYTOOL_PASSWORD=missing
```

Release-only commands were skipped because the required Developer ID and
notarytool credential env vars were not available in this worktree environment.
