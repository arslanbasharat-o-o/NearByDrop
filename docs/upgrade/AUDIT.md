# Upgrade audit — November 22, 2026

Baseline: `e413fc6` on `codex/tropical-upgrade`; this captures the previous private theme work and supplied brief. Public installation remains v2.4.0. No remote writes or publication are authorized.

## Existing behavior and ownership

- AppDelegate hosts the popover, incoming approvals, notifications and screenshot fixtures. TransferWindow owns file selections, outgoing attempt lifecycle, retry safety, QR workflows and local history.
- NearbyShare implements encrypted sessions, protocol validation, local discovery, source identities, destination safety and explicit consent. Generated Protobuf and bundled libmtp/libusb remain upstream artifacts; no protocol rewrite is planned.
- USBModel serializes MTP work and supports browsing, breadcrumbs, multiple selection, uploads, recursive downloads, cancellation and partial-result messages. The native bridge validates names/paths and closes descriptors; recursive downloads cap depth and repeated folder IDs.
- Settings and onboarding gate legacy diagnostics acknowledgment. UsageAnalytics has a bounded durable queue, event UUIDs, seven-day expiration, opt-out purge and retry. Its server accepts three legacy event types.
- Sparkle gates installation during active operations. Packaging verifies both architectures and nested signatures. Existing release workflows separate private CI artifacts and signed public updates.

## Findings, decisions and regression risks

| Area | Evidence / gap | Implementation decision |
| --- | --- | --- |
| Themes | Vice-only palette checks are scattered; native window fills and semantic state colors remain outside it | Central theme tokens, original theme artwork and shared surface modifiers; all six appearances retained |
| Accessibility | Buttons animate regardless of Reduce Motion; theme previews are a single horizontal row | Respect motion/contrast, keyboard focus and hover; adaptive preview grid |
| Discovery | No integrated troubleshooting; a discovered computer is labelled Windows without OS evidence | Connection Doctor reports only local observations; label computers generically |
| Favorites | No favorites store; device-name trust is deliberately invalidated | Persist advertised-name/type hints locally; never use favorites as authentication or consent |
| Sharing | Files supported; no explicit text or screenshot composer | Label UTF-8 file fallback honestly; explicit screenshot permission/capture/preview only |
| USB | No current-folder search/sort; closing the bridge on error leaves a stale connected label | Filter the loaded listing only; deterministic folders-first sorting; reset disconnected model state |
| Large batches | 128-file protocol selection cap and revalidation are protective; one outgoing attempt is serialized | Build/test a bounded planner; keep execution experimental/disabled until multi-session approval and source-lifetime tests on real receivers |
| Onboarding | Three mostly illustrative steps; privacy and camera are crowded into one | Seven purposeful steps; revisit/skip/back; final explicit acknowledgment preserves opt-out |
| Analytics | No attempt denominator, USB outcomes or operational lifecycle; exact advertised names in v1 | Versioned name-free v2, separate consent plus build-time disabled rollout gate; preserve v1 compatibility |
| Collector | Cleanup heuristics delete distinct events sharing installation/name/type/hour | Remove lossy cleanup; UUID idempotency and retention only; never run old heuristic migration in the upgrade |
| Dashboard | Legacy counts only; no filters, outcomes, coverage or delivery health | Add authenticated operational views with explicit cohorts/pending/unknown and legacy separation |
| Distribution | `security find-identity -v -p codesigning` returns zero valid identities | Local ad hoc RC possible; Developer ID/notarization/stapling explicitly credential-blocked |
| Hardware | Prior specific device checks exist; no phone/Windows/Intel hardware attached for this run | Automated encrypted loopback tests and both-architecture builds; document unperformed physical checks |

The baseline test run, new phase checks and release evidence are recorded in CHECKLIST.md and the final verification report. The installed stable app and production diagnostics are left intact.
