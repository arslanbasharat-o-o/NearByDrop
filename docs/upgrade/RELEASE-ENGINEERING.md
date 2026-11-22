# Release engineering and explicit gates

## Candidate vs public release

The installed local candidate is 2.5.0/build 23. Both `--release-candidate` and `--diagnostics-candidate` stage build 23, refuse production Sparkle secrets and generate no public appcast. The source reporting capability is enabled by default; reporting is automatic after the setup disclosure. Neither packaging mode publishes anything. Older installed bundles were backed up before replacement.

The normal source/release metadata remains the current public version until a separate approved release bump. Candidate metadata is applied only to a staged bundle before signing. The private candidate disables automatic update checks; a future approved public build retains the usual Sparkle flow.

## Credential evidence and remaining gates

`security find-identity -v -p codesigning` found **zero valid signing identities** on this Mac. Therefore the local RC is ad hoc signed. It is not Developer ID signed, notarized, stapled, or a public release. Building both architectures verifies binary slices, not execution on an Intel Mac. Physical Android/Windows/MTP checks remain documented manual gates.

After owner authorization and provision of a Developer ID Application identity in the macOS keychain, archive through Xcode using the intended team, Manual signing and Hardened Runtime; retain the app/extension entitlements and inspect all bundled helper/library signatures. Do not change the stable branch's release-signing restrictions or accept a PR-built artifact as a trusted release input.

`notarize-candidate.sh` accepts an already Developer ID signed, Hardened Runtime app and an existing notarytool keychain profile. It verifies signatures, submits via the keychain, requires an Accepted response, staples/validates, then creates a ZIP. It fails before contacting Apple for ad hoc candidates. This credential-dependent path cannot be executed or claimed successful here. Configure credentials interactively in the keychain; never put Apple passwords/private signing keys in chat, shell history, source, CI artifacts or logs.

Public Sparkle publication continues to use the existing protected tag/environment workflow and explicit signing secret. Update installation is deferred while wireless or USB operations are active. A public release requires explicit owner approval, final version bump, signed feed/archive, fresh hardware checks and review of any telemetry activation.

## Local verification commands

```sh
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop -configuration Debug -destination 'platform=macOS' -derivedDataPath build-upgrade CODE_SIGNING_ALLOWED=NO test
bash scripts/tests/theme-appearance.sh
bash scripts/tests/diagnostics-client.sh
bash scripts/tests/operational-client.sh
bash diagnostics/hostinger/tests/local-smoke.sh
bash diagnostics/hostinger/tests/operational-smoke.sh
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop -configuration Release -derivedDataPath build-upgrade CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build
bash scripts/package-release.sh build-upgrade dist/upgrade --release-candidate
```

Inspect the unpacked archive with deep/strict codesign validation; verify arm64 and x86_64 slices throughout, checksums, DMG integrity, privacy flag and release-candidate metadata. Preserve receiving pause choices and download/history data. Reporting in build 23 follows the new automatic policy instead of historical toggle preferences. Native open/save/permission dialogs stay under macOS control.

## Diagnostics candidate follow-up

`bash scripts/package-release.sh build-upgrade dist/automatic-diagnostics-rc --diagnostics-candidate` stages build 23 with automatic diagnostics after the setup disclosure. This mode refuses production Sparkle secrets and generates no public appcast. See RC23-AUTOMATIC-DIAGNOSTICS.md for the policy change, installed-app check and actual server receipt.
