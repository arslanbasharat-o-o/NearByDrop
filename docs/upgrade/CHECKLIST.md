# Master implementation checklist

Scope: supplied MASTER-PROMPT.md. Branch: `codex/tropical-upgrade`. Production deployment, public publication and expanded live telemetry require separate authorization.

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

- Installed public v2.4.0 is retained.
- Expanded production telemetry is not enabled. Client v2 requires an explicit build gate AND separate user consent.
- No live schema/configuration changes, publishing, external messages, or purchases.
- Physical device tests and Developer ID notarization require hardware/credentials; continue independent work.

## Product feature validation

Debug build and 80 XCTest cases passed. All three custom palettes pass text/state/button contrast checks; all six choices persist. ScreenCaptureKit compiles against the macOS 14 deployment target. Screen permission prompts/capture and physical phone transfers remain manual checks; 192 fixture images and native theme/privacy/keyboard interaction checks are complete. Full assistive-technology and physical-device checks remain open.

## Diagnostics validation

80 XCTest cases passed. Operational client tests passed for both gates, separate consent, privacy fields, correlated retries, HTTP acknowledgment and opt-out purge. Legacy collector/client regressions passed. Local SQLite migration replay, HTTP ingestion, dashboard authentication/filters, shuffled outcome accounting, conflicting terminals, missing-start coverage and name/content rejection passed. Live collection remains disabled and no production backend was modified. MySQL validation is tracked separately before deployment.
