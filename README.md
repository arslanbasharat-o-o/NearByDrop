# NearByDrop

NearByDrop is a Menu bar app for macOS that implements Google's [Nearby Share / Quick Share](https://blog.google/products/android/nearby-share/) protocol. Drop a file to your Android phone, receive files from it, or hand files over a USB cable when Wi-Fi is locked down.

Created by Arslan Basharat.

![Protocol documentation](/PROTOCOL.md "How the protocol works")

## Features

- **Two-way transfers.** Send files (and links) from your Mac to any Quick Share device, and receive files, links and plain text from Android, Windows or another Mac on the same Wi-Fi network. Everything is end-to-end encrypted with UKEY2/AES-256 — no cloud, no Google account.
- **Control Center–style popover.** The menu bar popover follows the AirDrop module layout: live transfer cards with PIN confirmation, a nearby-devices tray, and drag-and-drop onto the menu bar icon to start sending.
- **QR code pairing.** Display a Quick Share QR code to receive from devices that can't see the Mac via mDNS, and use the built-in Vision-based camera scanner to receive from a QR code shown on a phone.
- **USB MTP mode.** Wired transfers to/from Android storage over libmtp — browse the phone's files, upload, and save to Downloads when Wi-Fi is restricted.
- **Share extension.** Share to NearByDrop directly from Finder and the system Share menu, with a device picker and QR fallback baked into the extension UI.

## Installation

Grab the latest zip from the [Releases](https://github.com/your-org/NearByDrop/releases) page, unzip, and move `NearByDrop.app` to `/Applications`. The first launch is Gatekeeper-blocked: right-click the app in Finder and choose **Open**, or approve it in System Settings → Privacy & Security.

## Building from source

Requirements: Xcode 15 or newer. Dependencies (SwiftECC, swift-protobuf, QRCode) are resolved automatically by Swift Package Manager.

```shell
xcodebuild -project NearByDrop.xcodeproj -scheme NearByDrop -configuration Release -derivedDataPath build
```

The product is `build/Build/Products/Release/NearByDrop.app`. The Bundle ID and code-signing settings in the project are placeholders: set your own development team in Xcode's Signing & Capabilities before distributing a signed build.

The protocol `.pb.swift` files under `NearbyShare/Protobuf/` are pre-generated. Only if you edit the protos in `NearbyShare/ProtobufSource/`, run `NearbyShare/GenerateProtobuf.sh` (requires `brew install protobuf`).

## USB Acknowledgements & LGPL Compliance

The USB transfer component bundles dynamic libraries under LGPL v2.1/v3:

- **[libmtp](https://github.com/libmtp/libmtp)** — LGPL v2.1+
- **[libusb](https://github.com/libusb/libusb)** — LGPL v2.1+

Both libraries are dynamically linked from `Vendor/USB/lib/` with headers in `Vendor/USB/include/`. The corresponding license texts are available in `Vendor/USB/licenses/libmtp-LGPL.txt` and `Vendor/USB/licenses/libusb-LGPL.txt`. In compliance with LGPL requirements, users may inspect or replace these dynamic libraries with custom builds.

### Rebuilding Vendored USB Libraries
To rebuild and update the bundled dynamic libraries from source:
1. Clone the upstream repositories:
   ```shell
   git clone https://github.com/libusb/libusb.git
   git clone https://github.com/libmtp/libmtp.git
   ```
2. Build `libusb`:
   ```shell
   cd libusb && ./autogen.sh && ./configure --enable-shared --disable-static && make
   cp libusb/.libs/libusb-1.0.0.dylib Vendor/USB/lib/
   ```
3. Build `libmtp` against `libusb`:
   ```shell
   cd libmtp && ./autogen.sh && PKG_CONFIG_PATH=/path/to/libusb ./configure --enable-shared --disable-static && make
   cp src/.libs/libmtp.9.dylib Vendor/USB/lib/
   ```

## Upstream Attribution & Credits

- **Upstream Foundation**: *Built upon the foundational reverse-engineered Nearby Share protocol from Grishka's open-source NearDrop project.* See [PROTOCOL.md](/PROTOCOL.md) for protocol details.
- **Dependencies**: [SwiftECC](https://github.com/leif-ibsen/SwiftECC), [swift-protobuf](https://github.com/apple/swift-protobuf), [QRCode](https://github.com/dagronf/qrcode).


## Limitations

- **Wi-Fi LAN only.** Mac and phone must be on the same local network. Wi-Fi Direct/Hotspot/multi-device mediums are not supported on macOS.
- **Always visible** to other devices on the network while the app runs. Contact-restricted visibility requires Google's servers, which an unofficial client does not use; QR codes cover the "hidden" use case.
- Bluetooth-based discovery ("device nearby is sharing" notification) cannot be implemented on macOS: the OS does not expose the BLE service-data API Google's implementation relies on.
