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
