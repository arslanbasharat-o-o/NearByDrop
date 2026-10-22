# Nearbydrop

<p align="center">
  <strong>High-speed, zero-cloud peer-to-peer file transfer and device bridge for macOS and Android.</strong>
</p>

<p align="center">
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml"><img src="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml/badge.svg" alt="Build Status" /></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Android-green.svg" alt="Platform" />
  <img src="https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-orange.svg" alt="Architectures" />
  <img src="https://img.shields.io/badge/license-Proprietary-red.svg" alt="License" />
</p>

---

Nearbydrop brings effortless, ultra-fast file transfer, instant visual QR pairing, and native Android USB storage management into one streamlined macOS menu bar app. Designed for seamless workflows between your Mac and Android devices without requiring cloud accounts, web uploads, or external relays.

Created and engineered by **[Arslan Basharat](https://github.com/arslanbasharat-o-o)**.

---

## ⚡ What it does

- **Wireless Quick Share Transfers**: Send and receive photos, videos, documents, and folders over your local Wi-Fi network at full hardware speed (up to 500+ MB/s).
- **Inline QR Camera Scanner**: Scan a sender’s Quick Share QR code directly with a live camera preview in the menu bar dropdown, or display a code for selected files.
- **Direct USB File Explorer**: Native MTP file manager for bidirectional Android storage browsing, folder downloads, batch transfers, and Finder drag-and-drop.
- **Finder Integration**: Send files, folders, and links directly from macOS Finder via the native Share Extension.
- **Zero-Cloud Data Boundary**: All transfers remain strictly on your local network or USB cable. End-to-end UKEY2 cryptographic handshakes protect data integrity and privacy.
- **Native macOS Experience**: Polished SwiftUI interface living unobtrusively in your menu bar with real-time transfer tracking.

---

## 📥 Download

**macOS 14 Sonoma or newer · Apple silicon and Intel**

1. Download the universal ZIP from [Releases](https://github.com/arslanbasharat-o-o/NearByDrop/releases).
2. Extract the archive and move **Nearby Drop.app** into your `/Applications` folder.
3. The release includes native universal binaries (`arm64` and `x86_64`), the Finder Share Extension, and USB dynamic libraries.

> [!NOTE]
> Builds are currently ad hoc signed. macOS Gatekeeper may prompt on first launch. If prompted, go to **System Settings → Privacy & Security → Open Anyway** to launch the app. SHA-256 checksums are provided with each release in `SHA256SUMS.txt`.

---

## 🚀 How to Use

1. **Local Wi-Fi**: Connect both your Mac and Android device to the same Wi-Fi network. Allow local network access when macOS prompts.
2. **Send & Receive**: Open Nearbydrop from the menu bar. Use **Send** to select files and a nearby target device, or **Receive** to scan a sender's Quick Share QR code.
3. **Accept Transfers**: Accept incoming requests in the dropdown. Compare the pairing PIN when prompted.
4. **USB Transfer**: Unlock your phone, select **File transfer / Android Auto** in its USB settings, then open the **USB** tab in Nearbydrop.

---

## 🔒 Security & Privacy

- **Ephemeral Keys**: Wireless transfers use the UKEY2 ECDH handshake with curve P-256 to establish encrypted channels.
- **Local Network Boundary**: Data never leaves your local physical network or USB cable. No Google account, Apple ID, or cloud servers are involved.
- **Sanitized Filesystem Storage**: Received files and folders are strictly sandboxed and sanitized against path traversal and link attacks.
- **Vulnerability Reporting**: Please report security vulnerabilities privately via [GitHub Security Advisories](https://github.com/arslanbasharat-o-o/NearByDrop/security/advisories/new).

---

## 🛠️ Build and Test

Requirements: Xcode 26 or newer with the macOS SDK. Universal USB libraries and pinned Swift packages are checked into the repository.

```sh
# Universal Release Build (Apple silicon & Intel)
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
  -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build

# Run Automated Test Suite
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build-tests CODE_SIGNING_ALLOWED=NO test
```

The packaged universal release can be generated using `scripts/package-release.sh build dist`.

---

## 📄 Copyright and License

**Nearbydrop** is proprietary software created and owned by **Arslan Basharat**.  
Copyright © 2026 Arslan Basharat. All rights reserved.

Unauthorized copying, distribution, modification, reverse engineering, decompilation, public display, or commercial exploitation of this software and source code, in whole or in part, without explicit prior written authorization is strictly prohibited. See [LICENSE](LICENSE) for details.

### Third-Party Libraries
Third-party dependencies retain their respective open-source licenses:
- [SwiftECC](https://github.com/leif-ibsen/SwiftECC), [BigInt](https://github.com/leif-ibsen/BigInt), [ASN1](https://github.com/leif-ibsen/ASN1), [SwiftProtobuf](https://github.com/apple/swift-protobuf), [QRCode](https://github.com/dagronf/qrcode), [SwiftImageReadWrite](https://github.com/dagronf/SwiftImageReadWrite), and [swift-qrcode-generator](https://github.com/dagronf/swift-qrcode-generator).
- USB support dynamically links [libmtp](https://github.com/libmtp/libmtp) and [libusb](https://github.com/libusb/libusb) under LGPL 2.1 or later. License texts and source archives are documented in [Vendor/USB](Vendor/USB/README.md).

*Nearbydrop is an independent project and is not affiliated with Google LLC or Apple Inc. Quick Share, Android, and macOS are trademarks of their respective owners.*
