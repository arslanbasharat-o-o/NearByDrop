# Nearby Drop Secure CI Integration Report

- Date: 2026-10-31
- Branch: feature/nearbydrop-product-sprint-1
- Comparison base: b930be3705632465dcb144d28ae2798767f734d3
- Secure CI implementation commit: 7cafa27ada7d1d351dfff662d74bee0f60ab9f0a
- Final status: INTEGRATION BLOCKED

## Executive result

The workflow change removes the production Sparkle key from the current PR and ordinary build jobs. PR and main/beta validation now packages only unsigned, clearly nonpublic CI artifacts. Release packaging and GitHub Release publication live in a separate tag-only workflow with an environment gate, a trusted-main ancestry check, and an exact tag-to-app-version check.

I did not open a PR. GitHub currently stores SPARKLE_PRIVATE_KEY as a repository-level Actions secret, and no release-signing environment is configured. Repository secrets are available to workflows in the repository. A same-repository PR could change a workflow to reference that secret, so the absence of a reference in the current PR workflow is not sufficient proof of isolation. The release job is disabled because RELEASE_SIGNING_ENABLED is not configured. The environment and secret migration must be completed before a PR can safely run.

The feature branch is authorized to push without triggering a workflow. This work will be pushed without force; no PR, merge, tag, release, signing job, appcast update, or deployment is part of this handoff.

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

## Current GitHub configuration and remaining blocker

Read-only GitHub inspection confirmed:

- The repository is public.
- The only configured environment is github-pages, with a branch policy. release-signing does not exist.
- The Actions secret metadata lists SPARKLE_PRIVATE_KEY at repository scope. No secret value was read, printed, downloaded, copied, or rotated.
- No Actions variables are configured, so RELEASE_SIGNING_ENABLED is unset and the signed release job remains skipped.
- The active Protect main and beta ruleset prevents deletion and non-fast-forward updates. It has no required status checks or pull-request requirement configured.
- Default workflow token permissions are contents: read.
- GitHub Pages uses legacy publication from main/docs.

GitHub documents that repository secrets are available to workflows in the repository, while environment secrets are limited to jobs that reference the environment and are withheld until its protection rules pass. See [GitHub Actions secrets](https://docs.github.com/en/actions/reference/security/secrets) and [deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

Required administrative setup before PR creation:

1. Create a release-signing environment.
2. Require approval from an authorized maintainer and enable prevention of self-review.
3. Restrict the environment to selected tags matching v*; do not allow branches or pull-request refs.
4. Add the existing SPARKLE_PRIVATE_KEY directly as an environment secret through GitHub settings. Do not copy it through a shell, CLI argument, log, or repository file.
5. After the environment secret is set, remove the repository-level SPARKLE_PRIVATE_KEY so PR workflows cannot reference a repository-scoped copy.
6. Set RELEASE_SIGNING_ENABLED=true as a variable on the protected release-signing environment, and only after steps 1–5 are verified.

Until this setup is complete, signed-release.yml will skip its job, and I will not open a PR. The public repository supports required-reviewer environment protection. The main/beta ruleset also needs a separate maintainer decision about requiring the PR checks before merge; no existing required check names are configured today.

## Workflow execution matrix

| Event | Expected behavior |
| --- | --- |
| PR to main or beta | Build runs diagnostics, both macOS test jobs, workflow security policy, and the unsigned universal package. Site SEO runs its checks and dependency audit. No signing workflow, appcast generation, release publication, Pages deployment, or IndexNow request. |
| Feature branch push | No workflow currently matches this branch. |
| Push to main | Build runs unprivileged checks and unsigned packaging, except markdown/docs-only paths excluded by its filter. Site SEO runs for its configured paths. Legacy Pages may publish main/docs changes; IndexNow is conditional on a successful main Pages deployment. The beta mirror performs a fast-forward-only update. |
| Push to beta | Build runs unprivileged checks and unsigned packaging, except ignored paths. Site SEO runs for its configured paths. No beta-to-main synchronization or release signing. |
| Push of a v* tag | Build remains unprivileged and produces nonpublic CI artifacts. Signed release is eligible only for a protected, enabled release-signing environment; it validates tag ancestry and version before building and publishing. It is currently disabled by the missing environment variable. |
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
| Gitleaks commit range | PASS — 17 commits from origin/main scanned, no leaks. |
| Full-tree Gitleaks | Two generic-api-key matches were found at PROTOCOL.md:155 and Tests/NearbyShareSafetyTests.swift:1182. Both lines were verified to exist in origin/main; they are existing protocol/test-fixture false positives. Values remained redacted. |
| Diff integrity | PASS — git diff --check. |

No GitHub CI result exists for the feature head because no PR was opened and feature pushes do not match workflow filters. The unrelated successful main Site SEO run does not validate this branch.

## Feature branch, changed files, and commits

The feature branch is 17 commits ahead of origin/main and zero behind. The workflow implementation commit is 7cafa27ada7d1d351dfff662d74bee0f60ab9f0a. The pre-existing untracked master audit remains untouched.

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

No PR URL exists. Proposed PR title: Nearby Drop: Security, Transfer Reliability, New Features & Secure CI.

## Remaining release gates

The earlier audit's GUI, accessibility, hardware interoperability, minimum macOS 14 runtime, sleep/wake/network recovery, notarization, Gatekeeper clean-install, and Sparkle update verification remain incomplete. No public release is approved by this integration work.

Final status: INTEGRATION BLOCKED — repository-level signing secret and missing protected release-signing environment prevent proving same-repository PR isolation.
