# Voco Native Manual UX Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record Task 8 native macOS manual UX verification truthfully, separating local automated artifact evidence from manual clean-account and Developer ID release checks that cannot be claimed in this agent run.

**Architecture:** This slice creates documentation artifacts only. The checklist is the single source of truth for PASS, FAIL, and BLOCKED rows, while this plan records the execution method, commands, final verification evidence, and release follow-up gate.

**Tech Stack:** Markdown, macOS shell tools (`sw_vers`, `sysctl`, `codesign`, `hdiutil`, `spctl`, `xcrun stapler`), SwiftPM tests, existing native packaging smoke scripts.

---

## File Structure

- Create: `docs/superpowers/plans/2026-05-06-voco-native-manual-ux-verification.md` - Task 8 execution plan and final verification record.
- Create: `docs/superpowers/native-manual-ux-checklist.md` - environment matrix, manual UX matrix, automated artifact rows, and required follow-up references.

## Result Semantics

- `PASS`: the check was actually executed in the stated environment and produced the expected result.
- `FAIL`: the check was executed and produced an incorrect result. A release-blocking issue or implementation plan must exist before release.
- `BLOCKED`: the check was not executed because it requires a clean macOS account, real UI interaction, TCC state changes, logout/login, Developer ID credentials, notarization ticket, or another unavailable precondition.

No row may be left blank. Manual UX rows must not be marked `PASS` unless they were executed interactively in a clean macOS account.

## Task 1: Clean Account Setup Checklist

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Capture environment facts**

Run:

```bash
sw_vers
sysctl -n hw.model
uname -m
git rev-parse --short HEAD
test -d dist/Voco.app && printf '%s\n' "$PWD/dist/Voco.app"
test -f dist/Voco.dmg && printf '%s\n' "$PWD/dist/Voco.dmg"
codesign -dvvv dist/Voco.app
```

Expected:

- Checklist records exact macOS version and build.
- Checklist records machine model and architecture.
- Checklist records Voco build hash under test.
- Checklist records exact app and DMG paths.
- Checklist records signing status as ad-hoc, Developer ID, unsigned, or unavailable.

- [ ] **Step 2: Mark clean-account precondition**

Expected:

- If this run is not a clean macOS account with interactive UI access, mark clean-account setup `BLOCKED`.
- Link all manual-only checks to the clean-account follow-up gate.

## Task 2: First Launch Verification

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Verify first launch interactively**

Run in a clean macOS account only:

```bash
open /private/tmp/voco-native-manual-ux-verification/dist/Voco.app
```

Expected manual observations:

- Menu bar item appears.
- Dock icon is absent.
- Settings window opens only when requested from the menu bar item.
- DMG run-location warning appears when launching from the mounted DMG or another non-Applications location where the app is expected to warn.

- [ ] **Step 2: Record truthfully**

Expected:

- Mark rows `PASS` only if observed in the clean account.
- Mark rows `FAIL` for observed product defects.
- Mark rows `BLOCKED` when no clean interactive account was used.

## Task 3: Permission Recovery Verification

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Reset or use fresh TCC state**

Use a clean account or explicitly reset permissions before launch:

```bash
tccutil reset Microphone com.voco.app
tccutil reset Accessibility com.voco.app
```

Input Monitoring does not have a stable `tccutil` service name on all macOS releases, so prefer a clean account for that row.

- [ ] **Step 2: Verify permission UX**

Expected manual observations:

- Microphone permission prompt appears with Voco branding or a clearly Voco-owned request.
- Accessibility recovery link opens the correct System Settings pane.
- Input Monitoring recovery link opens the correct System Settings pane.

## Task 4: Hotkey Focus Verification

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Verify global hotkey without focus theft**

In a clean account with permissions granted, focus another app and press the configured Voco global hotkey.

Expected manual observations:

- Recording starts.
- The focused target app remains focused.
- Voco does not activate a Dock app or foreground window unexpectedly.

## Task 5: HUD Focus Verification

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Verify HUD placement and transcript updates**

In a clean account with ASR streaming configured, start recording through the global hotkey.

Expected manual observations:

- HUD appears near the notch or top center.
- HUD does not steal focus.
- Partial transcript updates appear while ASR streaming is configured.

If ASR credentials are unavailable, mark only the partial transcript row `BLOCKED` and keep placement/focus rows tied to the manual UI follow-up.

## Task 6: Text Insertion Target Matrix

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Verify insertion targets**

With permissions granted and a successful final transcript, test insertion into:

```text
TextEdit
Safari text field
Notes
terminal editor
```

Expected:

- Final text appears in the focused text target.
- Voco does not corrupt clipboard contents or focus state.
- Each target row is recorded independently as `PASS`, `FAIL`, or `BLOCKED`.

## Task 7: Launch-at-Login Verification

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Verify logout/login lifecycle**

In a clean account:

1. Enable launch-at-login inside Voco.
2. Log out.
3. Log in.
4. Observe Voco startup state.
5. Quit Voco from the menu bar.

Expected manual observations:

- Voco launches after login.
- Menu bar item appears after login.
- Quitting Voco removes the menu bar item.

## Task 8: Release Artifact Gatekeeper Verification

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`

- [ ] **Step 1: Run credential-free local artifact checks**

Run:

```bash
codesign --verify --deep --strict dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
```

Expected:

- Ad-hoc local app and DMG signatures verify.
- DMG structure verifies.

- [ ] **Step 2: Check Developer ID and notarization prerequisites**

Run:

```bash
printf 'VOCO_DEVELOPER_ID_APPLICATION=%s\n' "${VOCO_DEVELOPER_ID_APPLICATION:+set}${VOCO_DEVELOPER_ID_APPLICATION:-missing}"
printf 'VOCO_DEVELOPER_ID_DMG=%s\n' "${VOCO_DEVELOPER_ID_DMG:+set}${VOCO_DEVELOPER_ID_DMG:-missing}"
printf 'VOCO_NOTARYTOOL_PROFILE=%s\n' "${VOCO_NOTARYTOOL_PROFILE:+set}${VOCO_NOTARYTOOL_PROFILE:-missing}"
printf 'VOCO_NOTARYTOOL_APPLE_ID=%s\n' "${VOCO_NOTARYTOOL_APPLE_ID:+set}${VOCO_NOTARYTOOL_APPLE_ID:-missing}"
printf 'VOCO_NOTARYTOOL_TEAM_ID=%s\n' "${VOCO_NOTARYTOOL_TEAM_ID:+set}${VOCO_NOTARYTOOL_TEAM_ID:-missing}"
printf 'VOCO_NOTARYTOOL_PASSWORD=%s\n' "${VOCO_NOTARYTOOL_PASSWORD:+set}${VOCO_NOTARYTOOL_PASSWORD:-missing}"
```

Expected:

- If Developer ID identity and notarization credentials are missing, mark release-only `spctl` and `stapler` rows `BLOCKED`.
- Do not mark Gatekeeper release checks `PASS` against an ad-hoc, non-notarized artifact.

- [ ] **Step 3: Run release-only commands only when prerequisites exist**

Run only for a Developer ID signed and notarized release DMG:

```bash
codesign --verify --deep --strict dist/Voco.app
spctl --assess --type execute --verbose=4 dist/Voco.app
hdiutil verify dist/Voco.dmg
codesign --verify --strict dist/Voco.dmg
xcrun stapler validate dist/Voco.dmg
spctl --assess --type open --verbose=4 dist/Voco.dmg
```

Expected:

- App signature verifies.
- App Gatekeeper assessment passes.
- DMG verifies.
- DMG signature verifies.
- Stapled notarization ticket validates.
- DMG Gatekeeper assessment passes.

## Task 9: Result Recording and Issue Follow-Up

**Files:**
- Create: `docs/superpowers/native-manual-ux-checklist.md`
- Modify: `docs/superpowers/plans/2026-05-06-voco-native-manual-ux-verification.md`

- [ ] **Step 1: Ensure every row has a status**

Run:

```bash
rg -n '\|[[:space:]]*\|[[:space:]]*\|' docs/superpowers/native-manual-ux-checklist.md
```

Expected:

- No required result row has a blank status cell.
- Every result status is exactly `PASS`, `FAIL`, or `BLOCKED`.

- [ ] **Step 2: Link every `FAIL` or `BLOCKED` to follow-up**

Expected:

- Each `FAIL` or `BLOCKED` row has a follow-up ID or issue reference.
- Manual-only `BLOCKED` rows link to a clean-account manual UX follow-up gate.
- Release-only `BLOCKED` rows link to a Developer ID/notarization follow-up gate.

- [ ] **Step 3: Run final acceptance gate**

Run:

```bash
cd native && swift test
packaging/tests/native_app_bundle_smoke.sh
packaging/tests/native_dmg_smoke.sh
git diff --check
```

Expected:

- Native Swift tests pass.
- Native app bundle smoke passes.
- Native DMG smoke passes.
- No whitespace errors exist in the docs changes.

- [ ] **Step 4: Commit focused documentation changes**

Expected commits:

```bash
git commit -m "docs(native): plan manual ux verification"
git commit -m "docs(native): add native manual ux checklist"
git commit -m "docs(native): record native manual ux verification"
```

## Final Verification

Task 8 final recording completed from `/private/tmp/voco-native-manual-ux-verification` on 2026-05-06.

```text
Environment:
macOS: macOS 26.4.1, BuildVersion 25E253
Machine: MacBookPro18,1, arm64
Voco build hash under test: c1b018a
App path: /private/tmp/voco-native-manual-ux-verification/dist/Voco.app
DMG path: /private/tmp/voco-native-manual-ux-verification/dist/Voco.dmg
Signing status: ad-hoc; Signature=adhoc; TeamIdentifier=not set; flags=0x2(adhoc)

Checklist summary:
PASS=14
FAIL=0
BLOCKED=20
```

Automated acceptance gate:

```text
cd native && swift test
PASS: XCTest reported 140 tests executed, 1 test skipped, 0 failures.

packaging/tests/native_app_bundle_smoke.sh
PASS: output included ok: verified native Voco.app bundle: target/native/Voco.app
PASS: output ended with ok: native Voco.app bundle smoke passed

packaging/tests/native_dmg_smoke.sh
PASS: rebuilt /private/tmp/voco-native-manual-ux-verification/dist/Voco.dmg
PASS: hdiutil verified the DMG checksum
PASS: output ended with ok: native Voco.dmg smoke passed

git diff --check
PASS: exited 0 with no whitespace errors.
```

Local artifact checks after the DMG smoke rebuilt `dist/`:

```text
codesign --verify --deep --strict dist/Voco.app
PASS: exited 0; recorded as dist app codesign verify: PASS.

hdiutil verify dist/Voco.dmg
PASS: reported checksum of "dist/Voco.dmg" is VALID.

codesign --verify --strict dist/Voco.dmg
PASS: exited 0; recorded as dist dmg codesign verify: PASS.
```

Developer ID and notarization prerequisites:

```text
VOCO_DEVELOPER_ID_APPLICATION=missing
VOCO_DEVELOPER_ID_DMG=missing
VOCO_NOTARYTOOL_PROFILE=missing
VOCO_NOTARYTOOL_APPLE_ID=missing
VOCO_NOTARYTOOL_TEAM_ID=missing
VOCO_NOTARYTOOL_PASSWORD=missing
```

Release-only verification status:

```text
BLOCKED: spctl --assess --type execute --verbose=4 dist/Voco.app
BLOCKED: xcrun stapler validate dist/Voco.dmg
BLOCKED: spctl --assess --type open --verbose=4 dist/Voco.dmg
```

Reason: current smoke artifacts are ad-hoc signed and not notarized. Developer ID identities, notarytool credentials, and a stapled notarization ticket were unavailable in this worktree environment. These rows are tracked by `FU-RELEASE-01` in `docs/superpowers/native-manual-ux-checklist.md`.

Manual UX status:

```text
BLOCKED: first launch menu bar, Dock, Settings-on-demand, and DMG run-location warning.
BLOCKED: microphone prompt and Accessibility/Input Monitoring recovery links.
BLOCKED: global hotkey recording, focus retention, HUD placement, and streaming partial transcript observation.
BLOCKED: TextEdit, Safari, Notes, and terminal editor insertion matrix.
BLOCKED: launch-at-login after logout/login and menu bar item removal on quit.
```

Reason: this was a non-interactive agent run, not a clean macOS account with UI interaction. No true manual UX PASS is claimed. Manual follow-up gates are tracked by `FU-MANUAL-01` through `FU-MANUAL-05`, `FU-TCC-01`, and `FU-ASR-01` in `docs/superpowers/native-manual-ux-checklist.md`.
