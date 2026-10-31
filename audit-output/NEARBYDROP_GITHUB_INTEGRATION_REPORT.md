# Nearby Drop GitHub Integration & CI Verification

- Date: 2026-10-31
- Branch: feature/nearbydrop-product-sprint-1
- Canonical comparison base: b930be3705632465dcb144d28ae2798767f734d3
- Source correction commit: 1685c4e60f72681c78a72b2e5bded85d0e9d490c
- Final disposition: INTEGRATION BLOCKED

## Decision

The implementation and local validation are ready for engineering review. The GitHub pull request is blocked by the repository's current PR workflow: it runs the package job with the configured SPARKLE_PRIVATE_KEY and uses that key to sign a generated Sparkle appcast. The integration brief prohibits triggering production-secret access when an automatic production-safe path has not been established.

The feature-branch push itself matches no workflow push filter and does not publish or deploy. The branch push is authorized and is kept separate from PR creation. No PR was opened, and no feature-branch CI run exists. I did not disable workflows, weaken checks, or change the release workflow as part of this feature review.

This is an integration blocker, separate from the outstanding public-release gates listed below. No merge, tag, release, deployment, or feed update was performed.

## Repository and diff

The local branch is feature/nearbydrop-product-sprint-1. At the final source review it was 15 commits ahead of origin/main and zero behind. The fetched remote refs for main and beta both remain at b930be3705632465dcb144d28ae2798767f734d3. No existing pull request targets this branch. The branch preserves its existing history.

Against origin/main, the source and existing audit-document diff contains 30 paths, 3,801 insertions, and 410 deletions. This report adds one more path. The work covers:

- Trusted-device consent hardening and protocol-state/payload authorization.
- Safe folder traversal, file-count limits, lazy file handles, and retry attempt isolation.
- Receiving pause/resume, listener cancellation and port-collision handling.
- Local privacy-filtered diagnostics preview and export.
- Settings and transfer-window UI, installer and release metadata checks, and website updates.
- Security, reliability, release-candidate, feature, and integration reports plus expanded tests.

The complete changed-file list, including this report, is:

~~~
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
audit-output/NEARBYDROP_FEATURE_SPRINT_1_REPORT.md
audit-output/NEARBYDROP_FINAL_INTEGRATION_REVIEW.md
audit-output/NEARBYDROP_GITHUB_INTEGRATION_REPORT.md
audit-output/NEARBYDROP_RELEASE_CANDIDATE_REVIEW.md
audit-output/NEARBYDROP_STABILIZATION_FINAL_REPORT.md
audit-output/PR1_TRUSTED_DEVICE_SECURITY_REPORT.md
docs/assets/site-components.js
docs/assets/site.css
docs/index.html
docs/llms.txt
package.json
scripts/check_release_version.py
scripts/install.sh
scripts/release-version.json
scripts/site-components.tsx
scripts/tests/install.sh
~~~

The pre-existing untracked audit-output/NEARBYDROP_MASTER_AUDIT.md remains untouched and is not included.

## Review findings

The source review found no confirmed bypass of manual inbound approval. Inbound introductions are accepted only after the authenticated handshake and proceed through the normal consent path. Valid QR pairing authenticates the sender and then requests manual approval; malformed QR data and mismatched keys are rejected. Device display names, connection identifiers, and legacy trust metadata do not grant consent. Legacy migration invalidates only the obsolete trustedDevices preference.

Consent submission and timeout callbacks are guarded by per-connection state on serialized queues. Duplicate or stale approvals cannot move a terminated connection into acceptance. Pause cancels pending unapproved connections while preserving already-approved transfers; disconnect and cancellation close descriptors and clean partial outputs. Accepted file/URL payload handling is gated on approval. The tests exercise accepted writes and rejected/declined no-write outcomes, plus encrypted loopback flows. Dedicated full-duration consent-timeout and eight-simultaneous-inbound stress tests were not run.

File transfer review covered the 128-file boundary, source revalidation, symlink/FIFO refusal, lazy descriptor opening, destination no-follow/exclusive creation, retries with fresh consent, and partial-file cleanup. Diagnostics use a fixed allowlist and local preview/save flow; reviewed logging does not emit raw frames, file paths, peer identifiers, keys, tokens, or payloads. User-facing errors retain actionable descriptions.

The final integration pass found and fixed one receive-state UI regression: an asynchronous starting callback after resume could leave receivingPaused true until publication completed. TransferModel now derives that flag from every advertisement-state callback. A rapid pause/resume test also stopped asserting listener existence synchronously; it now waits for the actual listener-ready callback. These changes are in 1685c4e60f72681c78a72b2e5bded85d0e9d490c (Keep receiving awake through listener restarts).

Settings, diagnostics preview/save, transfer controls, and keyboard affordances were inspected statically. A packaged candidate GUI test was not run: there is no verified isolated runtime that avoids sharing the installed app's bundle identity and user defaults. Keyboard and VoiceOver behavior remain unverified at runtime.

## CodeRabbit

The authenticated CodeRabbit CLI completed a deep review against the exact main base commit b930be3705632465dcb144d28ae2798767f734d3. It reviewed all 30 source-diff files, including the two final local corrections, and reported zero findings. This is a code review result, not GitHub CI evidence.

## Workflow and GitHub safety

The Build workflow's push trigger is limited to main, beta, and v* tags. A feature-branch push therefore starts no workflow. Pull requests targeting main or beta run diagnostics, macOS test jobs, and a package job. That package job passes SPARKLE_PRIVATE_KEY to scripts/package-release.sh; the script uses it with Sparkle generate_appcast to sign an appcast, then uploads package artifacts. The GitHub Release action is separately restricted to v* tags, but the PR still accesses the signing secret and produces package artifacts. This workflow behavior predates the feature branch and is an inherited integration blocker.

The Site SEO workflow runs checks on a PR and only sends IndexNow after a successful push to main and its Pages deployment. GitHub Pages is configured for legacy publication from main/docs. The beta mirror is triggered only by a push to main and performs a fast-forward-only update. There are no feature-head Actions results: the branch push does not match a workflow trigger, and no PR was opened.

For context only, the recent Site SEO run on main succeeded at the audited base commit: https://github.com/arslanbasharat-o-o/NearByDrop/actions/runs/41111499110. It does not validate this feature branch.

The PR was not created because its package job would consume the signing secret. Resolving that requires a separately approved workflow-safety change or a verified safe PR path; this feature review did not alter automation to bypass the blocker.

## Validation results

| Check | Result |
| --- | --- |
| Full XCTest suite | PASS — 69 passed, 0 failed, 0 skipped. |
| Debug build | PASS. |
| Universal Release build | PASS — verbose build succeeded; all 13 bundled Mach-O binaries verified for arm64 and x86_64. |
| Xcode Analyze | PASS. |
| Strict concurrency | PASS with SWIFT_STRICT_CONCURRENCY=complete in Swift 5 mode. Compiler warnings remain; the code is not Swift 6 warning-clean. Review did not confirm a new data race. |
| Installer safety tests | PASS — checksum/asset selection, failure rollback, symlink refusal, and preservation of an existing app. |
| Diagnostics client and backend | PASS — client disclosure/consent cases and backend setup, ingestion, deduplication, dashboard, timestamp, retention, and rate-limit smoke cases. |
| PHP syntax | PASS — five public diagnostics PHP files. |
| Website checks | PASS — TypeScript, release-version consistency, site tests/interactions, component bundle reproducibility, SEO checks for 11 sitemap URLs, and npm audit with zero reported vulnerabilities. |
| Secret scan | PASS — 15 commits from origin/main scanned, no leaks found. |
| Diff integrity | PASS — git diff --check. |
| CodeRabbit | PASS — completed full base-to-branch review, zero findings. |
| GitHub CI for feature SHA | NOT RUN — no PR was opened; feature branch does not match the workflow push filters. |
| Packaged GUI smoke test | NOT RUN — no isolated candidate runtime was verified. |

The local Node 24.21/npm 12 CSS generation check produced six selectors absent from the committed stylesheet. The same output difference reproduces at origin/main under this toolchain, so it is not established as a branch regression and the stylesheet was left unchanged. The main Site SEO workflow run linked above succeeded. This integration result supersedes the earlier local CSS reproducibility statement in the final integration review.

## Remaining risks and release gates

Integration is blocked on the PR workflow signing-secret behavior. Swift concurrency checking succeeds in Swift 5 mode, but compiler warnings remain and the branch is not Swift 6 warning-clean. Consent timeout and maximum concurrent inbound stress coverage are incomplete. The source mutation check-to-read window documented in the prior audit remains a residual file-safety risk.

Before public release, complete:

1. Isolated packaged-app GUI launch, retry/pause flows, diagnostics preview/save, keyboard navigation, and VoiceOver.
2. macOS 14 runtime verification.
3. Physical Mac-to-Android and Mac-to-Windows two-way transfers, QR pairing and manual approval, retries, declines/no-write, and peer disappearance.
4. USB/MTP, sleep/wake, network recovery, and maximum-concurrency testing.
5. Apple Developer ID signing and notarization decision, Gatekeeper clean-install check, and Sparkle update verification.
6. Final release artifact integrity verification and fresh version/build number.

These release gates do not establish the GitHub PR status; likewise, a future merge would not satisfy them automatically.

## Git status and handoff

The only source correction commit in this final review is 1685c4e60f72681c78a72b2e5bded85d0e9d490c. This report is committed separately. The feature branch push is authorized and does not trigger the inspected workflows; its verified remote SHA is provided in the final handoff. No pull request, merge, release, tag, deployment, or production feed update was performed. The master audit remains untouched.

Final status: INTEGRATION BLOCKED.
