# Nearby Drop upgrade: implementation and verification

Verified November 22, 2026. Branch: `codex/tropical-upgrade`. This is a local 2.5.0 / build 21 release candidate, not a published release. The installed public stable v2.4.0 remains in place. No production backend, collection configuration, public website, release feed or remote branch was changed.

## Acceptance matrix

| Deliverable | Implemented and verified | Limits / next gate |
| --- | --- | --- |
| Three original themes and shared UI | Vice Nights, Coastal Sunrise, Midnight Route; System/Light/Dark retained. Central palettes, original Canvas artwork, shared surfaces/buttons/focus and reduced-motion handling. All six choices persist; tested text/state/button contrasts pass 4.5:1. | Native macOS dialogs retain system appearance. Full VoiceOver, Increase Contrast and all keyboard-navigation configurations need manual review. |
| App-owned states | 192 rendered fixture images across six appearances, including send, receive, QR, USB, settings, onboarding and utility sheets. Eight selected images included in this directory. Native preview tested immediate theme switching, favorites, Doctor, text input/cancellation and onboarding/privacy synchronization. | Fixtures are demonstrative data, not evidence of successful physical transfers. |
| Connection Doctor | Observed network transport/path, receiving/discovery state and actionable QR/USB guidance; explicit limits on what can be inferred. | It cannot inspect peer settings or prove network reachability. |
| Favorite recipients | Persistent name/type hints, available-first ordering, removal and offline hints. Unit coverage. | Hints do not authenticate peers or bypass approval. |
| Explicit text/link sharing | User-entered/pasted content becomes a private UTF-8 file through the existing selection/recipient flow. URL and size limits, private permissions and cleanup tested. | Native Quick Share text/link payload interoperability is unverified; the delivered fallback is a text file. |
| Screenshot sharing | Explicit ScreenCaptureKit capture or chosen image, bounded image size, preview before staging. Compiles for macOS 14+. | Real screen-permission/capture and phone transmission were not exercised. |
| USB improvements | Current-listing filtering, folder-first natural/size sorting, breadcrumbs, visible selection and fatal-error state recovery. Policy tests pass. | Physical MTP operations need device verification; filter is not recursive phone-wide search. |
| Large batches | Bounded planner tested; existing 128-file transfer cap preserved. | Execution deliberately disabled. Receiver approval/session lifetime, source access, retry and cancellation need validation before enabling; see EXPERIMENTAL-BATCHES.md. |
| Onboarding | Seven revisitable steps, skip-to-privacy, preserved receiving/privacy choices. Native retest confirmed onboarding opt-out synchronizes Settings. | Full first-run device walkthrough remains a manual gate. |
| Operational diagnostics | Versioned typed jobs/attempts/events, stable retry correlation, coarse buckets, bounded queue/backoff, separate consent and opt-out purge. Client regression/privacy/delivery tests pass. | Build gate is false in the candidate. No expanded live collection was activated. |
| Backend/dashboard | Additive migration, strict collector validation, UUID replay handling, authenticated filtered dashboard, health and honest outcome/coverage accounting. SQLite/HTTP regression tests pass. | MySQL staging migration has not been executed. No production migration or deployment occurred. |
| Release engineering | Universal Release; local RC DMG/ZIP/checksums; staged app and extension 2.5.0/21; automatic update checks disabled for private RC. Deep/strict signature, every Mach-O architecture, archive checksums and DMG integrity passed. | Ad hoc signed only. Zero valid signing identities were available. Developer ID signing, notarization and stapling remain blocked by credentials. |
| Documentation and growth | README, help/privacy, analytics definitions, release/signing guide, original screenshot set, local site preview, announcement/storyboard, official-source alternatives comparison and 30-day experiment. | Draft assets only. No publishing, external outreach or new website tracking. |

## Validation evidence

- Final XCTest run: **80 tests, zero failures**; encrypted protocol loopbacks and new policy/model tests included. Baseline was 72.
- Debug build, universal arm64 + x86_64 Release build, and Xcode static analysis succeeded. Analyzer log contained no warning lines.
- Theme persistence/contrast, legacy diagnostics client, operational client, legacy PHP smoke and operational accounting/HTTP suites passed. Operational tests cover gates, consent, opt-out, delivery acknowledgment, retries, duplicates, shuffled events, conflicting terminals, missing starts, privacy validation, dashboard authentication and filters.
- PHP lint, packaging-mode guards, workflow security checks, release-version consistency and website tests/SEO checks passed. Public-site SEO checks do not constitute a full audit of the draft site preview.
- Unpacked app and share extension both report 2.5.0/build 21; `ExpandedDiagnosticsEnabled=false`. Every packaged Mach-O includes arm64 and x86_64. DMG integrity and SHA-256 manifests passed.
- Notarization helper correctly rejected this ad hoc candidate before contacting Apple. Actual notarization was not run.
- No failed automated checks remain in this scope. This statement does not cover the unperformed manual and credential-dependent checks below.

Build/test logs from this run are local under `/private/tmp/nearbydrop-upgrade-*.log`; they are temporary, not permanent CI artifacts. Reproduction commands are in RELEASE-ENGINEERING.md. The 192 fixture images are under `build-upgrade/screenshots/`.

## Remaining release gates

1. Execute Android send/receive, Windows interoperability, QR pairing and MTP operations on real devices and networks, including failure/retry/cancellation. Check text-file receipt and screenshot capture/receipt explicitly. No physical-device results are claimed by this run.
2. Execute on an Intel Mac; universal slices are build evidence only. Complete VoiceOver, Increase Contrast, keyboard-navigation and target-screen permission checks.
3. Run migration/collector/dashboard tests in a private MySQL staging environment and review backups/rollback before any approved deployment. SQLite coverage is not MySQL execution evidence.
4. Supply an authorized Developer ID identity and notarization profile, then sign, notarize, staple and validate Gatekeeper installation. The supplied helper requires Developer ID and Hardened Runtime.
5. Separately authorize any public release, website/backend deployment or operational rollout. Review cohort/privacy disclosures before enabling either production gate. Do not enable batch execution without its safety verification.

## Prepared artifacts

- `dist/upgrade/Nearby-Drop-2.5.0-upgrade-rc.dmg`
- `dist/upgrade/Nearby-Drop-2.5.0-upgrade-rc-universal.zip`
- `dist/upgrade/SHA256SUMS.txt` and `RELEASE-CANDIDATE.txt`
- `docs/upgrade/site-preview.html`, `screenshots/`, HELP.md and GROWTH-AND-LAUNCH.md

These archives are private validation builds. They were not installed over the public stable app or uploaded anywhere.
