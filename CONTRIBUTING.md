# Contributing & Support

Nearbydrop is created and maintained by **[Arslan Basharat](https://github.com/arslanbasharat-o-o)**. Contributions, bug reports, and feedback are welcome.

## Feedback and Issue Reports
Reproducible bug reports and feature requests are welcome via [GitHub Issues](https://github.com/arslanbasharat-o-o/NearByDrop/issues). Please provide:
- Nearbydrop client version and build
- macOS version and hardware architecture (Apple silicon / Intel)
- Connected Android device model and OS version
- Connection environment (Wi-Fi, phone hotspot, or USB)

Never include personal files, credentials, or live pairing PINs in public issue reports.

## Code Contributions
Pull requests and community contributions are welcome!

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
5. **Contributor agreement**: By submitting a pull request, you agree that your contributions may be included, distributed, and licensed under Nearbydrop's project terms.
