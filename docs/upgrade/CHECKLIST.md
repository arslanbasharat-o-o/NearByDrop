# Master implementation checklist

Scope: supplied MASTER-PROMPT.md. Branch: `codex/tropical-upgrade`. Public app publication requires separate authorization. The subsequent diagnostics deployment was requested by the owner; see RC22-FOLLOWUP.md.

- [x] Recoverable baseline commit and code ownership/risk audit
- [x] Current baseline checks — 72 XCTest cases, PHP smoke and diagnostics client passed
- [x] Phase 2: six appearances, centralized tokens, original artwork, all app-owned screens, accessibility and fixture previews
- [x] Phase 3: Connection Doctor, favorite hints, accurate device picker, seven-step revisitable onboarding
- [x] Phase 4: explicit text/link file fallback, user-triggered screenshot preview, USB listing filter/sort/recovery
- [x] Phase 4: tested bounded batch planner; document experimental execution limits
- [x] Phase 5: versioned operational client, jobs/attempts, disabled rollout + separate consent, opt-out/retry tests
- [x] Phase 5: compatible local PHP collector, migration, authenticated dashboard and accounting/health tests
- [x] Phase 6: Debug tests, universal Release, packaging/signature/DMG validation, RC and credential/hardware limits
- [x] Phase 7: truthful README/help/privacy, screenshot set, storyboard, release draft, researched alternatives and growth plan
- [x] Final implementation report and acceptance matrix — see VERIFICATION.md; external release gates remain open

## Authorization boundaries

- Installed app is now diagnostics RC build 22; public v2.4.0 and RC build 21 rollback archives are retained.
- Operational server ingestion is enabled following the owner request. Client v2 still requires the explicit candidate build gate AND separate user consent.
- The authorized additive schema/configuration update is complete. No public app publication, external messages or purchases occurred.
- Physical device tests and Developer ID notarization require hardware/credentials; continue independent work.

## Product feature validation

Debug build and 80 XCTest cases passed. All three custom palettes pass text/state/button contrast checks; all six choices persist. ScreenCaptureKit compiles against the macOS 14 deployment target. Screen permission prompts/capture and physical phone transfers remain manual checks; 192 fixture images and native theme/privacy/keyboard interaction checks are complete. Full assistive-technology and physical-device checks remain open.

## Diagnostics validation

80 XCTest cases passed. Operational client tests passed for both gates, separate consent, privacy fields, correlated retries, HTTP acknowledgment and opt-out purge. Legacy collector/client regressions passed. Local SQLite migration replay, HTTP ingestion, dashboard authentication/filters, shuffled outcome accounting, conflicting terminals, missing-start coverage and name/content rejection passed. Live collection remains disabled and no production backend was modified. MySQL validation is tracked separately before deployment.

## Follow-up: build 22

- [x] Reproduce and fix actual installed Vice Nights tab contrast; verify native app.
- [x] Add light/dark-host navigation contrast regression checks.
- [x] Test MySQL using temporary tables, back up production, apply additive migration twice and deploy operational dashboard/collector.
- [x] Package/install build 22 with visible separate opt-in; verify it remains off by default.
- [x] Rerun 80 tests, universal Release, client/backend and package/security checks.
