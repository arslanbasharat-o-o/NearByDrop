# Nearby Drop Feature Sprint 1 Report

**Date:** 2026-10-31
**Branch:** `feature/nearbydrop-product-sprint-1`
**Stabilization base:** `268b9f826ee9735e6d2fc4e811e68c2a5483bbf2`
**Main comparison base:** `b930be3705632465dcb144d28ae2798767f734d3`
**Status:** **CONDITIONALLY READY — EXTERNAL TESTING REQUIRED**

## 1. Executive summary

Implemented the three requested product features on one local branch: retry as a new outgoing transfer attempt, pause and resume receiving while preserving outgoing discovery, and manually preview/save an allowlisted diagnostics JSON file. The retry path rechecks selected sources, opens a new connection, and requires fresh receiver consent. Pausing closes inbound admission and advertisement while retaining sessions already approved by the user. Diagnostics are generated in memory and saved locally through a native save panel; export has no upload path.

The full XCTest suite passed: **69 tests, 0 failures, 0 skipped**, including **19 new test methods**. Debug, universal arm64/x86_64 Release, Xcode Analyze, and a strict-concurrency build passed. Secret scans reported no findings. No confirmed critical security regression remains in the reviewed diff.

The app-level visual smoke test is **not counted as passed**: the launch request resolved to the installed Nearby Drop app instead of the isolated candidate. The app was stopped. A routine analytics request may have been attempted during that launch; delivery is unknown. No transfer was initiated and no diagnostics file was exported. Physical-device, minimum-macOS runtime, accessibility, and clean-candidate UI checks remain outstanding.

## 2. Features implemented

### Retry failed outgoing transfers

**Behavior and design:** Retry is available only for an eligible current-session outgoing failure. `TransferModel.retryFailedOutgoing()` creates a fresh attempt UUID and `OutgoingAttemptDelegate`; `prepareOutgoingAttempt(_:attemptID:isRetry:)` revalidates the selection before opening the normal outgoing connection. Old callbacks are ignored by attempt ID and lifecycle checks. The new attempt starts at zero, resets speed and ETA, obtains a fresh peer connection, and waits for the peer's normal approval. No resume state or wire changes were introduced.

The source selection is re-expanded and checked against the original URL set, names, identities, and skipped-entry counts. This reapplies the existing symlink and 128-file protections. Missing roots and expired access produce distinct actionable failures. File access is released on completion, failure, cancellation, and stale preparation callbacks. Retried transfer history omits its source URL.

**User experience:** The Send view shows a Failed state and a Retry control. Retry is disabled while the device is absent; the UI explains that the receiver must approve again. Retrying, waiting for receiver approval, transfer progress, completion, and cancellation have distinct status text.

**Edge cases and tests:** The code prevents simultaneous retries, blocks stale attempt callbacks, allows cancellation, and handles a peer that disappears before the button is used. Tests cover new lifecycle IDs, repeat clicks, cancellation, completion, stale callbacks, missing/modified/unreadable sources, symlink changes, and no retry URL in history. `RetryConsentLoopbackTests.testPeerRejectionThenRetryStartsFreshConsentBeforePayloadWrite` exercises the production inbound/outbound connection classes: the first transfer is declined without a destination payload, the second attempt asks for consent again, and bytes are written only after acceptance.

**Limitations and acceptance:** The protocol loopback does not drive the app's full SwiftUI/Bonjour flow. UI behavior for a disappearing peer, deterministic timeout expiry, and concurrent device churn still needs external validation. The feature's security and local automated acceptance criteria pass; full-device acceptance remains open.

### Pause receiving and control visibility

**Behavior and design:** Receiving defaults to the existing enabled behavior and persists the user's pause choice. `NearbyConnectionManager.setReceivingPaused(_:)` serializes listener and advertisement changes on `stateQueue`. Pause removes Bonjour service state, cancels the inbound listener, clears QR receive state, and rejects new or late inbound sessions and approvals. Pending, unapproved sessions are canceled with a specific pause error. Already-approved sessions are retained so their transfers can finish. Outgoing discovery is left running.

The manager restores the preference on initialization. Resume creates a fresh inbound listener and returns advertisement state through startup. QR receive requests are disabled while paused and require resuming before scanning.

**User experience:** The Receive view shows “Receiving On” or “Receiving Paused” with a direct Pause/Resume button and an explanation that outgoing discovery and approved transfers continue. QR scanning is visibly disabled while paused. Buttons include accessibility labels and hints.

**Edge cases and tests:** Policy and local manager tests cover default/persisted state, new-session rejection, consent during pause, preserving approved sessions, listener/advertisement removal, discovery reference preservation, and rapid pause/resume consistency. Legacy trust invalidation is also tested to remove only `trustedDevices`, preserving the download path, bookmark, and analytics preference.

**Limitations and acceptance:** Automated tests do not emulate sleep/wake, real Bonjour visibility on a second device, or pause during a physical active transfer. Those checks remain external. The local listener/discovery policy and UI wiring pass code and test review.

### Privacy-safe diagnostics export

**Behavior and design:** Settings generates a versioned JSON object from a fixed allowlist: app version/build, macOS version, architecture, receive/outgoing state, bounded active counts, and a safe error category. The builder does not collect arbitrary logs or transfer metadata. The report is previewed before a native JSON save panel is opened. Cancel writes nothing; save uses an atomic local file write. There is no network submission code path, and the feature does not change analytics consent.

**User experience:** Settings explains included and excluded fields, shows readable selectable JSON, and offers “Save Report…”. The save panel states that saving is local and does not send the report. Save errors are surfaced in the UI.

**Edge cases and tests:** Tests cover valid JSON, empty state, Unicode, unexpected error text reduced to a safe category, cancellation, save failure, atomic output content, and sentinel checks that excluded analytics fields do not appear.

**Limitations and acceptance:** The no-upload conclusion is based on the implementation's local call graph and source review; the suite does not install a network interceptor around the Settings UI. Diagnostics functionality passes code and unit coverage, but preview/save interaction was not exercised in the isolated candidate UI.

## 3. Architecture decisions

- Retry creates a fresh attempt and delegate rather than reviving an old connection or payload sequence.
- `TransferFileSafety.revalidateSelection(roots:matching:)` reuses the existing safe enumerator and compares the current selection to captured identities.
- Attempt IDs and the lifecycle model gate callbacks so a terminal or stale attempt cannot update the current transfer.
- Receive pause state and listener/advertisement transitions remain owned by the manager's existing serial state queue.
- Approved inbound transfer IDs define the pause lifecycle boundary: pause rejects new work and cancels pending consent, while approved work can finish.
- Diagnostics use a value snapshot and a fixed schema; the exporter does not read analytics buffers or raw application logs.
- The Quick Share wire format and USB transfer protocol were not changed.

## 4. UI changes

- `NearByDrop/AppDelegate.swift`: retry action and outgoing phase/error presentation; Receive pause/resume control, paused status, QR disablement, and accessibility text.
- `NearByDrop/TransferWindow.swift`: attempt lifecycle, phase/status state, pause action and diagnostics snapshot.
- `NearByDrop/SettingsView.swift`: diagnostics explanation, preview sheet, native JSON save panel, and save-error alert.
- `CHANGELOG.md`: three proposed Unreleased notes. Existing v2.3.5 history remains unchanged.

No broad layout or onboarding redesign was made. Candidate-specific visual polish and VoiceOver behavior remain unverified because the isolated candidate was not successfully launched.

## 5. Security and privacy assessment

- **Consent:** Retry creates a new connection and asks for consent again. QR key checks and the existing QR-to-manual-approval path remain in place.
- **Rejected writes:** The loopback test verifies no destination payload exists before consent and that a decline does not write payload bytes. Existing consent tests also cover decline cleanup and duplicate introductions.
- **Source safety:** Revalidation rejects changed, missing, newly unreadable, over-limit, or symlink-altered selections before sending.
- **Receiving pause:** New connections are checked at admission and consent time; pause tears down inbound advertisement/listener. Approved sessions are explicitly tracked.
- **Preferences:** Legacy invalidation deletes only the obsolete trusted-device key; the regression test protects download preferences and analytics opt-out.
- **Diagnostics:** The schema excludes file names/paths, device and peer identifiers, IP/MAC addresses, pairing material, secrets, tokens, install IDs, payloads, and logs. Export is an explicit local save.
- **Logging:** No raw diagnostic report, source URL, peer ID, or pairing value was added to logs. Existing user-facing transfer errors remain detailed; the export contains only safe categories.
- **Finding status:** No confirmed P0/P1 regression in this sprint diff. External interoperability and release checks remain open.

## 6. Regression fixes

During review, two pause-path lifecycle issues were corrected: pending transfers canceled by pause now receive a receiving-paused error instead of appearing user-canceled, while an explicit user cancellation retains the user-canceled error. Retry source inspection now distinguishes missing paths from access-denied paths so the UI can provide the correct action. Retried source URLs are not written to transfer history.

The independent CodeRabbit review found one minor issue in the pre-existing `audit-output/NEARBYDROP_STABILIZATION_FINAL_REPORT.md`: historical totals/file lists and its deferred-feature section no longer describe the current branch. That document was preserved as historical evidence; the sprint report records current results. No actionable new source finding was reported.

## 7. Tests added

**19 new test methods** were added in `Tests/NearbyShareSafetyTests.swift`:

- `RetryConsentLoopbackTests`: one production-connection consent/retry/write-path test.
- `TransferFileSafetyTests`: five retry revalidation tests for unchanged, modified, missing, expired-access, and symlink-altered sources.
- `OutgoingAttemptLifecycleTests`: four tests for new attempt IDs/repeated clicks/stale callbacks, cancellation, completed attempts, and retry history privacy.
- `DiagnosticsReportTests`: five tests for schema/JSON, empty Unicode state, unexpected errors, cancel/failure, and saved content.
- `ReceivingPausePolicyTests`: four tests for pause policy, preference restore, listener/discovery behavior, and rapid toggles.
- Existing legacy-preference test adds assertions that unrelated preferences survive invalidation.

Existing QR authentication tests still check malformed or mismatched proof rejection and valid QR pairing's manual approval. Existing transfer rejection tests assert no payload output.

## 8. Full test results

| Check | Result |
|---|---|
| Full XCTest suite | **PASS — 69 tests, 0 failures, 0 skipped.** |
| Debug build | **PASS — macOS arm64, signing disabled for build.** |
| Universal Release build | **PASS — arm64 and x86_64.** Verified all 13 Mach-O binaries in the app contain both architectures. |
| Xcode Analyze | **PASS.** |
| Strict-concurrency build | **PASS in Swift 5 language mode with complete strict checking; warnings remain.** |
| Secret scan | **PASS — Gitleaks found no secrets in the branch commits or working diff.** |
| Diff whitespace check | **PASS — `git diff --check`.** |
| CodeRabbit | **Completed against `main`; one minor historical-report finding, no actionable source finding.** |
| Site/installer checks | **NOT RUN — this sprint changes no site or installer files.** |

No public release version was assigned. The existing v2.3.5 artifact was not reused.

## 9. Swift concurrency impact

Both the sprint branch and exact stabilization base build with `SWIFT_STRICT_CONCURRENCY=complete`. A deduplicated comparison of source-file/line/diagnostic sites found **518 at base and 535 after the sprint**: 22 new sites and 5 sites removed, for a net increase of 17. Of the new sites, 14 are in `NearByDrop/TransferWindow.swift` and 8 in `NearbyShare/NearbyConnectionManager.swift`.

The new diagnostics arise at GCD/queue boundaries where mutable `TransferModel`, `NearbyConnectionManager`, and connection objects are captured, plus a main-actor task-isolation capture. Reviewed state writes are intended to run on the main queue, manager `stateQueue`, or connection queue. The builds pass in Swift 5 mode, but these warnings remain compiler-visible ownership debt; the change is not Swift 6 migration-ready. No broad `@unchecked Sendable` conformance or warning suppression was added. A focused actor/queue ownership refactor should address the new sites before a Swift 6 mode change.

## 10. Android, Windows, and USB compatibility

No Quick Share wire format, cryptographic exchange, payload framing, or USB/MTP implementation changed. Retry opens a new standard connection and relies on the existing receiver approval flow. Pausing affects inbound visibility/listening only; the Mac continues outgoing discovery. QR receive is explicitly blocked while paused and uses existing QR proof and approval logic after resume.

Universal compilation and protocol loopback do not establish Android, Windows, macOS 14, or USB interoperability. Android/Windows devices, USB hardware, and the minimum supported macOS runtime were **NOT RUN** and must be checked externally.

## 11. Manual UI test results

- **Isolated candidate UI smoke test: NOT RUN.** A request to open the candidate resolved by bundle identifier to the installed app, so that session is not counted as a candidate test. The installed app was stopped afterward. No transfer was started and no diagnostics report was created.
- The installed app's analytics startup ran while it was open. Existing preferences showed analytics enabled. A routine `first_launch` or `app_opened` event may have been sent if the configured endpoint accepted it; delivery is unknown. No transfer content or new diagnostic data was sent.
- Candidate menu-bar startup, popover, Retry presentation, pause/resume interaction, diagnostics preview/save, keyboard navigation, and VoiceOver: **NOT RUN**.
- Physical Android, Windows, USB/MTP, sleep/wake, and macOS 14 checks: **NOT RUN**.

The launch misresolution was reported during execution. The app was terminated, and no second launch was attempted.

## 12. Remaining blockers

There is no known automated test, build, or analyzer failure. Engineering review can proceed, but external validation is required before release:

1. Launch the exact candidate executable by filesystem path from an isolated copy and verify menu-bar/popover, Retry, Receive pause, Settings preview/save, keyboard, and VoiceOver.
2. Test Mac↔Android and Mac↔Windows transfers, including QR authentication, decline/no-write, fresh retry consent, active transfer during pause, pause/resume discovery, and device disappearance.
3. Test USB/MTP and sleep/wake/network recovery on supported hardware.
4. Run on the minimum supported macOS version (macOS 14).
5. Triage the 22 new strict-concurrency diagnostic sites through explicit actor/queue ownership.

The report intentionally distinguishes compiler warnings from confirmed races; the queue audit found intended serialization, but does not remove the need to make ownership visible to Swift's compiler.

## 13. Changed files

Nine tracked paths differ from the stabilization base, including this report:

1. `CHANGELOG.md`
2. `NearByDrop/AppDelegate.swift`
3. `NearByDrop/AppSupport.swift`
4. `NearByDrop/SettingsView.swift`
5. `NearByDrop/TransferWindow.swift`
6. `NearbyShare/NearbyConnectionManager.swift`
7. `NearbyShare/TransferFileSafety.swift`
8. `Tests/NearbyShareSafetyTests.swift`
9. `audit-output/NEARBYDROP_FEATURE_SPRINT_1_REPORT.md`

The pre-existing untracked `audit-output/NEARBYDROP_MASTER_AUDIT.md` was preserved and not modified.

## 14. Local commit SHAs

All feature commits are local on the sprint branch:

| Feature | Commit |
|---|---|
| Retry with fresh receiver consent | `4eb231a702ab14f5acd7a01f2a7e165164a970b7` |
| Pause receiving and preserve outgoing discovery | `7b5fedae002a38aa0214c0efc254f46a5a2ca0c3` |
| Preview and export diagnostics locally | `19f0260ab9f433c5b13a9d953fe40a463d61cca3` |

The final report is committed separately after these feature commits. No push, merge, deployment, or release was performed.

## 15. Proposed next-release changelog

The following notes were added to the existing Unreleased section in `CHANGELOG.md`:

- Retry failed outgoing transfers as new attempts after rechecking selected sources.
- Pause incoming visibility while preserving outgoing discovery and approved transfers.
- Preview and export allowlisted diagnostics locally without uploading the report.

Assign a new version/build only through the normal release process after compatibility, signing, and distribution validation. Do not reuse the public v2.3.5 artifact.

## 16. GitHub integration plan

This branch has not been pushed. Before integration, review its complete diff against the current canonical `main`, run repository CI, and resolve the strict-warning follow-up or explicitly accept that debt. After external device/UI checks, the maintainer can integrate through the repository's approved direct-to-main or PR workflow. If main advances, reconcile the branch against it; preserve the repository's fast-forward-only beta synchronization rules. This task made no GitHub changes.

## 17. Release-readiness assessment

**CONDITIONALLY READY — EXTERNAL TESTING REQUIRED**

The implementation, automated regression suite, local builds, analyzer, and privacy/security review support engineering review. Candidate UI, accessibility, physical interoperability, USB, and minimum-macOS validation have not been completed. The strict build also introduces 22 distinct warning sites, though no confirmed runtime race was found in the reviewed ownership paths. Do not treat this as public-release approval.
