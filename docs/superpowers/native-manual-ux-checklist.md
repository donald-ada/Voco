# Voco Native Manual UX Checklist

Task 8 checklist for the native macOS rewrite. Status values are limited to `PASS`, `FAIL`, and `BLOCKED`.

Manual UX checks in this file are not claimed as passed because this agent run did not execute Voco in a clean macOS account with real UI interaction.

## Environment

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| macOS version | PASS | macOS 26.4.1, BuildVersion 25E253 | `sw_vers` | None |
| machine model | PASS | MacBookPro18,1 | `sysctl -n hw.model` | None |
| architecture | PASS | arm64 | `uname -m` | None |
| Voco build hash | PASS | c1b018a | `git rev-parse --short HEAD` at Task 8 start; docs commits do not change the app binary under test | None |
| app path | PASS | `/private/tmp/voco-native-manual-ux-verification/dist/Voco.app` | `test -d dist/Voco.app` | None |
| DMG path | PASS | `/private/tmp/voco-native-manual-ux-verification/dist/Voco.dmg` | `test -f dist/Voco.dmg` | None |
| signing status | PASS | Ad-hoc signed app; `Signature=adhoc`, `TeamIdentifier=not set`, `flags=0x2(adhoc)` | `codesign -dvvv dist/Voco.app` | FU-RELEASE-01 for Developer ID release signing |

## First Launch

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| menu bar item appears | BLOCKED | Not executed in a clean interactive macOS account | Non-interactive agent run cannot observe menu bar UI | FU-MANUAL-01 |
| Dock icon absent | BLOCKED | Not executed in a clean interactive macOS account | Non-interactive agent run cannot observe Dock state | FU-MANUAL-01 |
| Settings opens only when requested | BLOCKED | Not executed in a clean interactive macOS account | Non-interactive agent run cannot click menu bar item and observe windows | FU-MANUAL-01 |
| DMG run-location warning appears when applicable | BLOCKED | Not executed from mounted DMG with real UI observation | Requires mounted DMG launch and UI observation | FU-MANUAL-01 |

## Permissions

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| microphone prompt | BLOCKED | Not executed with fresh TCC state in a clean account | Permission prompts require real app launch and UI/TCC interaction | FU-TCC-01 |
| accessibility recovery link | BLOCKED | Not executed with denied or missing Accessibility permission | System Settings recovery links require UI interaction | FU-TCC-01 |
| input monitoring recovery link | BLOCKED | Not executed with denied or missing Input Monitoring permission | System Settings recovery links require UI interaction | FU-TCC-01 |

## Recording

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| global hotkey starts recording | BLOCKED | Not executed with global keyboard input in a clean account | Requires UI session, granted permissions, and physical or scripted hotkey input | FU-MANUAL-02 |
| Voco does not steal focus | BLOCKED | Not executed while another app is focused | Requires focus observation during recording | FU-MANUAL-02 |
| HUD appears near notch/top center | BLOCKED | Not executed in a real display session | Requires visual observation on MacBookPro18,1 display | FU-MANUAL-03 |
| partial transcript updates appear when ASR streaming is configured | BLOCKED | Not executed with ASR streaming credentials/configuration | Requires ASR credentials and live recording flow | FU-ASR-01 |

## Insertion Targets

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| TextEdit | BLOCKED | Not executed with final transcript insertion | Requires clean-account UI flow and granted permissions | FU-MANUAL-04 |
| Safari text field | BLOCKED | Not executed with final transcript insertion | Requires clean-account UI flow and granted permissions | FU-MANUAL-04 |
| Notes | BLOCKED | Not executed with final transcript insertion | Requires clean-account UI flow and granted permissions | FU-MANUAL-04 |
| terminal editor | BLOCKED | Not executed with final transcript insertion | Requires clean-account UI flow and granted permissions | FU-MANUAL-04 |

## Lifecycle

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| launch-at-login works after logout/login | BLOCKED | Not executed across logout/login | Requires clean account and real logout/login cycle | FU-MANUAL-05 |
| quitting Voco removes menu bar item | BLOCKED | Not executed in a real menu bar session | Requires menu bar UI observation | FU-MANUAL-05 |

## Release Artifacts

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| codesign verification | PASS | Current ad-hoc `dist/Voco.app` signature verifies | `codesign --verify --deep --strict dist/Voco.app` exited 0 | FU-RELEASE-01 for Developer ID release signing |
| DMG codesign verification | PASS | Current ad-hoc `dist/Voco.dmg` signature verifies | `codesign --verify --strict dist/Voco.dmg` exited 0 | FU-RELEASE-01 for Developer ID release signing |
| spctl app assessment | BLOCKED | Not run as release Gatekeeper evidence against ad-hoc app | Developer ID Application identity is missing | FU-RELEASE-01 |
| hdiutil DMG verification | PASS | Current `dist/Voco.dmg` checksum is valid | `hdiutil verify dist/Voco.dmg` reported `checksum of "dist/Voco.dmg" is VALID` | None |
| stapler DMG validation | BLOCKED | Not run because current DMG is not notarized | notarytool credentials and notarization ticket are missing | FU-RELEASE-01 |
| spctl DMG assessment | BLOCKED | Not run as release Gatekeeper evidence against non-notarized DMG | Developer ID/notarized release DMG is unavailable | FU-RELEASE-01 |

## Automated Final Acceptance Gate

| Check | Status | Result | Evidence | Follow-up |
| --- | --- | --- | --- | --- |
| `cd native && swift test` | PASS | 140 tests executed, 0 failures, 1 live Doubao opt-in test skipped | XCTest reported `Executed 140 tests, with 1 test skipped and 0 failures` | None |
| `packaging/tests/native_app_bundle_smoke.sh` | PASS | Native app bundle smoke passed | Output ended with `ok: native Voco.app bundle smoke passed` | None |
| `packaging/tests/native_dmg_smoke.sh` | PASS | Native DMG smoke passed | Output ended with `ok: native Voco.dmg smoke passed` | None |
| `git diff --check` | PASS | No whitespace errors | Command exited 0 with no output | None |

## Follow-Up Gates

| ID | Status | Scope | Required before release |
| --- | --- | --- | --- |
| FU-MANUAL-01 | BLOCKED | First launch menu bar, Dock, Settings, and DMG location warning | Create or use a clean macOS account, launch `/private/tmp/voco-native-manual-ux-verification/dist/Voco.app` and the mounted DMG, record screenshots or notes for every First Launch row, then update this checklist from `BLOCKED` to `PASS` or `FAIL`. |
| FU-TCC-01 | BLOCKED | Microphone prompt and permission recovery links | Use a fresh TCC state or clean account, trigger Voco permission flows, verify Microphone, Accessibility, and Input Monitoring prompts/recovery links, then update every Permissions row. |
| FU-MANUAL-02 | BLOCKED | Hotkey recording and focus retention | With permissions granted, focus TextEdit or Safari, press the configured global hotkey, verify recording starts and focus remains on the target app, then update Recording rows. |
| FU-MANUAL-03 | BLOCKED | HUD placement and focus behavior | On the MacBookPro18,1 display, start recording and verify HUD placement near notch/top center without focus theft, then update HUD rows. |
| FU-MANUAL-04 | BLOCKED | Text insertion targets | Verify final transcript insertion independently in TextEdit, Safari, Notes, and a terminal editor, then update each target row. |
| FU-MANUAL-05 | BLOCKED | Launch-at-login and quit lifecycle | Enable launch-at-login, log out, log in, verify Voco starts and quitting removes the menu bar item, then update Lifecycle rows. |
| FU-ASR-01 | BLOCKED | Streaming partial transcripts | Configure valid ASR credentials, record live speech, verify partial transcript updates during streaming, then update the partial transcript row. |
| FU-RELEASE-01 | BLOCKED | Developer ID signing, notarization, and Gatekeeper | Provide `VOCO_DEVELOPER_ID_APPLICATION` plus `VOCO_DEVELOPER_ID_DMG` or app fallback, and either `VOCO_NOTARYTOOL_PROFILE` or Apple ID/team/password env vars. Run Developer ID release DMG build, notarization, `xcrun stapler validate`, and `spctl` app/DMG assessments before release. |
| FU-ISSUE-01 | BLOCKED | Any future `FAIL` row | Before release, create a concrete GitHub issue or `docs/superpowers/plans/` implementation plan for every `FAIL`, then link it from the failed row. |

## Current Summary

Counts include the required checklist matrix and automated final acceptance rows. Counts exclude Follow-Up Gates and this summary table.

| Status | Count |
| --- | ---: |
| PASS | 14 |
| FAIL | 0 |
| BLOCKED | 20 |
