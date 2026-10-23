<p align="center">
  <img src="docs/assets/icon.png" alt="Nearby Drop app icon" width="112">
</p>

<h1 align="center">Nearby Drop</h1>
<p align="center"><strong>Move files between your Mac, Android, and compatible Windows devices.</strong></p>

<p align="center">
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml"><img alt="Build status" src="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/arslanbasharat-o-o/NearByDrop?color=blue"></a>
  <img alt="macOS 14 or newer" src="https://img.shields.io/badge/macOS-14%2B-black">
  <img alt="Proprietary license" src="https://img.shields.io/badge/license-proprietary-red">
</p>

<p align="center">
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest"><strong>Download</strong></a> ·
  <a href="https://arslanbasharat-o-o.github.io/NearByDrop/">Guides</a> ·
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/issues">Report a problem</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

Nearby Drop is a native macOS menu bar app for sharing files with Android phones and compatible Windows Quick Share clients. Send over Wi-Fi, scan or show a QR code, connect by USB, or use Finder’s Share menu.

## Pick your path

| Quick Share | QR codes | USB MTP | Finder |
| --- | --- | --- | --- |
| Send and receive files over a reachable local network. | Scan a phone’s code in the app, or show a code for the phone to scan. | Browse Android storage and move files over a cable. | Share files, folders, and links from the Finder menu. |

## Get started

1. [Download the latest DMG](https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest).
2. Open it and drag **Nearby Drop** into **Applications**.
3. Open the app from the menu bar.

The app supports macOS 14 or newer on Apple silicon and Intel. Releases are currently ad hoc signed, so macOS may ask you to approve the first launch in **System Settings → Privacy & Security**.

Starting with version 2.3.3, the app checks for updates at launch and hourly. When one is ready, choose **Update & Restart** from the menu or About page. Versions 2.3.2 and earlier need one manual update to 2.3.3 first.

## Send and receive

- **Mac to phone or PC:** Open **Send**, choose files, then select a nearby device. Both devices need to be on a reachable local network.
- **Phone to Mac:** Choose files on the phone and share with Quick Share. Accept the request in Nearby Drop, unless that device is trusted for automatic acceptance.
- **QR:** Use **Receive → Scan QR Code** to scan a phone’s Quick Share code. Choose **QR Share** to show a code from the Mac.
- **USB:** Connect and unlock the phone, choose **File transfer / Android Auto** in its USB prompt, then open the **USB** tab.
- **Finder:** Select items, open the Share menu, and choose **Nearby Drop**.

## What has been tested

| Connection | Result |
| --- | --- |
| Pixel 8 Pro ↔ Mac over local Wi-Fi | File transfer and both QR directions were manually confirmed. |
| One Windows PC ↔ Mac | Both directions passed with the Google Quick Share app in a development build; the packaged release was not separately device-tested. |
| Android USB MTP | Supported. Browse, upload, and download were not reverified in the latest device-test round. |
| Phone hotspot using LTE | Not verified; use a shared Wi-Fi network or USB if discovery does not work. |

See [device verification notes](docs/DEVICE-VERIFICATION.md) for the tested scope and limitations. Results on one device do not guarantee compatibility with every Android phone or Windows PC.

## Network and privacy

- Both devices need a reachable local network. Guest Wi-Fi and client isolation can block discovery.
- Wireless Quick Share sessions are encrypted. Files travel directly between devices; Nearby Drop does not relay them through a cloud service. USB MTP uses the connected cable.
- The app contacts GitHub to check for signed updates. It does not send transfer history or personal files.
- Quick Share is a Google trademark. Nearby Drop is independent and is not affiliated with Google or Apple.

## For developers

See [Contributing](CONTRIBUTING.md) for the universal release build and automated test commands. Protocol notes are in [PROTOCOL.md](PROTOCOL.md); USB library notices and source details are in [Vendor/USB](Vendor/USB/README.md).

## License

Nearby Drop is free to download and proprietary. Third-party components retain their own licenses; see [LICENSE](LICENSE) and [Vendor/USB](Vendor/USB/README.md).
