# PR 1 — Trusted Device Security Hardening

## Root cause and attack preconditions

Before this change, `InboundNearbyConnection.processConnectionRequestFrame` copied the peer display name and endpoint ID from the incoming Quick Share connection request. `NearbyConnectionManager.isTrusted` accepted either a composite `name#endpointID` entry or a bare display name. `AppDelegate.obtainUserConsent` automatically approved peers matching either preference.

An attacker on a reachable local network could present a previously trusted display name. A composite entry was also not a secure identity binding: the endpoint ID came from peer-supplied protocol metadata and was not authenticated as a persistent device identifier. Completing a fresh encrypted session did not prove the peer was the previously trusted device.

## Identity and authentication model discovered

- The display name and endpoint ID arrive in the peer's connection request metadata. The name is sender-provided; the endpoint ID is sender-provided and can change between sessions.
- UKEY2 derives session keys and protects the session. The exchanged ephemeral key does not bind the connection to a persistent, previously authorized device identity.
- A scanned Quick Share QR code contains a P-256 public key. `processPairedKeyEncryptionFrame` verifies the sender's proof against the current UKEY2 authentication key and rejects a mismatch. This proves the current pairing session matches the scanned code; the app does not establish a durable authorization binding for later sessions.
- `trustedDevices` was a `UserDefaults` string array containing bare names and composite name/endpoint strings. Neither representation can authorize a peer securely.

The pre-change consent path was: connection-request metadata → UKEY2 session setup → optional QR proof check → transfer introduction → app-side trust lookup → automatic acceptance or approval card. The trust lookup was the unsafe decision point; UKEY2 encryption alone did not repair it.

## Security policy selected

No stable, previously authorized authenticated peer identity is available in the current Quick Share interoperability path. The app now requires explicit user approval for every incoming transfer, including transfers whose QR proof succeeds. QR proof verification remains in place and still rejects an incorrect key before a transfer reaches consent.

No protocol handshake or wire format changed. UKEY2 encryption, QR authentication, and manual approval/rejection remain supported.

## Changes made

- `NearbyShare/InboundNearbyConnection.swift`: every valid introduction now goes through `requestUserConsent`; no trust-based path exists in the protocol handler. Reduced logs that included peer metadata, handshake bytes, hashes, or error details.
- `NearbyShare/NearbyConnectionManager.swift`: removed display-name/composite trust matching and persistence helpers. Added idempotent invalidation of the legacy `trustedDevices` preference.
- `NearByDrop/AppDelegate.swift`: runs legacy preference invalidation at launch. Removed trusted-device and QR-session auto-approval. QR-authenticated transfers now show the normal approval card; decline clears the row, progress, accepted marker, and QR state.
- `NearByDrop/TransferWindow.swift` and `NearByDrop/SettingsView.swift`: removed trust storage/actions and replaced the trust list with an explanation that automatic acceptance is unavailable and each transfer needs approval.
- `NearByDrop/AppSupport.swift`: added the presentation-state transition used by the app to clear pending/accepted state on decline and completion.
- `Tests/NearbyShareSafetyTests.swift`: added protocol-loopback, migration, and consent-state regressions.

## Migration and disabled behavior

On every app launch, the old `trustedDevices` key is removed. Repeating this is safe and also clears entries restored after an older-version rollback. No saved entry is migrated because none can be cryptographically verified. The app no longer creates trusted-device entries, and no incoming transfer auto-accepts based on a name, endpoint ID, composite string, or QR session alone.

## Regression tests

The local protocol harness covers a matching legacy name, a stale endpoint ID, an exact composite entry from an unverified sender, the normal manual-approval flow, rejection without writing files, successful explicit approval, successful QR authentication followed by manual approval, and wrong-key QR rejection before consent. Separate tests cover repeated legacy preference invalidation and UI presentation-state cleanup after decline/completion. Existing encrypted loopback and QR tests remain in the suite.

## Validation results

- Full XCTest suite: **PASS — 37 passed, 0 failed, 0 skipped** on arm64 macOS 27.2.
- Debug build: **PASS**.
- Universal Release build: **PASS**; verified slices are `arm64` and `x86_64`.
- Xcode Analyze: **PASS**.
- Strict-concurrency Debug build (`SWIFT_STRICT_CONCURRENCY=complete`): **PASS**. Existing warnings remain in asynchronous callback/global-state code and generated protobuf sources; no warning was emitted for the consent-state helper or main-queue URL-opening helper.
- Tests use local loopback/protocol mocks only. No real-device or public-network attack was attempted.

## Compatibility, remaining risks, and manual verification

Quick Share wire compatibility is unchanged. The visible behavior change is that previously trusted senders and QR-scanned senders now require approval for each transfer. Automatic acceptance stays unavailable until the app can verify a persistent identity that is cryptographically bound to the authenticated session.

**NOT RUN:** manual Android and Windows device verification. On supported hardware, verify that normal incoming transfers show approval, approval receives files, decline leaves no received files and resets the UI, a valid QR session still connects and requests approval, and an incorrect QR key is rejected. The automated protocol harness covers the corresponding local flows.

## Source control and diff summary

- Branch: `fix/trusted-device-identity`, created from baseline `b930be3705632465dcb144d28ae2798767f734d3`.
- Changed source/test files: 7; 348 insertions and 219 deletions.
- Commit SHA: provided in the final review handoff.
- No push, merge, release, deployment, or GitHub issue changes were made.
- The pre-existing untracked `audit-output/NEARBYDROP_MASTER_AUDIT.md` was preserved.

## Independent final security review

The complete uncommitted branch diff was reviewed against `main` at `b930be3705632465dcb144d28ae2798767f734d3`. The authenticated CodeRabbit CLI completed a review with `--base main --uncommitted`; it reviewed all seven changed source/test files and reported **0 findings**.

### Additional regressions fixed

- The inbound setup handler accepted repeated paired-key and introduction frames without checking protocol state. A second introduction could replace a pending consent card's metadata and produce a second consent callback. The handler now requires the expected frame type and exact preceding state, so each connection can process one introduction only.
- `textPayloadID` defaulted to `0`, allowing an early URL payload with ID `0` to reach the URL-opening branch before any introduction or approval. It is now unset until URL metadata arrives, and opening a URL requires `.receivingFiles` after approval. The open operation is dispatched to the main queue.
- File chunks are now rejected unless the inbound state is `.receivingFiles`. This blocks all pre-approval file chunks, including zero-byte end markers that previously could be acknowledged and remove pending metadata despite not writing file bytes.

### Consent and concurrency coverage

The encrypted loopback tests use the production `InboundNearbyConnection` handshake, QR verification, introduction processing, consent callback, and file writer. The test delegate stands in for the UI and explicitly accepts or declines. Consent presentation state transitions are separately covered through the helper called by `AppDelegate`; the test target does not instantiate `AppDelegate` or run SwiftUI UI automation. Source inspection confirmed that production acceptance is routed through `NearbyConnectionManager.submitUserConsent`, which is guarded by inbound connection state and serialized on the connection queue.

The strict-concurrency build passes in Swift 5 mode with existing warnings for non-Sendable callback captures, shared mutable manager state, and generated protobuf storage. The new consent-state helper only mutates caller-owned values synchronously; the URL-opening helper schedules AppKit work on the main queue. No new warning was reported for either helper.

### Final-review limitations

- No physical Android or Windows peer was available for interoperability testing.
- The tests verify the production inbound protocol/session and writer but do not automate the SwiftUI consent card or instantiate the production `AppDelegate` routing layer.
- CodeRabbit completed against `main`; its first follow-up connection closed, and a retry completed successfully with zero findings.
