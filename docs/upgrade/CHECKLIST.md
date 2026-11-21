# Master implementation checklist

Scope: supplied MASTER-PROMPT.md. Branch: `codex/tropical-upgrade`. Production deployment, public publication and expanded live telemetry require separate authorization.

- [x] Recoverable baseline commit and code ownership/risk audit
- [x] Current baseline checks — 72 XCTest cases, PHP smoke and diagnostics client passed
- [ ] Phase 2: six appearances, centralized tokens, original artwork, all app-owned screens, accessibility and fixture previews
- [x] Phase 3: Connection Doctor, favorite hints, accurate device picker, seven-step revisitable onboarding
- [x] Phase 4: explicit text/link file fallback, user-triggered screenshot preview, USB listing filter/sort/recovery
- [x] Phase 4: tested bounded batch planner; document experimental execution limits
- [ ] Phase 5: versioned operational client, jobs/attempts, disabled rollout + separate consent, opt-out/retry tests
- [ ] Phase 5: compatible local PHP collector, migration, authenticated dashboard and accounting/health tests
- [ ] Phase 6: Debug tests, universal Release, packaging/signature/DMG validation, RC and credential/hardware limits
- [ ] Phase 7: truthful README/help/privacy, screenshot set, storyboard, release draft, researched alternatives and growth plan
- [ ] Final implementation report and acceptance matrix

## Authorization boundaries

- Installed public v2.4.0 is retained.
- Expanded production telemetry is not enabled. Client v2 requires an explicit build gate AND separate user consent.
- No live schema/configuration changes, publishing, external messages, or purchases.
- Physical device tests and Developer ID notarization require hardware/credentials; continue independent work.

## Product feature validation

Debug build and 78 XCTest cases passed (including six new policy tests). All three custom palettes pass text/state/button contrast checks; all six choices persist. ScreenCaptureKit compiles against the macOS 14 deployment target. Screen permission prompts/capture and physical phone transfers remain manual checks; full fixture/keyboard QA follows before packaging.
