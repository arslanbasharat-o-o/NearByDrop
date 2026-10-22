# Nearbydrop

<p align="center">
  <strong>The High-Performance Cross-Platform Sync & Device Bridge SaaS for macOS and Android.</strong>
</p>

<p align="center">
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml"><img src="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml/badge.svg" alt="Build Status" /></a>
  <img src="https://img.shields.io/badge/status-Private%20SaaS%20Preview-blue.svg" alt="Status" />
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Android-green.svg" alt="Platform" />
  <img src="https://img.shields.io/badge/license-Proprietary%20%2F%20Commercial-red.svg" alt="License" />
</p>

---

Nearbydrop brings effortless, ultra-fast file transfer, instant visual QR pairing, and native USB Android storage management to macOS. Designed for creative professionals, engineers, and modern teams who demand instantaneous transfers without relying on third-party cloud lockers, sluggish web uploads, or cloud bandwidth fees.

Created and engineered by **[Arslan Basharat](https://github.com/arslanbasharat-o-o)**.

---

## ⚡ What Makes Nearbydrop Different

- **Gigabit Local Speeds**: Transfer multi-gigabyte video libraries, photography batches, and raw media over your local Wi-Fi or USB connection at maximum hardware throughput (up to 500+ MB/s).
- **Zero-Cloud Data Boundary**: Your files never upload to third-party cloud servers or external relays. All operations use peer-to-peer authenticated channels.
- **Instant Visual QR Pairing**: Point your Mac's camera at an Android screen from the menu bar to instantly establish a cryptographically authenticated session.
- **Direct USB File Explorer**: Integrated MTP engine for bidirectional Android filesystem browsing, folder sync, batch downloads, and Finder drag-and-drop.
- **Native macOS Experience**: Crafted in SwiftUI and AppKit to live unobtrusively in your menu bar with Finder Share Extension integration.

---

## 🚀 Product Capabilities

| Capability | Description |
| :--- | :--- |
| **Wireless Transfers** | High-speed, end-to-end encrypted transfers compatible with Android Quick Share. |
| **Inline Camera Scanner** | Integrated QR scanner inside the menu bar popup for zero-friction device discovery. |
| **Android USB Bridge** | Native, kernel-level MTP explorer for wired file and directory transfers. |
| **Finder Integration** | Send files, folders, and links directly from macOS Finder via the native Share Extension. |
| **Granular Device Trust** | Remember verified workstations and devices for seamless, one-click authorization. |

---

## 💼 SaaS Tiers & Licensing

Nearbydrop is offered as a commercial Software as a Service (SaaS) and managed client platform:

### 🔹 Professional
- High-speed peer-to-peer Wi-Fi and wired USB transfers.
- Integrated camera QR scanner and instant pairing.
- Finder Share Extension integration and batch file manager.
- Priority customer support and regular client updates.

### 🔹 Team & Enterprise
- Centralized deployment support for managed macOS fleets.
- Custom enterprise policies, security auditing, and local storage rules.
- Dedicated onboarding and direct developer support.

---

## 📥 Access & Distribution

Nearbydrop is delivered as a commercial SaaS product directly to subscribers and pilot customers.

> [!NOTE]
> **No Public GitHub Releases**: Nearbydrop does not distribute public binary releases on GitHub Releases. Client builds, updates, and licensing keys are provided exclusively through commercial customer channels and private early access invitations.

### Request Early Access / Enterprise Inquiries
To request a demonstration, purchase licenses, or join the private SaaS preview, please reach out to **[Arslan Basharat](https://github.com/arslanbasharat-o-o)** via GitHub or open an inquiry in [Discussions / Issues](https://github.com/arslanbasharat-o-o/NearByDrop/issues).

---

## 🔒 Enterprise Security & Architecture

Nearbydrop prioritizes confidentiality, speed, and privacy:

1. **UKEY2 Handshake**: Cryptographic curve P-256 ECDH key exchange establishes ephemeral shared secrets between devices.
2. **Encrypted Transport**: High-performance AES-GCM data stream protects in-flight file data over local network routes.
3. **Local Authentication**: QR code pairing verifies the public key fingerprint of the peer device before a single byte of metadata is accepted.
4. **Isolated Filesystem Operations**: Incoming transfers enforce sanitized filesystem boundaries to eliminate path traversal or link vulnerabilities.

---

## 🛠️ Developer & Evaluator Build

Authorized developers and security evaluators can build the project locally using Xcode 26 or newer:

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

---

## 📄 Copyright and Commercial Terms

**Nearbydrop** is proprietary software created and owned by **Arslan Basharat**.  
Copyright © 2026 Arslan Basharat. All rights reserved.

Unauthorized copying, distribution, modification, reverse engineering, decompilation, public display, or commercial exploitation of this software and source code, in whole or in part, without explicit prior written authorization is strictly prohibited. See [LICENSE](LICENSE) for details.

### Third-Party Components
Third-party libraries bundled with or linked by the application retain their respective open-source licenses (including libmtp and libusb under LGPL 2.1+, and Swift packages under MIT / Apache 2.0). Refer to [Vendor/USB](Vendor/USB/README.md) and internal licensing documentation.

*Nearbydrop is an independent commercial product and is not affiliated with Google LLC or Apple Inc. Quick Share, Android, and macOS are trademarks of their respective owners.*
