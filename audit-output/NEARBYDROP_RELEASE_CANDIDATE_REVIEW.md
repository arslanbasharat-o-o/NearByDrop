# Nearby Drop Final Stabilization Validation and Feature Handoff

**Date:** 2026-10-31
**Branch:** `stabilization/nearbydrop-hardening`
**Expected stabilization HEAD verified:** `0c383f7f11ef62451a05446bf4f7467de4f74a4c`
**Correct common ancestor with `main`:** `b930be3705632465dcb144d28ae2798767f734d3`
**Candidate application source commit:** `47cda853cf65cb8fa9c8e9501b7cbe97a4600535`

## 1. Verified Source Baseline

At task start, `HEAD` matched the expected stabilization commit on `stabilization/nearbydrop-hardening`. `main` was its actual merge base. The branch contained PR 1 commit `272bfe7bbdbe78f4f2f7d93964865b6de36f65fc` and all four stabilization implementation commits, plus the final stabilization report commit. The 26 changed paths at that baseline matched `NEARBYDROP_STABILIZATION_FINAL_REPORT.md`; the untracked `audit-output/NEARBYDROP_MASTER_AUDIT.md` was present and was preserved.

No unrelated or credential-bearing file was introduced. Gitleaks reported no leaks in the seven commits through the final source correction. Website build outputs and temporary package files remain outside the repository. The source correction adds four regression tests, tightens descriptor reads, prevents raced FIFO opens from blocking, adds checked `Sendable` conformances for value-only metadata, and records the next release notes. No wire format changed.

The old v2.3.5 section and its historical wording remain intact. The current branch diff contains the original 26 paths plus this review report (27 total). The stabilization summary remains an accurate record of the earlier `0c383f7` baseline; this document records the later validation and correction.

Final path list against `main`:

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
audit-output/NEARBYDROP_RELEASE_CANDIDATE_REVIEW.md
audit-output/NEARBYDROP_STABILIZATION_FINAL_REPORT.md
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
```

## 2. Filesystem Race and Security Conclusion

### Checks performed

- Folder traversal uses `lstat`/`fstatat(..., AT_SYMLINK_NOFOLLOW)`, descriptor-relative directory walking, and no-follow opens. Implicit and explicit symlinks are excluded.
- A selected file is opened read-only with `O_NOFOLLOW`; its descriptor is checked with `fstat` against the captured device, inode, size, modification time, and change time before it is returned.
- The opened descriptor remains bound to that inode if the path is later renamed or replaced. A later symlink cannot redirect a descriptor-based read.
- Before and after every 512 KiB maximum chunk read, descriptor identity is checked. A changed identity rejects the chunk before the copied buffer is framed for transmission.
- A replaced file or parent path resolving to a different regular file fails the descriptor identity comparison before a handle is returned or payload bytes are read. The OS may briefly open the substituted file to inspect its descriptor identity.
- A newly identified availability race was fixed: a local replacement with a FIFO between selection and open could make blocking `open(O_RDONLY)` wait indefinitely and stall the shared connection queue. File opens now use `O_NONBLOCK`, after which `fstat` rejects the non-regular object. The same flag is applied to files opened with `openat` during enumeration.

Regression tests added in this review:

- `testParentDirectorySymlinkReplacementFailsDescriptorIdentityCheck`
- `testSelectedFileReplacedWithFIFOIsRejectedWithoutBlocking`
- `testOpenedDescriptorDoesNotFollowLaterSymlinkReplacement`
- `testInPlaceEditAfterOpenIsRejectedBeforeReturningChunk`

### Residual mutation race

The descriptor and identity checks prevent path substitution from changing which inode is read. They do not make an open inode an atomic, immutable snapshot. A local process with write access to the same selected file could write concurrently with a read. Completed edits normally change `ctime`/`mtime` and are rejected by the post-read check; the implementation does not prove that a read racing a still-in-progress filesystem write always observes one stable version.

**Preconditions:** a local process must already be able to write the exact selected file while an explicitly approved outbound transfer is reading it. A remote peer alone cannot replace local paths or read an unrelated file through this flow.

**Severity:** residual local-file consistency/integrity risk; not a demonstrated arbitrary-file disclosure or unauthenticated network path. It is not a release-critical defect for the current threat model, but the code does not claim an atomic file snapshot.

**Stronger mitigation:** snapshot the selected source before transmission using a supported copy-on-write filesystem clone where available, verify the resulting snapshot, and otherwise spool to a private temporary file under a documented size/quota policy or fail closed. This has material storage, latency, and filesystem-compatibility costs and was not added to this stabilization correction.

## 3. Swift Concurrency Warning Triage

The clean `SWIFT_STRICT_CONCURRENCY=complete` build passed in Swift 5 language mode. Diagnostics below are unique Swift source file/line/message tuples after removing repeated arm64/x86_64 emissions. The categories are diagnostic classes, not counts of confirmed runtime races. Each site is assigned once, in the order shown.

| Category | Before | After | Review |
|---|---:|---:|---|
| Potentially dangerous state-race diagnostics | 73 | 60 | Includes Swift 6 “sending … risks data races” and shared-state warnings. The central network/consent state is serialized on `NearbyConnection.connectionQueue`; manager maps and listener/discovery state use `stateQueue`; download-scope globals are protected by `NSLock`; diagnostics retry state is confined to its serial queue. No confirmed unsynchronized write in those reviewed paths was found. Remaining sites still need compiler-visible ownership/actor isolation. |
| UI/AppKit actor-isolation diagnostics | 105 | 105 | `AppDelegate`, SwiftUI, dialogs, and AppKit operations rely on main-thread framework callbacks or explicit main-queue hops. No broad actor migration was attempted. Add `@MainActor` boundaries incrementally and verify callback entry points before moving to Swift 6 mode. |
| Callback ownership and cancellation captures | 160 | 145 | Many captures cross serial queue/main-queue boundaries. Value-only `RemoteDeviceInfo`, `TransferMetadata`, `FileMetadata`, `EndpointInfo`, error reasons, and advertisement state now explicitly conform to `Sendable`; mutable connection/manager objects remain unannotated and queue-confined. USB cancellation uses the bridge’s documented atomic flag; MTP operations use one serial queue. The drag/drop collector uses a lock and a dispatch-group completion before main-queue consumption. |
| Generated dependency/protobuf diagnostics | 172 | 172 | Generated `.pb.swift` files report deprecated dictionary-literal initializers and non-Sendable generated storage. No generated dependency source was hand-edited. Regenerate with a compatible SwiftProtobuf toolchain in a dedicated dependency update. |
| Lower-risk migration diagnostics | 39 | 36 | Mostly calls to deprecated SwiftProtobuf `serializedData` APIs and compatibility/migration notices. Address with generated-code updates and API migration, not warning suppression. |
| **Total** | **549** | **518** | **31 warning locations removed; strict build remains warning-bearing, not a Swift 6 migration.** |

The reductions came from real `Sendable` conformances on value types whose stored members are value-safe. No `@unchecked Sendable` conformance was added. The queue/lock review does not prove every legacy callback safe; it identifies ownership evidence and migration work rather than treating every diagnostic as a confirmed race.

## 4. Test Results

| Check | Result |
|---|---|
| Full XCTest suite | **PASS — 50 passed, 0 failed, 0 skipped.** `main` had 27 test methods; 23 are now added on the branch. |
| Debug build | **PASS.** |
| Universal Release build | **PASS** with `ARCHS="arm64 x86_64"`, `ONLY_ACTIVE_ARCH=NO`, and signing disabled for compilation. |
| Xcode Analyze | **PASS.** |
| Clean strict-concurrency build | **PASS**, Swift 5 language mode; 518 distinct warning locations remain as classified above. |
| Site tests | **PASS:** one site test; site interaction checks passed for FAQs, modes, diagnostics, deep links, clipboard errors, theme persistence/cross-tab behavior, and hero accents. |
| TypeScript / SEO / version | **PASS:** `tsc --noEmit`; 11 sitemap URLs; release references agree on published v2.3.5/build 19 with an optional Unreleased section. |
| Installer tests | **PASS:** mock checksum, asset, mount/copy failure, signature rollback, symlink, and prior-app preservation cases. Actual local candidate installation and failure-preservation checks are detailed in §5. |
| Diagnostics / PHP | **PASS:** client tests; local backend smoke tests for setup/sign-in/ingestion/deduplication/dashboard and retention/rate limits; all six diagnostics PHP files linted. |
| Dependency / secret checks | **PASS:** `npm audit --audit-level=moderate` found 0 vulnerabilities; Gitleaks found no leaks in the seven source commits; `git diff --check` passed. |

XCTest ran on the available arm64 Mac with Xcode 27.2 and macOS 27.2. The final 50-test run also included the corrected parent-symlink test name; that documentation/test-symbol-only correction does not change the packaged app source at `47cda853cf65cb8fa9c8e9501b7cbe97a4600535`. No tests were skipped. XCTest does not certify Android/Windows interoperability, MTP hardware, the macOS 14 runtime, Gatekeeper launch, or accessibility interaction.

## 5. Local Release Candidate Verification

### Artifact

The Release app was packaged locally from source commit `47cda853cf65cb8fa9c8e9501b7cbe97a4600535`. The artifact is clearly marked **NON-PUBLIC — DO NOT DISTRIBUTE** and is outside the repository:

- DMG: `/tmp/NearbyDrop-NONPUBLIC-47cda85/Nearby-Drop-2.3.5.dmg`
- Universal ZIP: `/tmp/NearbyDrop-NONPUBLIC-47cda85/Nearby-Drop-2.3.5-universal-NON-PUBLIC-LOCAL-CANDIDATE.zip`
- Checksums: `/tmp/NearbyDrop-NONPUBLIC-47cda85/SHA256SUMS.txt`
- Candidate manifest: `/tmp/NearbyDrop-NONPUBLIC-47cda85/NON-PUBLIC-LOCAL-CANDIDATE.txt`
- Isolated install: `/tmp/NearbyDrop-NONPUBLIC-47cda85/Install Destination With Spaces/Nearby Drop.app`

SHA-256:

```text
67b1056fd0bd5d71b95e92731095a860ef5bc131fb74b75c6b7645ded09d6c2a  Nearby-Drop-2.3.5.dmg
441d14e61b03472f21a7d04904ecd125ff5fb6129099f27686698a8847fb4187  Nearby-Drop-2.3.5-universal-NON-PUBLIC-LOCAL-CANDIDATE.zip
```

### Verification

- Every one of the 13 Mach-O files in the app bundle contains both `arm64` and `x86_64` slices.
- Bundle metadata is v2.3.5/build 19 with minimum macOS 14.0. The current version is retained solely to validate the non-public candidate; it must not be published as v2.3.5.
- The app, extension, Sparkle framework/tools, and bundled libraries passed `codesign --verify --deep --strict`. Signature state is **ad hoc** (`Signature=adhoc`, no Developer ID Team ID); hardened-runtime options are present on the main app. **Not notarized.**
- The bundle embeds Sparkle's HTTPS feed URL, public EdDSA key, and `SURequireSignedFeed=true`. No appcast was generated: the packaging script's appcast step may access the maintainer's Sparkle signing key. No credential or Keychain signing operation was attempted.
- `hdiutil verify` reported the candidate DMG checksum valid. Local SHA-256 verification passed for both artifacts.
- The actual `scripts/install.sh` installed the candidate into an isolated destination whose path contains spaces. A local `curl` fixture supplied only this candidate DMG and its checksum; the installer's own exact-asset checksum, mount, signature, version, staging, and replacement code ran. The existing `/Applications` app was not touched.
- With a deliberately mismatched candidate checksum, the installer rejected the package and the previously installed isolated candidate remained signature-valid. With a controlled `DITTO_BIN` staging-copy failure, the installer returned failure, kept the previous isolated install signature-valid, and removed its staging directory. Mock tests separately cover mount/signature/rollback behavior.
- The app was not launched. Gatekeeper first-launch behavior and Sparkle update execution remain external checks.

The repository's `scripts/package-release.sh` was not run end-to-end because its final Sparkle step may read a maintainer signing key. Packaging steps before that point were carried out locally, without credentials, then independently checked. This artifact is an engineering validation candidate, not a signed/notarized release.

## 6. Remaining Blockers and External Validation Checklist

The following physical-device, VM, and manual UI checks were unavailable and remain **NOT RUN**:

| Check | Status | Required validation |
|---|---|---|
| Android → Mac incoming transfer | **NOT RUN** | Test one/multiple files, Unicode and nested folder names, accept/decline, cancellation, progress, and no payload write after decline. |
| Mac → Android outgoing transfer | **NOT RUN** | Test selected files/folders, 128/129 boundary, link exclusions, empty files, and receiver-side completion. |
| QR pairing | **NOT RUN** | A valid QR proof must reach the same manual consent UI; approval receives the payload; decline writes nothing; wrong key is rejected before consent. |
| Windows ↔ Mac two-way | **NOT RUN** | Exercise both directions on a physical Windows PC with the packaged candidate and current Quick Share. |
| USB MTP | **NOT RUN** | Browse storage, upload/download files and nested folders, test empty/large files, unplug during transfer, cleanup, reconnect, and retry. |
| Network interruption / cancellation | **NOT RUN on hardware** | Interrupt each direction before consent, during a chunk, at completion, and after cancellation; verify state reset and no stale/partial destination files. Automated loopback covers some but not physical networking. |
| Large files / folder scale | **NOT RUN beyond local 64 MiB loopback** | Measure 4 GiB and 50 GiB files plus 128/1,000/10,000-item folders, memory, file descriptors, time-to-first-byte, throughput, and cleanup. |
| macOS 14 minimum runtime | **NOT RUN** | Launch, permissions, incoming/outgoing transfers, USB, camera, updater, and installation on a macOS 14 VM or supported device. Universal compilation on macOS 27.2 is not runtime certification. |
| VoiceOver / keyboard | **NOT RUN** | Complete Send/Receive/Transfers/USB workflows, approval/decline, cancel, status/progress, focus order, increased text, and permission-denied flows without a pointer. |
| Candidate installation | **Partially verified** | Mechanical DMG verification and actual install into a temp destination passed. On clean macOS, test first launch/Gatekeeper and user guidance; do not remove quarantine. |
| Candidate update | **NOT RUN** | Validate a genuinely Developer ID signed, notarized candidate and signed Sparkle feed/update continuity on clean supported macOS. The local ad hoc candidate is not suitable for this check. |

Before public release, also choose the supported signing/notarization route, perform macOS 14 and device validation, complete the accessibility pass, and publish a new version/build with a signed appcast. Apple's [Gatekeeper guidance](https://support.apple.com/en-us/102445) and [notarization documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution) are referenced; the current public [v2.3.5 release](https://github.com/arslanbasharat-o-o/NearByDrop/releases/tag/v2.3.5) remains the historical version and is not the candidate.

## 7. Proposed Unreleased Changelog

This proposed section was added above the unchanged historical v2.3.5 notes in `CHANGELOG.md`; `check_release_version.py` now validates the optional Unreleased heading and still pins the current published release.

```markdown
# Unreleased

- Require approval for every incoming transfer, including valid QR pairings.
- Exclude symbolic links and reject files changed during outbound reads.
- Enforce the 128-file limit and open source files only while sending.
- Verify installer checksums and preserve the existing app on failed upgrades.
```

The eventual release should receive a new version/build and release-specific notes. Do not tag, upload, or reuse v2.3.5 for this branch.

## 8. GitHub Integration Readiness

The corrected source and tests are **ready for GitHub integration review**. The clean common ancestor is `main` at `b930be3705632465dcb144d28ae2798767f734d3`; the old unrelated release tag was not used. Full XCTest, Debug, universal Release, Analyze, strict build, website/version, installer, diagnostics, dependency, and secret checks passed.

This means the code can be reviewed and discussed as an integration change. It does **not** mean the device matrix is certified or that the branch may be released. The local candidate remains non-public and ad hoc signed.

## 9. Next Feature Sprint Specifications

These are planning specifications only; none is implemented in this task.

### 9.1 Retry a failed transfer as a fresh attempt

- **Technical design:** Add an explicit retry action for failed outbound transfers. Create a new `NWConnection`, UKEY2 session, transfer ID, payload IDs, acknowledgement set, and state machine instance. Revalidate every source file against its saved identity before starting. Do not resume old sequence numbers or silently resend after a terminal failure. For inbound transfers, the receiver can clean partial output and prompt the user to ask the sender to initiate a new transfer; it cannot replay a peer's payload itself.
- **Dependencies:** `TransferModel` failure state, `NearbyConnectionManager` connection lifecycle, `OutboundNearbyConnection` preflight/identity checks, cancellation and acknowledgement cleanup, and `InboundNearbyConnection` partial-file cleanup.
- **Acceptance criteria:** Retry is user initiated; every retry has new session/transfer/payload IDs; a changed source requires re-selection; callbacks from the failed attempt cannot update the retry row; a rejected/canceled attempt never becomes accepted; partial destinations are cleaned or reported explicitly; duplicate names do not overwrite prior successful files.
- **UI considerations:** Keep the original failure reason visible. Place “Retry as new transfer” on an eligible failed outgoing row; disable it while the original attempt is active or sources are unavailable. Never label it resume if it starts from byte zero.
- **Tests:** Connection failure before consent, disconnect mid-chunk, failure after one of several files, explicit cancel, stale completion callback, changed source, duplicate filename, and successful retry proving new IDs and no partial overwrite.

### 9.2 Pause receiving and control device visibility

- **Technical design:** Add a stateQueue-owned receive-visibility state in `NearbyConnectionManager`. Pausing stops new inbound acceptance and Bonjour/BLE visibility without terminating already accepted transfers. New inbound sockets during pause are rejected before creating a consent row. Resume republishes the service and refreshes discovery metadata. Define how an active QR receive session expires on pause and ensure resumed advertising does not revive an old pairing proof.
- **Dependencies:** Manager listener/NetService/Bluetooth lifecycles, `AdvertisementState`, incoming connection admission, QR receive timeout, and Settings/Receive UI state.
- **Acceptance criteria:** Pause immediately removes the device from discovery and blocks new incoming consent; existing approved transfers continue; repeated pause/resume is idempotent; listener failures remain visible; resume creates fresh discovery state; QR sessions do not survive pause unless explicitly rescanned.
- **UI considerations:** Provide one clear Receive visibility toggle with visible Paused/Visible status and a brief explanation that active transfers continue. Keep the control reachable from Receive and Settings. Do not make pause look like transfer cancellation.
- **Tests:** Pause while idle, pause with an incoming request pending, pause during an accepted transfer, fresh connection rejection while paused, resume/re-advertise, repeated toggles, QR expiry, and listener restart failure.

### 9.3 Previewable, redacted diagnostic export

- **Technical design:** Build an opt-in local diagnostic bundle from an allow-listed schema, not raw application logs. Include app/build/OS versions, redacted error categories, coarse timestamps, and bounded protocol phase summaries. Exclude file contents, filenames, paths, local/peer names, endpoint IDs, IP addresses, QR keys/tokens, payload bytes, and authentication material. Generate locally and require an explicit export/share action; do not upload automatically.
- **Dependencies:** `UsageAnalytics` event schema, `NearbyLogger` policy, a redaction/allow-list module, Settings diagnostics UI, temporary-file cleanup, and file-size limits.
- **Acceptance criteria:** Preview equals exported content; canary secrets inserted into every excluded field never appear; user can cancel before export; no network request occurs; export is capped and temporary files are removed; analytics opt-out remains independent and honored.
- **UI considerations:** Show a readable preview before Save/Share, state exactly what is included, allow copying an error identifier, and keep raw diagnostic detail out of the default view. Do not imply that export shares transfer files.
- **Tests:** Redaction canaries for path/name/host/IP/endpoint/QR/payload; schema allow-list rejects unknown keys; export-size cap; cancellation and temp cleanup; opt-out/no-network checks; preview/export equality; malformed log input handling.

## 10. Commits and Final Git Status

The verified source correction is local commit:

| SHA | Subject |
|---|---|
| `47cda853cf65cb8fa9c8e9501b7cbe97a4600535` | Pin file reads and dodge FIFO stalls |

It follows the original PR 1 and stabilization commits listed in `NEARBYDROP_STABILIZATION_FINAL_REPORT.md`. The release-candidate artifact was built from this source commit. This report is committed separately; its commit SHA is provided in the final handoff.

After the report commit, expected Git status is clean except for the same pre-existing untracked `audit-output/NEARBYDROP_MASTER_AUDIT.md`. No push, merge, deploy, release, or live-service change was made. The candidate artifacts remain under `/tmp/NearbyDrop-NONPUBLIC-47cda85/` and are not tracked.

## Final Decision

**CONDITIONALLY READY — EXTERNAL VALIDATION REQUIRED**

The source is ready for GitHub integration review, the confirmed FIFO queue-stall race is fixed, path substitutions are rejected before data reads, descriptor chunks are checked before transmission, and all 50 local tests/build/analysis checks pass. Public release still requires Android/Windows/USB validation, macOS 14 runtime and accessibility checks, and a Developer ID signing/notarization/update decision. The local artifact is ad hoc signed and explicitly non-public.
