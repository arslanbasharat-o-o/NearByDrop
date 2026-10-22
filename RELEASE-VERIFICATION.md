# Release verification

Target: Nearby Drop 2.3.0 (14), universal `arm64` and `x86_64`, macOS 14+.

This is a community prerelease. Passing automated checks does not establish compatibility with every phone, router, USB device, or supported macOS version.

## Checks

| Check | Evidence / status |
| --- | --- |
| Secret scan | Git history and publication files scanned with Gitleaks. Only a documented public protocol salt and deterministic test public key were allowlisted. |
| Code review | Eight findings across two CodeRabbit reviews addressed, including: null interface address, frame processing after close, incoming/outgoing cancellation lifetime, private logging, trusted-device display, QR discovery across tabs, and update availability. |
| Universal build | Release build includes the app, Finder share extension, protocol library, libmtp, and libusb for both architectures. Packaging refuses a missing architecture. |
| Automated tests | 18 tests pass locally, plus 100 repeated transfer tests (20 iterations of five cases). Handshake encoding, malformed frames and payload ranges, encrypted files and empty files, QR validation/authentication, cancellation cleanup, scanner lifetime, progress, update responses, and safe USB destinations. |
| Static analysis | Local Xcode analysis passed. CI repeats it on both architectures. |
| Packaging | Strict code-signature verification; licenses embedded in the app; ZIP checksum published. Ad hoc signing only. |
| CI | Native Apple silicon and Intel jobs build/test/analyze before the universal packaging job. See the workflow run linked from the release. |

## Physical observations

- A Pixel 8 Pro transfer succeeded on the first attempt after the handshake encoding fix.
- The user reported roughly 50–60 MB/s with a working phone hotspot setup while the phone was connected to Wi-Fi. This is an observation, not a promised speed.
- The inline menu bar camera preview, cancel/reopen behavior, and tab changes were checked on the development Mac.

## Still required

- Reproduce and fix discovery when the phone uses LTE only and the Mac joins its hotspot. This setup currently fails for the user.
- Scan real Android Quick Share codes and complete transfers in both directions after the final changes. Synthetic QR decoding and encrypted QR loopback tests do not replace this check.
- Exercise USB browsing, upload, download, disconnect/reconnect, and cancellation on real Android hardware.
- Test physical Intel hardware and macOS 14/15. Architecture compilation and hosted CI cover part of this, not the full device experience.
- Obtain Developer ID signing and notarization before offering a standard notarized distribution.

## Dependencies

USB source assets correspond to libmtp 1.1.23 and libusb 1.0.30. Their archive SHA-256 values were checked against the package metadata:

```
74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed  libmtp-1.1.23.tar.gz
fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf  libusb-1.0.30.tar.bz2
```

Sources are unmodified; bundled libraries have relative Mach-O install names for loading inside the app. Their LGPL licenses and replacement instructions ship in the app’s ThirdPartyLicenses folder.
