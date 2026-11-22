# Unreleased

# 2.5.0 (26)

- Add Vice Nights, Coastal Sunrise and Midnight Route appearances, with readable navigation and shared controls.
- Add Connection Doctor, favorite-recipient hints and a seven-step setup guide.
- Prepare text and links as UTF-8 files, and preview screenshots before choosing a recipient.
- Filter and sort the current USB folder, improve breadcrumbs and recover stale connection state.
- Add job/attempt diagnostics for failures, retries, USB outcomes and coarse timing/error categories.
- Send diagnostics automatically after the setup disclosure; remove reporting switches and simplify General Settings.
- Keep local report preview/export under More and Help; never automatically upload the local report.
- Keep the 128-file wireless limit; large-batch execution remains disabled.
- Retain the existing Sparkle update key and transfer safety checks. macOS 14+, Apple silicon and Intel binaries.
- Distribution remains ad hoc signed; Developer ID notarization is not available.

# 2.4.0 (20)

- Require approval for every incoming transfer, including valid QR pairings.
- Exclude symbolic links and reject files changed during outbound reads.
- Enforce the 128-file limit and open source files only while sending.
- Verify installer checksums and preserve the existing app on failed upgrades.
- Retry failed outgoing transfers as new attempts after rechecking selected sources.
- Pause incoming visibility while preserving outgoing discovery and approved transfers.
- Preview and export allowlisted diagnostics locally without uploading the report.
- Preflight incoming disk space and report capacity failures to the sender.
- Recover stale USB sessions after transfer errors and preserve readable local uploads.
- Improve VoiceOver labels for transfer status, USB actions, and completion states.
- Commit received files atomically and clean abandoned partial files on launch.
- Add actionable completion and failure notifications for background transfers.

# 2.3.5 (19)

- Add first-party diagnostics with a reviewable choice in onboarding and Settings.
- Document report fields, including device names, and make reporting optional.
- Queue reports for up to seven days with a 200-event limit; expire server data after 90 days.
- Preserve local-only transfer behavior and exclude filenames, paths, contents, history, and peer identifiers from reports.
- Distribute a universal macOS 14+ build with ad hoc signing; notarization remains unavailable.

# 2.3.4 (18)

- Polish the menu-bar experience with clearer settings, transfer, QR, and USB surfaces.
- Smooth onboarding and keep update actions inside the app.

# 2.3.3 (17)

- Add automatic background update checks and an update indicator in the menu bar.
- Install signed updates and restart directly from the menu dropdown or About page.
- Verify signed feeds and archives before extraction using Sparkle.
- Defer installation while a transfer is active and report download or installation errors in the app.
- Generate a signed appcast with every packaged release.

# 2.3.2 (16)

- Fix Android-generated QR receiving with the receiver authentication proof, version 1 QR advertisements, and a fresh discovery identity for each scan.
- Preserve early connection responses until key exchange completes.
- Keep the camera scanner open when clicking outside the menu dropdown.
- Verify Pixel 8 Pro QR receiving on real hardware and add discovery and handshake regression coverage.

# 2.3.1 (15)

- Preserve binary endpoint information in connection request frames to ensure compatibility with Windows and Android senders.
- Add sequential chunk numbering and distinct attachment IDs for outgoing file transfers.
- Implement payload acknowledgement tracking and safe-disconnect handshake for reliable transfer completion.
- Update app branding, packaging scripts, and privacy permission descriptions to "Nearby Drop".
- Add comprehensive protocol regression tests for binary endpoint decoding, chunk indexing, and safe disconnect.

# 2.3.0 (14)

- Keep Send, Receive, Transfers, and USB in the menu bar dropdown, with an inline camera for QR scanning.
- Fix signed public-key encoding in the Quick Share handshake so Android does not reject valid keys intermittently.
- Allow retrying the same QR code after validation or connection errors; validate QR hosts and pairing keys strictly.
- Refresh local discovery when the network changes, including switches between Wi-Fi networks.
- Send an explicit TCP write-close when finishing a transfer.
- Correct repository/update links and author attribution; set macOS 14 as the supported minimum.
- Package a universal app for Apple silicon and Intel, with automated build, test, and analysis checks.

# 2.2.3 (13)

- Keep transfer requests and results inside the menu bar dropdown; remove system notification permission prompts and the separate notification-preview window.
- Ignore failed discovery probes in transfer UI and track trusted transfers through the same progress/completion path.
- Fix a camera scanner shutdown crash caused by retaining the scanner during deallocation.
- Preserve QR pairing across unrelated connection closures; cancel an active QR transfer correctly.
- Release canceled sockets and reject late callbacks from replaced outgoing connections.
- Keep multi-file progress cumulative and each incoming transfer’s progress separate.
- Throttle progress rendering and remove per-chunk debug logging from the send path.
- Preserve USB connections on refresh; clear stale storage state on disconnect/reconnect.
- Save received USB folders to new, sanitized destinations without merging into existing folders or following existing symlinks.
- Present folder and file dialogs on the interaction display or as a sheet on the initiating settings window.
- Show the bundle’s version/build, release notes, and a manual update check in About.
- Add encrypted and QR-authenticated loopback tests, cancellation cleanup tests, and safety checks to CI.
