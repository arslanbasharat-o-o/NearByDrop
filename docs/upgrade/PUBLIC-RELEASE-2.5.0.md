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

## Post-push CI timing follow-up

A duplicate main-branch Intel run later failed in the mock diagnostics-client test, after the complete preflight had passed. The test changed its mock HTTP status while an earlier 503 response could still be in flight, then expected a retry within five seconds even though the client correctly backs off for 60 seconds.

The test now synchronizes on request completion before switching mock responses. A deliberately delayed mock response exercises the previously racy boundary. Both diagnostics client suites passed locally after the test-only change. The shipping client and published binary were not changed. Rosetta was unavailable for a local x86_64 follow-up; GitHub's subsequent run provides the Intel check.
