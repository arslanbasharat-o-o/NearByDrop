# Nearby Drop Stabilization Final Report

**Date:** 2026-10-31
**Branch:** `stabilization/nearbydrop-hardening`
**Comparison base:** `main` at `b930be3705632465dcb144d28ae2798767f734d3`
**PR 1 commit:** `272bfe7bbdbe78f4f2f7d93964865b6de36f65fc`

## A. Executive Summary

The stabilization sprint addressed the confirmed trusted-device, folder-link, transfer-limit, installer-integrity, release-version, Gatekeeper-documentation, and privacy-logging findings from `NEARBYDROP_MASTER_AUDIT.md`. It also added loopback regressions around consent, QR proof, cancellation, file replacement, and transfer limits. No wire protocol changes were made, and no network payload can be written before explicit user approval.

The final local verification passed: 46 XCTest cases, Debug and universal Release builds, Xcode Analyze, a clean strict-concurrency build, site checks, installer checks, and the applicable diagnostics/security checks. Strict-concurrency mode still emits 549 distinct source-location/diagnostic pairs across the project; this remains engineering debt, not a clean Swift 6 migration. Hardware interoperability, VoiceOver/manual UI review, macOS 14 runtime validation, and Developer ID signing/notarization were not performed.

No confirmed P0/P1 defect or automated release-blocking failure remains in the reviewed source. The branch is **conditionally ready for external validation and final human review**, not ready to publish. No push, merge, deployment, release, or live-service change was made.

## B. Workstream Completion Matrix

| Workstream | Status | Evidence and limits |
|---|---|---|
| PR 1 trusted-device security | Completed | All incoming introductions require consent; QR proof remains enforced; regression loopbacks pass. |
| A — Safe folder transfers | Completed | No-follow enumeration, link exclusion, source identity checks, user notices, and loopback replacement coverage. A small mutation race remains between identity check and a subsequent read. |
| B — Transfer limits and resource management | Completed | Sender preflight enforces the receiver's 128-file limit; file handles open lazily and close per file/failure/cancellation. |
| C — Installer and release safety | Partially completed | Failure-safe installer, exact-release checksum validation, rollback, consistency checks, and Gatekeeper copy are implemented and tested. Developer ID signing, notarization, and a new signed package were not attempted. |
| D — QA, error recovery, and regression testing | Partially completed | Full local suite and applicable scripts pass. Physical-device, UI automation, disk-full, and several interruption/stress scenarios remain untested. |
| E — Swift concurrency and maintainability | Partially completed | Folder selection and AppDelegate send entry are main-actor isolated; worker results cross as Sendable values. Broad callback/global-state warnings remain. |
| F — UI/UX, accessibility, and privacy | Partially completed | Selection notices, accessible progress, clearer errors, safer Settings copy, and redacted logs are implemented. No complete manual accessibility pass was performed. |
| G — Compatibility and release readiness | Partially completed | Universal macOS 14-targeted builds pass. macOS 14 runtime and Android, Windows, and USB MTP hardware validation remain external gates. |

## C. Bugs Fixed

Eight confirmed finding groups from the master audit were directly addressed. The two additional inbound protocol regressions recorded in the PR 1 review are included with the consent finding.

| Original finding | Root cause and solution | Changed files and tests | Remaining risk |
|---|---|---|---|
| `BUG-01` / `SEC-02`: folder symlink exposure | Path-based enumeration could dereference links outside the selected folder. Enumeration now classifies without following links; implicit and explicit symlink roots, dangling links, and cycles are excluded. Source identity is checked when preparing/opening and between chunks. | `TransferFileSafety.swift`, `TransferWindow.swift`, `OutboundNearbyConnection.swift`, `Tests/NearbyShareSafetyTests.swift`; symlink and source-replacement tests plus encrypted loopback rejection. | A source may still mutate in the narrow interval after an identity check and before a read. |
| `BUG-02` / `SEND-01`: sender/receiver limit mismatch and eager handles | The sender could announce more than the receiver's 128 file records and open every handle at once. A shared limit now rejects oversize selections before connection work; each active file opens lazily and closes after use. | `TransferFileSafety.swift`, `TransferWindow.swift`, `OutboundNearbyConnection.swift`, `InboundNearbyConnection.swift`, tests for 128/129 boundaries and manager preflight. | Folder entries are flattened to files; this does not segment an oversize send into multiple transfers. |
| `PROB-01` / `SEC-01`: spoofable trusted-device auto-accept | Names and endpoint IDs are peer metadata, not persistent authenticated identity. Trust matching and auto-approval were removed; launch invalidates only the obsolete `trustedDevices` preference. Repeated introductions, pre-approval URLs/chunks, and duplicate consent are rejected or gated by protocol state. | `NearbyConnectionManager.swift`, `InboundNearbyConnection.swift`, `AppDelegate.swift`, `AppSupport.swift`, Settings and tests for migration, spoofed names, changed endpoint IDs, duplicate introductions, rejection, and QR consent. | Every transfer now requires a visible user decision; durable authenticated identity is not implemented. |
| `SEC-03` / `INST-01` / `REL-02`: destructive/unverified installer | The installer previously risked removing the working app before validating a replacement. It now resolves the exact release asset and checksum, validates package/signature/version, stages on the destination volume, preserves rollback, refuses symlink destinations, and does not clear quarantine. | `scripts/install.sh`, `scripts/tests/install.sh`; mocked download/checksum/mount/copy/signature/rollback/symlink cases and an isolated installation of the currently published DMG. | No new production release package was built or notarized. |
| `REL-01`: stale release-version references | Several public pages/components and the changelog lagged the actual v2.3.5/build 19 release. Current references and deterministic CI consistency validation were updated without rewriting the 2.3.4 history. | `CHANGELOG.md`, `docs/index.html`, `docs/llms.txt`, `scripts/site-components.tsx`, generated `docs/assets/site-components.js`, `scripts/release-version.json`, `scripts/check_release_version.py`, `package.json`, workflows. | The stabilization branch remains unreleased; its changes belong in a future release note. |
| `UI-02`: outdated Gatekeeper instructions | The site recommended an obsolete Control-click bypass. Copy now describes the supported Privacy & Security → Open Anyway flow and does not recommend quarantine removal. | `docs/index.html`, site components. | A clean first-launch Gatekeeper flow was not manually exercised on a fresh macOS installation. |
| `SEC-05`: Finder Share Extension path logging | A rejected directory path could be printed to local logs. The raw URL was removed in favor of a generic diagnostic. | `ShareExtension/ShareViewController.swift`. | No extension UI invocation was manually tested. |
| `SEC-06`: protocol debug logging | Debug/protocol logs could expose transfer metadata or raw frame details. Sensitive values were removed/redacted while user-facing error messages remain actionable. | `NearbyShare/InboundNearbyConnection.swift`, `NearbyShare/OutboundNearbyConnection.swift`, related support code. | Internal protocol failures intentionally expose less low-level detail in logs; error categories and UI diagnostics remain. |

## D. Security Assessment

| Area | Result |
|---|---|
| Trusted-device consent | **Pass.** No display name, endpoint ID, stale trust entry, or QR session alone authorizes a transfer. App launch deletes only the legacy `trustedDevices` key; unrelated preferences are untouched. |
| QR authentication | **Pass.** The sender proof is verified against the P-256 key from the current QR pairing. A mismatched key fails before introduction/consent. A valid proof identifies the current session but still reaches the normal manual approval card. |
| Protocol-state transitions | **Pass.** Introduction and paired-key frames require their expected states. Consent is submitted on the connection queue from the waiting state; app guards and connection state reject duplicate approval, and duplicate introductions cannot replace pending metadata. The 60-second consent timeout rechecks state before rejecting, so a stale timeout cannot reject a later-approved transfer. Disconnect/cancellation paths close the connection and clean partial output. Inbound connections receive separate IDs and the manager caps concurrency at eight. |
| Payload authorization | **Pass.** File and URL payload paths require `.receivingFiles` after explicit approval. Encrypted loopback tests prove accepted files are written and rejected transfers write no payload files. URL opening is restricted to the approved state and supported schemes. |
| Symbolic links and file boundary | **Pass with race limitation.** Links are not traversed; file identity is checked around preparation/open/read. Unicode names and nested regular files are preserved. |
| Installation integrity | **Pass for tested installer path.** The installer verifies exact-release checksum, DMG integrity, signature, and app version before replacement and retains rollback. It preserves Gatekeeper quarantine. |
| Sensitive logging | **Improved.** Raw selected paths/URLs, peer details, and protocol frame values were removed/redacted from the reviewed logging paths. Actionable UI errors remain. |
| Other entitlements | **Unchanged.** The main app's disabled library validation entitlement remains an open justification/revalidation item; no entitlement was changed without proving native-library compatibility. |

The inbound loopback harness uses the production protocol connection, handshake, QR verification, consent callback, and file writer. It substitutes a test delegate for the UI. The test target does not instantiate the production `AppDelegate` or automate the SwiftUI consent card; the app routing was separately inspected. No wire protocol or handshake changes were made.

## E. Transfer Reliability

- File count is capped at 128 file metadata records, matching the receiver. A 129-file selection fails in sender preflight with an actionable reason before device lookup or network transfer; it is not silently truncated.
- Folder enumeration preserves nested relative paths and Unicode names, counts skipped unsupported/unreadable entries, and reports exclusions. Empty or wholly unusable selections explain what happened and how to continue.
- The sender opens only the current file, streams in 512 KiB chunks, and closes the handle after the file or on failure/cancellation/deinitialization.
- File identity includes device/inode/size/mtime/ctime. Descriptor-safe checks run at preparation/open and between chunks. This narrows replacement risk but does not make a mutable source snapshot atomic.
- Receiver metadata/path validation, collision handling, restrictive destination creation, cancellation cleanup, and per-transfer progress remain in effect. Rejection tests assert that no received payload file is created.
- Encrypted loopback covers empty files, a 64 MiB transfer, cancellation cleanup, safe socket close/disconnect, and multi-transfer progress. 4 GiB/50 GiB transfers, physical Wi-Fi performance, and disk-full behavior were not tested.

## F. UI/UX Improvements

- Folder selection runs asynchronously with generation checks; stale selections release security-scoped access safely.
- Transfer selection explains skipped entries and empty/unreadable folders without adding confirmation dialogs.
- Transfer progress exposes an accessibility label/value; selection and error text are clearer.
- Settings explains that incoming transfers always require approval and no longer offers insecure trust controls.
- Finder Share Extension failure logging no longer prints the raw URL.
- Manual VoiceOver, keyboard-only navigation, increased text size, contrast, permission-denied, camera, and live consent-card interaction remain unverified.

## G. QA Results

| Check | Result |
|---|---|
| Full XCTest suite | **PASS — 46 passed, 0 failed, 0 skipped.** The base `main` suite had 27 test methods; 19 methods were added on this branch. The production-path loopback suite contains 16 tests. |
| Debug build | **PASS** on Xcode 27.2. |
| Universal Release build | **PASS**, `CODE_SIGNING_ALLOWED=NO`, `ONLY_ACTIVE_ARCH=NO`; all 11 Mach-O binaries in the Release app contain `arm64` and `x86_64` slices. |
| Xcode Analyze | **PASS.** |
| Strict-concurrency build | **PASS** from a clean DerivedData directory with `SWIFT_STRICT_CONCURRENCY=complete`; Swift 5 language mode, not a Swift 6 migration. |
| Strict warning inventory | **549 distinct file/line/diagnostic pairs** after deduplicating repeated architecture emissions. Main categories include non-Sendable callback captures, mutable manager state, actor-isolated AppKit calls, and generated protobuf deprecations. No warning was emitted from the new `TransferFileSafety.swift` helper or the final main-actor selection path. |
| Site checks | **PASS:** TypeScript no-emit check; site test; site interaction checks; SEO check for 11 sitemap URLs; release-version consistency; CSS/component builds. Existing Vite `use client` directive notices remain non-fatal. |
| Installer | **PASS:** mocked failure/rollback cases; actual published v2.3.5 DMG installed in an isolated temporary path, exact asset checksum verified, `hdiutil verify` valid, strict/deep signature checks passed, version/build 2.3.5/19 confirmed. `/Applications` was not modified. |
| Diagnostics and PHP | **PASS:** diagnostics client and local backend smoke tests; all six diagnostics PHP files linted. |
| Security/dependency checks | **PASS:** `npm audit --audit-level=moderate` reported zero vulnerabilities; Gitleaks scanned `main..HEAD` with zero findings; `git diff --check` passed. |

External-device coverage was **not run**: Android ↔ Mac Quick Share/QR, Windows ↔ Mac packaged Release, USB MTP disconnect/recovery, and minimum supported macOS 14 runtime. There is no deterministic test that waits out the full consent timeout, nor an incoming-connection stress test at the eight-connection limit. No XCTest cases were skipped; hardware and manual checks are separate gaps, not skipped tests.

## H. Release Readiness

- **Minimum OS:** project deployment target remains macOS 14. Universal compile succeeded against the installed macOS 27.2 SDK. A macOS 14 runtime/VM launch and transfer check remains required.
- **Current published version:** v2.3.5, build 19. The published release is ad-hoc signed, not Developer ID notarized. Its actual DMG was verified and installed only in a guarded temporary location. See the [v2.3.5 release](https://github.com/arslanbasharat-o-o/NearByDrop/releases/tag/v2.3.5).
- **Branch artifacts:** no new release package or appcast was produced. Release signing/package tooling was not run because its configuration may access a local Sparkle signing key. No production credentials were requested or created.
- **Installer safety:** checksum verification, `hdiutil`, codesign, version checks, staging, rollback, and symlink refusal passed local tests. The installer does not run `xattr -cr` or remove quarantine.
- **Gatekeeper guidance:** follows Apple's documented [Open Anyway](https://support.apple.com/en-us/102445) flow; no quarantine bypass is recommended.
- **Notarization:** remains an external release gate. Readiness steps: provision maintainer-controlled Developer ID and notarization credentials; sign the app and nested code with the intended hardened-runtime options; validate USB library compatibility and the library-validation entitlement; notarize and staple the app/package; assess Gatekeeper on a clean supported macOS install; verify Sparkle signing/update continuity. Follow [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution).
- **Release blockers:** external hardware interoperability, macOS 14 runtime, and the release signing/notarization decision. No local build, automated test, or installer test is failing.

Do not add the trusted-device behavior to historical v2.3.5 notes. Recommend a concise trusted-device/manual-approval, safe-folder, and installer-integrity entry in the next unreleased changelog section.

## I. Architecture and Concurrency

Folder selection now produces a Sendable result from background work and applies model state on the main actor. `TransferModel.setFiles`/`chooseFiles` and the AppDelegate send entry are actor-isolated; the callback is `@MainActor @Sendable`. Selection generations prevent late asynchronous results from overwriting a newer choice. These changes remove strict-mode warnings from the new selection path.

The clean strict build still emits 549 distinct diagnostic sites across pre-existing UI, callback, manager, USB, Share Extension, and generated protobuf code. Prioritize `NearbyConnectionManager` shared mutable state and cross-queue delegate/model captures; then isolate AppKit/UI callbacks and evaluate generated-code updates. Do not suppress these with blanket `@unchecked Sendable`. The build remains Swift 5 language mode, so a Swift 6 migration requires separate ownership design and test work.

The file safety checks narrow source replacement risk but leave a check-to-read race. A stronger guarantee would require a stable opened descriptor/snapshot strategy that prevents in-place concurrent writes, plus platform-focused validation; the current implementation does not claim that guarantee.

## J. Local Git Commits

The implementation commits on this branch are:

| SHA | Subject |
|---|---|
| `272bfe7bbdbe78f4f2f7d93964865b6de36f65fc` | Quick Share asks before receiving files |
| `7e2c23dd63bbbb5799c9c821de8fbdaefa879b8b` | Keep links out, open files on demand |
| `30e35d5d68562d6b450503ed87b921c6d83c27f4` | Verify installers and sync release facts |
| `e89f85fd166c7786421024aed50b6ad6869a09ac` | Keep folder selection on the main actor |
| `8c3fff3b683e3fde248c081e2b54e96ec34afa25` | Explain empty and unreadable folder picks |

This report is committed in a final documentation commit; its SHA is given in the handoff. All commits are local. Comparison to base currently covers 25 implementation/configuration/test/documentation paths plus this report. The pre-existing untracked `audit-output/NEARBYDROP_MASTER_AUDIT.md` remains untouched and unstaged.

### Changed file list

```text
.github/workflows/build.yml
.github/workflows/site-seo.yml
CHANGELOG.md
NearByDrop.xcodeproj/project.pbxproj
NearByDrop/AppDelegate.swift
NearByDrop/AppSupport.swift
NearByDrop/SettingsView.swift
NearByDrop/TransferWindow.swift
NearbyShare/InboundNearbyConnection.swift
NearbyShare/NearbyConnection.swift
NearbyShare/NearbyConnectionManager.swift
NearbyShare/OutboundNearbyConnection.swift
NearbyShare/TransferFileSafety.swift
ShareExtension/ShareViewController.swift
Tests/NearbyShareSafetyTests.swift
audit-output/PR1_TRUSTED_DEVICE_SECURITY_REPORT.md
docs/assets/site-components.js
docs/index.html
docs/llms.txt
package.json
scripts/check_release_version.py
scripts/install.sh
scripts/release-version.json
scripts/site-components.tsx
scripts/tests/install.sh
audit-output/NEARBYDROP_STABILIZATION_FINAL_REPORT.md
```

The original implementation/configuration/test/documentation diff against `main` was 25 paths, 1,469 insertions, and 331 deletions before adding this report. The master audit itself was not modified.

## K. Remaining Issues

### Critical blockers

None identified in the reviewed source or automated checks. No confirmed P0/P1 issue remains.

### Release blockers / external gates

- Decide and complete Developer ID signing/notarization for any new public release; current distribution remains ad-hoc signed.
- Exercise the declared macOS 14 minimum on a runtime/VM.
- Verify Android/QR, Windows packaged Release, and USB MTP with physical devices.
- Manually verify the approval/decline UI and accessibility flows.

### Nonblocking technical debt

- Triage the 549 strict-mode diagnostic sites; the clean strict build passes but is not warning-clean.
- Revisit main-app library-validation entitlement with signed native-library compatibility evidence.
- Eliminate or further reduce the file identity check-to-read mutation window if stronger source immutability is required.
- Add deterministic disk-full, duplicate output-name, permission-denied, repeated interruption, and very large-file tests; perform 4 GiB/50 GiB and folder-scale resource measurements.

### Deferred feature opportunities

See Section M; none was implemented in this sprint.

## L. Release Decision

**CONDITIONALLY READY — EXTERNAL VALIDATION REQUIRED**

The local source/security objective passes: manual approval gates every inbound transfer, QR proof rejects invalid keys, rejected flows do not write payloads, folder symlinks are excluded, sender/receiver limits match, installer failure paths preserve the existing app, and automated tests/builds pass. Engineering review can proceed on this evidence. Public release remains gated on minimum-OS and device checks plus the maintainers' signing/notarization choice. This is not authorization to publish.

CodeRabbit CLI was authenticated and reviewed the committed branch against `main`, not the unrelated release tag. It reported one minor changelog suggestion to add the unshipped trusted-device behavior under published v2.3.5; that suggestion was treated as a false positive to preserve historical release notes. No actionable implementation finding was reported. The final added test-only assertion was committed afterward and reviewed locally.

## M. Next Product Phase

After completing external validation, the highest-value follow-up is recovery and observability based on real failure data:

1. Retry a failed transfer as a new attempt with clear partial-file cleanup semantics.
2. Add an explicit pause control for receiving/device visibility with a discoverable state indicator.
3. Offer an opt-in redacted diagnostic export that avoids paths, filenames, QR keys, and payload data.
4. Improve device discovery/recovery from Android and Windows interoperability evidence.
5. Improve USB MTP disconnect and resume behavior only after repeating Pixel/Nexus and large-directory tests.

Do not add per-device trust or preferences until a stable identity cryptographically bound to the authenticated session is available.
