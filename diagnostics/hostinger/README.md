# Nearby Drop diagnostics dashboard

This is a first-party PHP/MySQL event receiver and password-protected dashboard intended for regular Hostinger web hosting. It is separate from the GitHub Pages website.

## What it records

- One `first_launch` event per app installation, plus `app_opened` on app launches.
- App version, Mac hardware model identifier, macOS major/minor version, current Mac display name, UTC timestamp, and a random installation ID.
- `transfer_completed` only after a successful wireless transfer, with direction and the peer's advertised name and broad type (`phone`, `tablet`, `computer`, or `unknown`).
- No file names, file contents, local file paths, transfer history, or peer IDs.

The protocol exposes a peer's advertised name and broad device type. It does not expose the phone model or Android version, so those fields are not guessed or collected. A Mac name or peer name can identify someone.

## Hostinger setup

1. Create a MySQL database in Hostinger and import `schema.sql`.
2. Copy `config.example.php` to `nearbydrop-diagnostics-config.php` in the directory above `public_html`. Set the database name and user; leave the password and dashboard fields empty. Keep this file outside `public_html` and out of Git.
3. Upload the contents of `public/` into a dedicated HTTPS site's `public_html` directory. The dashboard is `/`; the app endpoint is `/ingest.php`.
4. Issue the owner a single-use setup link. It expires after 48 hours and remains usable if the form is reopened or a database password is mistyped. The setup page verifies the MySQL connection, stores the database password in the private config, and saves a dashboard password hash.
5. The owner chooses the dashboard username and password on that setup page. After setup, the link is consumed and the owner lands directly on the dashboard.
6. Set `DiagnosticEventsEndpoint` in the app's `Info.plist` to the full HTTPS endpoint URL before building the release that should report.

The native app uses no embedded server secret. Its random installation ID is for counting installations, not authentication. The receiver validates event types and field sizes, de-duplicates retries by event ID, and uses prepared SQL statements. The event table has no IP-address column; Hostinger may keep separate server access logs under its own policies. Keep this endpoint on HTTPS and restrict server/database access to the project owner.

## Interpreting counts

`Reported installs` counts installations that have successfully reported their first app launch. `Active installs, 30 days` counts distinct installation IDs with an app-open event in the last 30 days; it does not claim the app is running right now. Reinstalling after removing the app's local preferences can create a new installation ID. A user identity, phone model, or Android version is not available from the app's protocol. Reports are retained for 90 days. Ingestion and authenticated dashboard access purge older reports; run `cleanup.php` daily through cron as a backstop. Counts therefore cover retained events, not lifetime downloads. The app queues at most 200 reports for seven days, retries transient failures, and clears pending reports on opt-out. Ingestion is limited to 300 requests per minute per address bucket and 120 per installation bucket; login allows 10 attempts per 15 minutes. Rate-limit buckets retain only counters and expiry, not raw addresses. Hash bucket collisions can share limits.

## Upgrading an existing dashboard

Back up its PHP files outside `public_html` and back up MySQL before upgrading. Apply `migrations/002-mac-model.sql` once, then upload `common.php`, `ingest.php`, `index.php`, and `cleanup.php`; preserve the private configuration and existing dashboard login. Configure a daily PHP cron in hPanel targeting `domains/nearbydrop.runs-at.dev/public_html/cleanup.php`. The CLI cleanup must succeed; requesting `/cleanup.php` through HTTPS must return 404.

Run `bash diagnostics/hostinger/tests/local-smoke.sh` for setup, sign-in, ingestion, deduplication, timestamp validation, retention, and rate limits. On macOS, run `scripts/tests/diagnostics-client.sh` to compile the shipping client with isolated preferences and simulated HTTP responses. Those client checks exercise the disclosure gate, durable retry acknowledgement, Mac model payload, transfer events, and opt-out queue removal. Release builds still require a real launch and phone transfer against production.

Version 2.3.5 shows the diagnostics choice to existing installations before sending reports. Closing that window leaves reporting blocked; Get Started acknowledges the disclosure, respecting its reporting toggle. Reporting remains on by default as disclosed, and disabling it preserves the installation ID so later re-enabling does not inflate installation counts. That ID is not an account or a hardware identifier.
