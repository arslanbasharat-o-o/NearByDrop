# Nearby Drop Secure CI Integration Report

- Date: 2026-10-31
- Branch: feature/nearbydrop-product-sprint-1
- Comparison base: b930be3705632465dcb144d28ae2798767f734d3
- Secure CI implementation commit: 7cafa27ada7d1d351dfff662d74bee0f60ab9f0a
- Current status: Draft PR #13 open; CI passed on source head `d2aea1edcf39891e79785908ca2d84babf9dd83d`.

> The configuration and blocker sections below describe the state before the 2026-10-31 recovery. This update supersedes their old current-state conclusions. The report-only follow-up commit is validated by the latest checks linked from [PR #13](https://github.com/arslanbasharat-o-o/NearByDrop/pull/13).

## Executive result

The existing Sparkle identity was recovered from the Mac login Keychain and verified against both the app and published v2.3.5 archive. The same identity was exported only into a permission-restricted temporary directory for transfer and piped to GitHub CLI over standard input. The temporary export was automatically removed. No private key material was printed, logged, committed, or stored in the repository.

The `release-signing` environment now contains the verified key. It allows only `v*` tags, has administrator bypass disabled, and the repository-level `SPARKLE_PRIVATE_KEY` was deleted only after the environment secret name was confirmed. The repository Actions variable `RELEASE_SIGNING_ENABLED` is explicitly `false`. Only the owner account has write access, so no independent release approver can be configured; production signing remains disabled.

Draft PR [#13](https://github.com/arslanbasharat-o-o/NearByDrop/pull/13) targets `main`. On source head `d2aea1edcf39891e79785908ca2d84babf9dd83d`, all six GitHub checks passed. No merge, new tag, signed-release run, release-signing deployment, appcast publication, or new release occurred.

## Original security issue and corrections

Before this change, the Build workflow ran its universal packaging job on PRs, passed SPARKLE_PRIVATE_KEY to scripts/package-release.sh, and allowed the script to fall back to Keychain signing when the environment variable was absent. The same job had contents: write and contained tag-only GitHub Release publication.

The implementation commit makes these changes:

- Pull request, main, beta, tag, and manual Build runs now use --ci-unsigned package mode. That mode refuses a supplied Sparkle key, produces files with a ci-unsigned filename suffix, writes a NONPUBLIC-CI-ARTIFACTS.txt marker, removes a stale appcast, and does not invoke generate_appcast.
- The Build package job has contents: read, uploads only the named CI artifacts, and no longer publishes GitHub Releases.
- Release packaging requires an explicit mode. --release fails immediately without SPARKLE_PRIVATE_KEY; it never falls back to Keychain. The prior local Keychain path is preserved only through explicit --release-keychain mode.
- Signed packaging and GitHub Release publication moved to signed-release.yml. It listens only for v* tag pushes, requires the environment variable RELEASE_SIGNING_ENABLED=true, references release-signing, validates that the tagged commit is an ancestor of main and that the tag equals the version in scripts/release-version.json, builds from that tag checkout, and does not consume artifacts from PR jobs. Its contents: write permission is job-scoped.
- Added a workflow policy regression check that rejects secret references outside the signed release workflow, PR jobs with deployment environments or write permissions, pull_request_target, unpinned Actions, and release behavior in the Build workflow.
- Added package-mode guard tests, runs actionlint 1.7.12 in CI with a pinned SHA-256 checksum, and added npm audit to the Site SEO checks.

All actions referenced by the repository workflows are pinned to full commit SHAs. No Apple Developer ID signing credential was added or used.

## Original GitHub configuration before recovery (historical snapshot)

Read-only GitHub inspection confirmed:

- The repository is public.
- The only configured environment is github-pages, with a branch policy. release-signing does not exist.
- The initial read-only inspection found SPARKLE_PRIVATE_KEY at repository scope and did not read or display its value. Its verified existing value was migrated later as documented in the current update above.
- No Actions variables are configured, so RELEASE_SIGNING_ENABLED is unset and the signed release job remains skipped.
- The active Protect main and beta ruleset prevents deletion and non-fast-forward updates. It has no required status checks or pull-request requirement configured.
- Default workflow token permissions are contents: read.
- GitHub Pages uses legacy publication from main/docs.

GitHub documents that repository secrets are available to workflows in the repository, while environment secrets are limited to jobs that reference the environment and are withheld until its protection rules pass. See [GitHub Actions secrets](https://docs.github.com/en/actions/reference/security/secrets) and [deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

The pending setup is now complete, with the second-reviewer requirement handled by leaving signing disabled:

1. Created the `release-signing` environment.
2. Confirmed no independent maintainer has write access; no impossible self-review rule was configured.
3. Restricted the environment to `v*` tags and disabled administrator bypass.
4. Exported the verified existing key to a permission-restricted temporary file and sent it to the environment secret using standard input.
5. Confirmed the environment secret name, then deleted the repository-level secret.
6. Set `RELEASE_SIGNING_ENABLED=false` at repository scope and kept signed release publication disabled.

GitHub has only the owner as a collaborator with write access, so a self-review rule would make releases impossible. The environment therefore has no reviewer requirement; its `v*` tag-only policy and disabled repository variable keep signing isolated and off. The main/beta ruleset still has no required status checks; recommendations are listed in the current update below.

## Workflow execution matrix

| Event | Expected behavior |
| --- | --- |
| PR to main or beta | Build runs diagnostics, both macOS test jobs, workflow security policy, and the unsigned universal package. Site SEO runs its checks and dependency audit. No signing workflow, appcast generation, release publication, Pages deployment, or IndexNow request. |
| Feature branch push | No workflow currently matches this branch. |
| Push to main | Build runs unprivileged checks and unsigned packaging, except markdown/docs-only paths excluded by its filter. Site SEO runs for its configured paths. Legacy Pages may publish main/docs changes; IndexNow is conditional on a successful main Pages deployment. The beta mirror performs a fast-forward-only update. |
| Push to beta | Build runs unprivileged checks and unsigned packaging, except ignored paths. Site SEO runs for its configured paths. No beta-to-main synchronization or release signing. |
| Push of a v* tag | Build remains unprivileged and produces nonpublic CI artifacts. Signed release additionally requires the protected `release-signing` environment and `RELEASE_SIGNING_ENABLED=true`; it remains disabled because the repository variable is explicitly false. |
| Manual dispatch | Build and Site SEO can run their unprivileged checks. There is no manual signing trigger. |

The Site SEO IndexNow step is restricted to a successful push to main after the Pages deployment. Main-to-beta synchronization remains restricted to a main push. No reusable workflows or secret inheritance are configured.

## Security validation

- actionlint 1.7.12: passed for all four workflow files. The Darwin and Linux release archives were checked against published SHA-256 digests; CI downloads the Linux binary and verifies its digest before execution.
- Workflow policy regression script: passed for all workflow files.
- Package mode guard tests: passed. Missing release key fails before packaging and does not fall back to Keychain.
- Bash syntax checks: passed.
- Real local --ci-unsigned package run: passed. It created the ad hoc signed 2.3.5 DMG and universal ZIP with the nonpublic marker, and no appcast. SPARKLE_PRIVATE_KEY was removed from that process environment.
- Workflow secret references: the only current workflow reference is in the tag-only signed-release workflow. The repository-level secret scope still prevents proving same-repository PR isolation, so PR creation remains blocked.
- No PR, release tag, release-signing job, appcast publication, or Pages deployment was triggered.

## Local validation

| Check | Result |
| --- | --- |
| XCTest | PASS — 69 passed, 0 failed, 0 skipped on macOS 27.2, arm64. |
| Debug build | PASS. |
| Universal Release build | PASS — arm64 and x86_64; package script verified each Mach-O binary. |
| Xcode Analyze | PASS. |
| Strict concurrency | PASS with complete checking in Swift 5 mode. Compiler warnings remain; this is not a Swift 6 warning-clean build. |
| Installer safety | PASS — checksum, asset selection, mount/copy failure, signature rollback, symlink refusal, existing-app preservation. |
| Diagnostics client and backend | PASS — client disclosure and retry cases; backend setup, sign-in, ingestion, deduplication, dashboard, timestamps, retention, cleanup, and rate limits. |
| PHP syntax | PASS — five public diagnostics files. |
| Website | PASS — npm ci, TypeScript, version consistency, site tests/interactions, 11 sitemap URLs, and npm audit with zero vulnerabilities. The generated component bundle matched. |
| Site CSS reproduction | Local Node 24.21/npm 12 generation differed from the committed CSS, as previously observed at origin/main with the same toolchain. The tracked stylesheet was restored byte-for-byte. A recent Site SEO run on main passed, but it is not feature-branch CI. |
| Gitleaks staged diff | PASS — no leaks. |
| Gitleaks commit range | PASS — 18 commits from origin/main scanned, no leaks. |
| Full-tree Gitleaks | Two generic-api-key matches were found at PROTOCOL.md:155 and Tests/NearbyShareSafetyTests.swift:1182. Both lines were verified to exist in origin/main; they are existing protocol/test-fixture false positives. Values remained redacted. |
| Diff integrity | PASS — git diff --check. |

GitHub CI passed on PR source head `d2aea1edcf39891e79785908ca2d84babf9dd83d`:

- Build run [41194713723](https://github.com/arslanbasharat-o-o/NearByDrop/actions/runs/41194713723): `Workflow security policy`, `Diagnostics backend`, `Test (macos-15-intel)`, `Test (macos-26)`, and `Universal app` all passed.
- Site SEO run [41194713722](https://github.com/arslanbasharat-o-o/NearByDrop/actions/runs/41194713722): `site-seo` passed, including website/SEO and dependency audit checks.
- The uploaded `nearby-drop-ci-nonpublic` artifact was inspected. It contains the nonpublic marker, `ci-unsigned` DMG/ZIP names, and no appcast. Its marker states it is for engineering validation only, not installation or distribution.

The PR check names currently observed and recommended for the main ruleset are `Workflow security policy`, `Diagnostics backend`, `Test (macos-15-intel)`, `Test (macos-26)`, `Universal app`, and `site-seo`. The ruleset was not changed; it currently prevents deletion and non-fast-forward updates only.

## Feature branch, changed files, and commits

At PR creation, the feature branch head was `d2aea1edcf39891e79785908ca2d84babf9dd83d`; this added a workflow-comment correction identifying the repository-level variable scope for the pre-environment gate. A report-only follow-up is included in PR #13; its latest head and checks are linked above. The pre-existing untracked master audit remains untouched.

The diff against origin/main contained 35 paths, 4,206 insertions, and 441 deletions before this report. The complete list including this report is:

~~~
.github/workflows/build.yml
.github/workflows/signed-release.yml
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
audit-output/NEARBYDROP_SECURE_CI_INTEGRATION_REPORT.md
audit-output/NEARBYDROP_STABILIZATION_FINAL_REPORT.md
audit-output/PR1_TRUSTED_DEVICE_SECURITY_REPORT.md
docs/assets/site-components.js
docs/assets/site.css
docs/index.html
docs/llms.txt
package.json
scripts/check_release_version.py
scripts/check_workflow_security.py
scripts/install.sh
scripts/package-release.sh
scripts/release-version.json
scripts/site-components.tsx
scripts/tests/install.sh
scripts/tests/package-release-modes.sh
~~~

PR: [#13](https://github.com/arslanbasharat-o-o/NearByDrop/pull/13), draft, title “Nearby Drop — Security, Reliability, New Features & Secure CI”.

## Remaining release gates

The earlier audit's isolated GUI and accessibility checks, hardware interoperability, minimum macOS 14 runtime, sleep/wake/network recovery, Developer ID signing/notarization, and Gatekeeper clean-install remain incomplete. The existing v2.3.5 appcast/archive signature was cryptographically verified, but no new public update was built or published. No public release is approved by this integration work.

Final status: INTEGRATION COMPLETE — draft PR open, CI passed, release signing disabled, and no merge or release performed.
