# Nearby Drop

[![Build](https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml/badge.svg)](https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/arslanbasharat-o-o/NearByDrop?color=blue)](https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Apple%20Silicon%20%26%20Intel-green.svg)](https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest)
[![Website](https://img.shields.io/badge/website-live-brightgreen)](https://arslanbasharat-o-o.github.io/NearByDrop/)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)

[**Website & Guides**](https://arslanbasharat-o-o.github.io/NearByDrop/) · [**Download DMG**](https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest) · [**Report Issue**](https://github.com/arslanbasharat-o-o/NearByDrop/issues) · [**Contributing**](CONTRIBUTING.md)

Nearby Drop is an independent macOS menu bar app for transferring files between a Mac and Android devices that support Quick Share (formerly Nearby Share). It includes wireless sending and receiving, an inline QR scanner, and a USB MTP file browser. It is free to download and distributed under a proprietary license.

Created and maintained by [Arslan Basharat](https://github.com/arslanbasharat-o-o).

## Key Features

- **Wireless Quick Share Transfers**: Send and receive photos, videos, archives, and links over a shared local network. Actual speed depends on the phone, Mac, signal, and network.
- **Inline QR Camera Pairing**: Scan an Android device's Quick Share QR code directly with a live camera preview in the menu bar dropdown, or display a QR code for selected Mac files.
- **Direct Android USB Storage (MTP)**: Built-in high-speed MTP file manager for browsing phone storage, downloading full directories, batch uploading, and Finder drag-and-drop over USB.
- **macOS Finder Share Menu**: Send files, folders, or web links directly to nearby Android phones from Finder via the native Share Extension.
- **Zero-Cloud Privacy**: Wirelessly encrypted with the UKEY2 handshake and AES-GCM cipher. Your file data stays strictly on your local Wi-Fi or USB connection — no Google account, Apple ID, or third-party servers required.
- **Universal Architecture**: Native performance on both Apple silicon (`arm64`) and Intel (`x86_64`) Macs running macOS 14 Sonoma or newer.

## Comparison

| Feature | Nearby Drop | Apple AirDrop | Cloud Storage | Android File Transfer |
| :--- | :---: | :---: | :---: | :---: |
| **Android to Mac Wireless** | **Yes** (Quick Share) | No | Yes (Upload/Download) | No |
| **Mac to Android Wireless** | **Yes** (Quick Share) | No | Yes (Upload/Download) | No |
| **Instant QR Code Pairing** | **Yes** (Built-in) | No | No | No |
| **USB MTP File Explorer** | **Yes** (Built-in) | No | No | Yes (Deprecated) |
| **macOS Finder Share Menu** | **Yes** (Native Extension) | Yes (Apple only) | Yes | No |
| **Zero Cloud / Local Only** | **Yes** (Local P2P) | Yes (Apple only) | No (Cloud Relayed) | Yes (USB only) |

## Download

**macOS 14 Sonoma or newer · Apple silicon and Intel**

1. Download the installer: [**Nearby-Drop-2.3.1.dmg**](https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest/download/Nearby-Drop-2.3.1.dmg).
2. Open the disk image and drag **Nearby Drop** into your `/Applications` folder.
3. The DMG includes native universal binaries (`arm64` and `x86_64`), the Finder Share Extension, and USB dynamic libraries.

> [!NOTE]
> Builds are currently ad hoc signed. macOS may show a Gatekeeper notice on first launch. If prompted, open **System Settings → Privacy & Security → Open Anyway** to authorize the app.

Settings → About displays the active version and provides manual update checks against GitHub Releases.

## How to Use

### Wireless Transfer (Quick Share)
1. Ensure your Mac and Android device are connected to the same local Wi-Fi network. Allow local network access when macOS prompts.
2. Open Nearby Drop from the menu bar:
   - **Send to Android**: Click **Send**, pick files, and select your phone from discovered nearby devices.
   - **Receive from Android**: On your phone, select files and tap **Quick Share**. Accept the transfer prompt in the Nearby Drop dropdown and verify the pairing code.
   - **QR Code Pairing**: Click **Receive** to scan a phone's Quick Share QR code with your Mac's camera.

### USB Storage Transfer (MTP)
1. Connect your Android phone to your Mac with a USB cable.
2. Unlock your phone and select **File transfer / Android Auto** in the USB settings prompt.
3. Open Nearby Drop, switch to the **USB** tab, and browse or drag files directly.

## Network and Device Notes

- Wireless speed depends on network capacity. A 5 GHz Wi-Fi or Wi-Fi 6 router delivers the best throughput.
- Both devices must share a reachable local subnet. Guest networks or router client isolation can prevent discovery.
- LTE-only phone-hotspot discovery has not been verified and may not show the Mac. Use a shared Wi-Fi network or USB MTP if discovery fails.
- The Mac advertises itself on your local network while Nearby Drop is active. Google account/contact-restricted discovery is not supported.
- See [release verification](RELEASE-VERIFICATION.md) for full hardware test coverage and limits.

## Build and Test

Requirements: Xcode 26 or newer with the macOS SDK. Universal USB libraries and pinned Swift packages are checked into the repository.

```sh
# Universal Release Build
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
  -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build

# Run Automated Tests
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build-tests CODE_SIGNING_ALLOWED=NO test
```

Universal packages can be generated using `scripts/package-release.sh build dist`. Protocol definitions are documented in [PROTOCOL.md](PROTOCOL.md).

## Contributing

Contributions, bug fixes, and feature suggestions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines, build instructions, and automated testing requirements.

## Privacy and Security

- Camera access is used solely for optical Quick Share QR code scanning.
- File contents and transfer history remain strictly local on your Mac.
- The manual update check queries GitHub's public release API and never transmits telemetry or personal files.
- Report security issues privately through [GitHub Security Advisories](https://github.com/arslanbasharat-o-o/NearByDrop/security/advisories/new).

## Copyright and Licenses

Nearby Drop is proprietary software created and maintained by **Arslan Basharat**.
Copyright © 2026 Arslan Basharat. All rights reserved.

Unauthorized copying, distribution, modification, reverse engineering, decompilation, public display, or commercial use of this software, in source code or binary form, without express prior written permission is strictly prohibited. See [LICENSE](LICENSE) for details.

### Third-Party Open Source Components
Dependencies retain their respective open-source licenses:
- [SwiftECC](https://github.com/leif-ibsen/SwiftECC), [BigInt](https://github.com/leif-ibsen/BigInt), [ASN1](https://github.com/leif-ibsen/ASN1), [SwiftProtobuf](https://github.com/apple/swift-protobuf), [QRCode](https://github.com/dagronf/qrcode), [SwiftImageReadWrite](https://github.com/dagronf/SwiftImageReadWrite), and [swift-qrcode-generator](https://github.com/dagronf/swift-qrcode-generator).
- USB support dynamically links [libmtp](https://github.com/libmtp/libmtp) and [libusb](https://github.com/libusb/libusb) under LGPL 2.1 or later. License texts and source archives are documented in [Vendor/USB](Vendor/USB/README.md).

Nearby Drop is an independent project and is not affiliated with Google LLC or Apple Inc. Quick Share, Android, macOS, and AirDrop are trademarks of their respective owners.
