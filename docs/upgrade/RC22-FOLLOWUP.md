# Build 22: readable navigation and live operational diagnostics

November 22, 2026, Asia/Karachi. The owner reported unreadable Vice Nights tabs and requested the diagnostics system be updated. This follow-up supersedes build 21's historical deployment/installation status.

## Theme correction

The actual installed app reproduced near-black unselected Receive/Transfers/USB labels on the dark custom background. The prior fixture renderer explicitly forced the color scheme and hid this hosting mismatch. Navigation used dynamic system text colors while custom surfaces used fixed dark colors.

Menu navigation and settings selectors now use shared palette text tokens. The shared window modifier propagates the chosen color scheme to SwiftUI/native controls, and Settings uses that modifier too. A regression checks selected/unselected custom navigation text against the actual palette under both Aqua and Dark Aqua. All three custom themes pass; System/Light/Dark remain available.

The installed Release candidate was visually checked through native UI: Send, Receive, Transfers and USB are readable in Vice Nights; dark Settings labels and the operational opt-in are readable. The optional operational control was observed **off**. No user's reporting consent was changed.

## Diagnostics deployed

The existing live host had only legacy `diagnostic_events` and no operational collector/dashboard. Deployment used the existing SSH access without accessing hPanel.

Before writes, connection-local MySQL temporary tables tested migration DDL replay/indexes, ingestion inserts, UUID deduplication, retry accounting, filters, health upserts and retention. They shadowed table names and changed no persistent rows. PHP accounting tests also passed on the host. This is MySQL validation evidence, not a separately provisioned staging database or a live HTTP receipt test.

A private backup captured website files, configuration and a compressed SQL database dump at:
`/home/u265637618/nearbydrop-upgrade-20261122/backup/20261122T045320Z`.

Migration 004 was applied and replayed successfully. Updated PHP files were linted and replaced by file rename; dashboard credentials were preserved. The server operational gate was enabled. Canonical app source keeps the gate false; the explicitly packaged diagnostics candidate stages it true, still requiring separate user consent. No public app feed/release was published.

Verified over HTTPS:
- Malformed operational event rejected with 422.
- Unauthenticated operational dashboard rejected with 401.
- Authenticated dashboard renders coverage, reliability, errors, OS/version, direction, payload/count categories, connection/approval timings, queue depth and collector health without database errors.

No synthetic successful transfer was inserted into production. The full valid HTTP acknowledgment/dedup path passed against disposable local fixtures. Actual user event delivery begins after an installation opts in. Old public clients cannot supply historical failure/attempt data retroactively; legacy and schema 2 totals overlap and must remain separate.

## Build and test evidence

- 80 XCTest cases passed, zero failures.
- Universal Release build succeeded; installed app and extension are 2.5.0/build 22.
- Theme persistence/navigation contrast, operational client gates/consent/delivery/opt-out, both PHP smoke suites, MySQL temporary-table tests, packaging guards and workflow security checks passed.
- ZIP/DMG SHA-256 checks, DMG integrity and deep/strict installed signature verification passed.
- Candidate remains ad hoc signed and not notarized. Physical device transfer tests were not repeated for this correction.

Installed: `/Applications/Nearby Drop.app`.
Artifacts: `dist/diagnostics-rc/Nearby-Drop-2.5.0-diagnostics-rc.dmg` and its universal ZIP.
Prior RC rollback: `dist/rollback/Nearby-Drop-2.5.0-rc21.zip`. The earlier stable 2.4.0 rollback ZIP is also retained. Preferences, receiving state, history and download files were preserved.

## Rollback

Quit the app and restore the desired backed-up bundle to Applications, preserving preferences. To stop new operational ingestion, set the private server configuration's `operational_enabled` false. Restore the backed-up PHP/configuration if needed; leave additive tables intact rather than deleting data. Review and restore SQL only for a demonstrated data issue. Do not reapply historical migration 003's lossy name/hour deduplication.
