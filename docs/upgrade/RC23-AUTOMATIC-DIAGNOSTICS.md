# Build 23 — automatic diagnostics

November 22, 2026, Asia/Karachi. The owner explicitly requested diagnostic reporting by default with no user-facing off switch. This supersedes the opt-in policy in build 22; the public app release has not been published or updated.

## Implemented

Removed both reporting controls from General Settings and the reporting toggle from onboarding. Informational disclosures remain in both screens. Local diagnostic report preview/export remains available. Reporting is automatic after the setup disclosure in configured builds; previews and missing/invalid endpoints still do not transmit. Historical reporting preferences no longer gate the current candidate. Configured source builds enable the operational capability by default; deployment configuration can still stop server ingestion.

The event data contract is unchanged. Schema 2 contains coarse operational categories, versions and pseudonymous correlation IDs, with no advertised names, paths, contents or clipboard data. The existing legacy stream still includes advertised device names and the Mac model, as disclosed. No file contents or filenames were added. Retention remains 90 days; the local queue remains at most 200 reports for seven days, with stable IDs, acknowledgment and bounded retries.

Updated the local privacy page, README, help/analytics/release documentation and draft marketing copy to describe automatic reporting. Live dashboard wording was updated after backing up its PHP file; no schema or historical data changed. Public GitHub Pages/privacy-site publication was not performed.

## Verification

- Universal Release build passed; installed app/extension metadata is 2.5.0/build 23.
- All 80 XCTest cases passed with zero failures.
- Revised shipping-client tests passed for automatic delivery despite historical false preferences, setup disclosure, deployment capability, job/attempt correlation, payload allowlist, daily sampling, acknowledgment and durable retries.
- Packaging credential guards, workflow security, SHA-256 manifest, DMG integrity and deep/strict bundle signatures passed.
- Native Settings and onboarding were inspected in the installed candidate: automatic reporting is described and no diagnostic switches exist. Other unrelated settings switches remain.
- A genuine `client_health` event from the installed candidate was confirmed in the live operational database. The inspection printed only event counts, not the installation identifier or payload. No synthetic transfer success was inserted.

Installed app: `/Applications/Nearby Drop.app`. Build 22 rollback: `dist/rollback/Nearby-Drop-2.5.0-rc22.zip`.
Candidate: `dist/automatic-diagnostics-rc/Nearby-Drop-2.5.0-diagnostics-rc.dmg` and universal ZIP.

Physical device transfers were not repeated for this policy change. The candidate remains ad hoc signed, not notarized. Updated public-site policy copy is prepared locally for a future authorized publication.
