# Nearby Drop device verification

Last reviewed: October 24, 2026.

These are hands-on checks on specific devices. They do not establish compatibility with every Android phone, Windows PC, or network.

## Passed checks

- **Quick Share over local Wi-Fi:** Mac-to-Android and Android-to-Mac file transfers passed with a Pixel 8 Pro.
- **Quick Share QR transfers:** Mac-generated QR sending and Android-generated QR receiving both passed with a Pixel 8 Pro. Android-to-Mac QR receiving was verified with the v2.3.2 Debug build.
- **Android USB MTP:** browsing, upload, and download passed with Pixel and Nexus devices. The test payload was transferred over MTP; ADB was used only to read back the phone-side hash.
- **Windows Quick Share:** sending to and receiving from Nearby Drop passed with one Windows PC in a Debug test build after protocol fixes.

The packaged v2.3.4 release includes these workflows, but it has not been separately device-tested for every listed setup. The Windows result covers one PC only.

## Not verified

- LTE-only phone-hotspot discovery; the mobile connection was unstable during testing.
- Other Android models, additional Windows PCs, and every router or network configuration.
- A maximum transfer speed. Speeds depend on the devices, network, cable, and storage.
