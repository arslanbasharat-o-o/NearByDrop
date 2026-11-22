# Unified diagnostics dashboard

November 22, 2026. Deployed to https://nearbydrop.runs-at.dev/.

The site now has one dashboard implementation, shared by the root URL and existing operations.php bookmarks. Authentication, CSRF protection, private configuration, collection endpoints and stored event schemas are preserved.

## Interface

- Clear overview of reporting installations, app opens, successful basic transfers and detailed transfer success.
- One set of UTC date/version filters, with method filtering scoped to detailed reports.
- Sections for transfer results, error/timing categories, recent detailed reports, reporting Macs, paginated basic transfer history and collector health.
- Short labels and expandable counting definitions instead of long technical paragraphs.
- Desktop sidebar, compact mobile navigation, visible focus, readable tables with contained horizontal scrolling and labeled empty/error states.
- Basic and detailed counts remain separate where combining them would double-count activity.
- Health-only reports do not enter transfer charts or success calculations.
- Old records remain accessible by dates. Report pagination has no arbitrary 100-record history cutoff; identical-looking transfers with distinct event IDs remain visible. Reporting Macs shows the latest report from up to 100 installations. Summary charts cap at 50,000 detailed reports and disclose truncation; individual report pages remain available.

## Record protection

Before deployment, public files, private configuration and a compressed SQL database dump were saved outside public_html at /home/u265637618/nearbydrop-dashboard-redesign-20261122/.

A private event manifest recorded a SHA-256 hash of every pre-existing event row. After deployment, all **221 basic events and 1 detailed event** were verified present with identical hashes. No migrations or cleanup were executed during deployment. Dashboard rendering performs only reads; it no longer invokes retention cleanup. Existing ingestion/CLI retention policy is unchanged.

The new view displays all 57 basic completed transfers across two pages. The old view used DISTINCT on visible fields, which hid some distinct records without deleting them. The new history displays each event separately.

## Verification

- Legacy setup/login/collector and operational migration/accounting/HTTP suites passed.
- Added regression coverage for read-only page views, browsing records older than the retention window, safe rendering of device labels, duplicate-looking history rows and pagination.
- PHP lint passed locally and on the host.
- Authenticated desktop and 390px mobile UI checked on the live site. No page-level horizontal overflow; filter controls remained within the viewport.
- Live method filtering preserved the 28 reporting installations and 57 basic completed transfers; the second history page displayed the remaining seven transfers.
- Original dashboard credentials and collection configuration remain intact. No synthetic production events were added.

Local review images: build-upgrade/dashboard/desktop.jpg and mobile.jpg. They contain real dashboard totals and are intentionally outside Git. The app itself was not modified by this website update.
