# Operational diagnostics — opt-in rollout

## Rollout boundaries

The canonical source Info.plist keeps `ExpandedDiagnosticsEnabled=false`. The explicitly packaged diagnostics RC, build 22, sets the staged flag to **true** so its separate opt-in is visible. Schema 2 additionally requires legacy reporting to remain enabled, onboarding/disclosure acknowledgment, and separately granted consent version 2. Settings shows the additional disclosure/toggle only in an explicitly enabled rollout build. There is no automatic upgrade consent. The PHP endpoint separately requires private config `operational_enabled === true`; its example remains false. Neither a migration nor uploading files enables collection by itself.

On November 22 the owner requested the diagnostics update. The live server was backed up, migration 004 was tested using isolated MySQL temporary tables and then applied twice successfully, the collector/dashboard were deployed, and the server gate enabled. This does not grant consent to any installation. The installed build 22 opt-in was verified off. See RC22-FOLLOWUP.md for deployment evidence and rollback.

## Data contract

`OperationalEvent` can encode only schema/event UUID, existing random installation UUID, app/macOS versions, broad computer category, ephemeral job/attempt UUIDs and attempt number, minute-rounded event/job timestamps, method/direction/outcome/stage, bucketed file counts/sizes/attempt duration/connection duration/approval duration, a fixed error category and queue-depth category. It has no name, path, clipboard, content, account, phone model, hardware identifier, IP or arbitrary-properties field.

Installation IDs are pseudonymous reporting hints, not fully anonymous identities or authenticated people. The public collector cannot prove events came from a real installation. Hosting access logs are separate from app event storage.

Wireless jobs start at an explicit send/preparation or incoming approval request. Retry preserves job ID and creates a new attempt. Terminal guards prevent duplicate callback outcomes. Incoming declines/cancellations are explicit. USB operation events begin after initial input validation and before MTP transfer work; folder sizes/counts may be unknown. UI/health events are sampled at most once per installation per day. This system is not native text/link payload interoperability validation.

The existing three-event v1 stream remains compatible and retains its existing disclosure. Do not add legacy and schema 2 transfer counts: coverage overlaps.

## Delivery and retention

The shared durable queue retains at most 200 events for seven days. Acknowledgment requires HTTP 202 plus `ok:true`. Permanent invalid-payload errors are dropped; transient failures back off exponentially from 60 seconds to at most one hour, honoring Retry-After within that bound. Stable event UUIDs survive delivery retries. Full opt-out cancels delivery and clears pending events. Operational-only opt-out cancels/requeues delivery safely, removes schema 2 reports, and preserves the legacy reporting choice.

The server validates enum/category/UUID/timestamp fields and rejects unknown fields, including names/content. It uses prepared SQL and event UUID idempotency. Installation IDs scope job correlation. Health counts accepted, duplicate, rejected, delayed and DB-visible error outcomes without request bodies/identifying strings. Both event systems and health counters retain 90 days; CLI cleanup handles optional operational tables even after rollout is disabled. Low-value sampling applies to UI/health, not transfer outcomes.

Old cleanup compared names/types/hour and could discard distinct reports. New code uses retention and UUID idempotency only. Deleted historical rows cannot be reconstructed. Migration 003 is historical and must not be reapplied as part of this upgrade.

## Safe migration and rollback

1. Back up the staging database and private configuration outside public_html.
2. Copy a staging-only config with a separate database. Leave `operational_enabled` false initially.
3. Run `php diagnostics/hostinger/migrations/apply-004.php /absolute/path/to/staging-config.php`. Replay is idempotent; it creates only additive tables/indexes. It does not alter the legacy table or credentials.
4. Run both PHP smoke suites and client gate/delivery checks. In disposable fixtures only, enable the server gate to test HTTP ingestion.
5. Review schema/consent text, artifacts, retention, old-client compatibility and outcome definitions with the owner. Production deployment was subsequently authorized and completed for the server; the client requires individual opt-in.
6. For rollback, disable the client rollout and server gate. Keep additive tables for retention/inspection; do not drop production data to roll back code. Restore legacy endpoint/dashboard files from the verified backup if needed.

SQLite migration replay and HTTP fixtures are automated. MySQL connection-local temporary-table checks subsequently passed on the host, followed by the backed-up additive production migration and authenticated dashboard verification. This was not a separate persistent staging database.

## Metric definitions and limits

Dashboard operational cohorts use job-start time; non-job events use occurrence time. Late events can revise an earlier cohort. The latest numbered attempt determines the job outcome, independent of receipt order. A terminal overrides its start; conflicting terminal outcomes become unknown. A start without a terminal is pending for 24 hours, then unknown rather than failed. Jobs missing all start events are displayed as missing coverage and excluded from the attempted-job denominator.

Observed success = completed / (completed + failed), excluding cancellations, declines, pending/unknown and missing-start jobs. This is an explicitly finalized cohort metric, not an unconditional all-user reliability claim. Version/method filters apply to schema 2; legacy cards are date-filtered only. UI/health sampling limits causal attribution. A later success is not proof troubleshooting caused it.

Activation cards are milestones observed in the selected range, not lifetime first-ever conversions. Returning means reports on two or more UTC days. Histograms count events, not distinct people/jobs; start-event durations are not throughput measurements. Results cap at 50,000 rows and visibly disclose truncation. Health uses receipt-day totals across methods/versions. A database outage can prevent writing its own error counter; queue reports cover only reporting clients, and silence alone is not outage proof.
