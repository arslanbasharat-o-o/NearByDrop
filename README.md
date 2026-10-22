# Nearbydrop

[![Build](https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml/badge.svg)](https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml)

Move files between your Mac and Android without a cloud account. Nearbydrop brings Quick Share transfers, QR pairing, and Android USB storage into one macOS menu bar app.

Created by [Arslan Basharat](https://github.com/arslanbasharat-o-o).

## What it does

- Send and receive files and links over your local network using Quick Share.
- Scan a sender’s QR code with a camera preview inside the menu bar dropdown, or display a code for selected files.
- Browse Android storage and copy files over USB using MTP.
- Track transfers in the dropdown and send files from Finder’s Share menu.

Wireless transfers use the UKEY2 handshake and encrypted transport. File contents stay on the local network or USB cable. No Google account or cloud relay is required.

## Download

**macOS 14 Sonoma or newer · Apple silicon and Intel**

Download the universal ZIP from [Releases](https://github.com/arslanbasharat-o-o/NearByDrop/releases), extract it, and move **Nearby Drop.app** into Applications. The same download contains native `arm64` and `x86_64` code, including the share extension and USB libraries.

Current builds are **ad hoc signed and not notarized**. macOS may block the first launch. After attempting to open the app, use System Settings → Privacy & Security → Open Anyway if you trust this release. Do not disable Gatekeeper globally. SHA-256 checksums are provided with each release.

Settings → About shows the version and provides an update check. Updates are downloaded and installed manually.

## Use it

1. Connect the Mac and phone to the same local network. Allow local network access when macOS asks.
2. Open Nearbydrop from the menu bar. Use **Send** to choose files and a nearby device, or **Receive** to scan a sender’s Quick Share QR code.
3. Accept incoming requests in the dropdown. Compare the pairing code when prompted.

For USB, unlock the phone, select **File transfer / Android Auto** in its USB settings, then open the **USB** tab. Close other MTP apps if they are holding the connection.

## Network and device limits

- Wireless speed depends on the network. A slow 2.4 GHz router cannot deliver 40–50 MB/s. QR pairing uses the same network transport and does not increase its speed.
- A phone hotspot can carry transfers when local discovery works. LTE-only hotspot discovery remains an open device verification item; do not rely on that setup yet.
- Automatic Wi-Fi Direct and hotspot negotiation are not implemented. Both devices need a reachable local network; guest networks and client isolation can prevent discovery.
- The Mac advertises itself while the app runs. Google account/contact-restricted visibility and Bluetooth discovery are not supported.
- Physical QR interoperability, USB devices, and older macOS versions need broader testing. See [release verification](RELEASE-VERIFICATION.md) for the exact checks and limits.

## Build and test

Use Xcode 26 or newer with the macOS SDK. Swift packages are pinned in `Package.resolved`; USB libraries are vendored as universal dynamic libraries.

```sh
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
  -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build

xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build-tests CODE_SIGNING_ALLOWED=NO test
```

The app is written to `build/Build/Products/Release/Nearby Drop.app`. Use `scripts/package-release.sh` to package and verify an ad hoc signed universal build. Distribution with Apple notarization requires your own Developer ID certificate and notarization credentials.

Generated protocol files are checked in. If you change the `.proto` files, install `protobuf` and run `NearbyShare/GenerateProtobuf.sh`. Read [PROTOCOL.md](PROTOCOL.md) for the wire protocol.

## Privacy and security

Camera access is used for QR scanning. Transfer history and preferences are stored locally. System notification permission is not required. The update check contacts GitHub’s release API and does not send file contents.

A trusted device may skip the consent prompt. Device trust is a convenience based on local device identification, not Google account authentication; only enable it on networks and devices you trust. Scanning a QR code authorizes the sender whose signing key matches that code.

For a security concern, use [GitHub’s private vulnerability reporting](https://github.com/arslanbasharat-o-o/NearByDrop/security/advisories/new). For reproducible bugs, open an [issue](https://github.com/arslanbasharat-o-o/NearByDrop/issues/new). Remove personal file names, device identifiers, and pairing codes from logs before sharing them.

## Copyright and licenses

Nearbydrop is proprietary software created by **Arslan Basharat**.  
Copyright © 2026 Arslan Basharat. All rights reserved.

Unauthorized copying, distribution, modification, reverse engineering, decompilation, or commercial use of this software, in source code or binary form, without express prior written permission is strictly prohibited. See [LICENSE](LICENSE) for details.

### Third-party components

Dependencies include [SwiftECC](https://github.com/leif-ibsen/SwiftECC), [BigInt](https://github.com/leif-ibsen/BigInt), [ASN1](https://github.com/leif-ibsen/ASN1), [SwiftProtobuf](https://github.com/apple/swift-protobuf), [QRCode](https://github.com/dagronf/qrcode), [SwiftImageReadWrite](https://github.com/dagronf/SwiftImageReadWrite), and [swift-qrcode-generator](https://github.com/dagronf/swift-qrcode-generator). Their own licenses apply.

USB support dynamically links [libmtp](https://github.com/libmtp/libmtp) and [libusb](https://github.com/libusb/libusb) under LGPL 2.1 or later. License texts, exact source versions, and replacement instructions are in [Vendor/USB](Vendor/USB/README.md). Release archives include third-party notices and corresponding USB source archives.

Nearbydrop is an independent project and is not affiliated with Google or Apple. Quick Share and other product names belong to their respective owners.
