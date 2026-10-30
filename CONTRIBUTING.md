# Contributing & Support

Nearby Drop is created and maintained by **[Arslan Basharat](https://github.com/arslanbasharat-o-o)**. Bug reports and feature suggestions are welcome.

## Feedback and Issue Reports
Reproducible bug reports and feature requests are welcome via [GitHub Issues](https://github.com/arslanbasharat-o-o/NearByDrop/issues). Please provide:
- Nearby Drop client version and build
- macOS version and hardware architecture (Apple silicon / Intel)
- Connected Android device model and OS version
- Connection environment (Wi-Fi, phone hotspot, or USB)

Never include personal files, credentials, or live pairing PINs in public issue reports.

## Code Contributions
Nearby Drop is proprietary software. Please open an issue before preparing a code change; the project license does not automatically grant permission to submit or merge modifications. Code contributions need prior written permission from the copyright holder.

Before submitting a pull request:
1. **Discuss major changes**: Open an issue first to discuss new features or substantial architecture changes.
2. **Focused pull requests**: Keep changes focused on a single fix or enhancement.
3. **Build and test**: Verify that the project builds cleanly and all automated tests pass:
   ```sh
   # Universal Release Build
   xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
     -configuration Release -derivedDataPath build \
     CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build

   # Run Automated Test Suite
   xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
     -configuration Debug -destination 'platform=macOS' \
     -derivedDataPath build-tests CODE_SIGNING_ALLOWED=NO test
   ```
4. **Code style & safety**: Match existing Swift conventions, preserve third-party attributions and licenses, and add regression tests for protocol, security, or lifecycle modifications.
5. **License**: Do not assume a public pull request grants permission to use your code. Written permission is required before code can be merged.

## Commit Messages
Use plain, friendly English. Five words is ideal; ten is the limit. Say what changed, add a small joke or user-friendly nudge when it fits, and skip long bodies.

- Keep QR codes on speaking terms
- Make file sending less dramatic
- Smooth out the settings panel

## Release Notes

- Title releases `Nearby Drop vX.Y.Z`.
- Use one short summary and at most three brief bullets. Keep it friendly and easy to scan; a small joke or useful user prompt is welcome when the change stays clear. Keep compatibility, signing, installation, and update details accurate.
- Preserve published tags and download assets. Never rewrite shared history or push to GitHub without the user's approval.
