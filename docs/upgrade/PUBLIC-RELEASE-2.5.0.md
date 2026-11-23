# Public release 2.5.0

Verified November 23, 2026 (Asia/Karachi).

Nearby Drop 2.5.0, build 26, is published as a stable release:
https://github.com/arslanbasharat-o-o/NearByDrop/releases/tag/v2.5.0

## Release checks

- Local XCTest: 80 tests, zero failures.
- GitHub Apple silicon and Intel jobs: tests, diagnostics checks, theme checks, installer checks and static analysis passed.
- Backend and workflow security jobs passed; universal packaging passed.
- Site audit, types, tests, generated assets and SEO checks passed after regenerating the stylesheet.
- Intel's Swift compiler initially timed out on the sunset artwork expression. The same drawing was split into a typed renderer; both platform jobs then passed.
- Protected signing workflow succeeded using the existing Sparkle key. No signing key was rotated or generated.
- Downloaded public ZIP passed SHA-256 and Ed25519 verification against the original public key trusted by 2.4.0.
- Published appcast signature, enclosure length/URL and version/build passed verification. The latest-release endpoint serves 2.5.0.
- App and share extension both report 2.5.0/build 26; deep/strict signature validation passed.

Preflight: https://github.com/arslanbasharat-o-o/NearByDrop/actions/runs/45025786008
Site checks: https://github.com/arslanbasharat-o-o/NearByDrop/actions/runs/45024994589
Signed release: https://github.com/arslanbasharat-o-o/NearByDrop/actions/runs/45027528457

## Update test

The local RC was replaced with the verified public 2.4.0/build 20 bundle, preserving preferences, history and files. The owner then confirmed updating and requested keeping the new version. The installed app was independently observed as 2.5.0/build 26. The older bundles remain in local rollback archives.

A native history entry showed a completed 35-byte text send to the owner's Pixel 8 Pro during readiness checks; the operational backend received its start and completion reports. Phone-side content hashing, Windows transfers and physical MTP transfers were not repeated. Native screen capture reported unavailable permission on this Mac; actual display capture was not verified.

Distribution remains ad hoc signed, not Developer ID signed or Apple-notarized. The owner chose to defer paid Developer Program enrollment. Sparkle feed/archive signing is separate and was verified successfully.
