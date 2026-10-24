# Nearby Drop

Nearby Drop is a native macOS menu bar app for two-way file sharing between Mac and Android with Quick Share, QR codes, and USB MTP. It also supports compatible Windows Quick Share clients and Finder sharing.

<p align="center">
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml"><img alt="Build status" src="https://github.com/arslanbasharat-o-o/NearByDrop/actions/workflows/build.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/arslanbasharat-o-o/NearByDrop?color=blue"></a>
  <img alt="macOS 14 or newer" src="https://img.shields.io/badge/macOS-14%2B-black">
  <img alt="Proprietary license" src="https://img.shields.io/badge/license-proprietary-red">
</p>

**[Website](https://arslanbasharat-o-o.github.io/NearByDrop/)** · **[Download](https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest)** · [Guides](https://arslanbasharat-o-o.github.io/NearByDrop/#guides) · [Report a problem](https://github.com/arslanbasharat-o-o/NearByDrop/issues) · [Contributing](CONTRIBUTING.md)

[Privacy](https://arslanbasharat-o-o.github.io/NearByDrop/legal/privacy.html) · [Terms](https://arslanbasharat-o-o.github.io/NearByDrop/legal/terms.html) · [Security and data handling](https://arslanbasharat-o-o.github.io/NearByDrop/legal/security.html) · [License and third-party notices](https://arslanbasharat-o-o.github.io/NearByDrop/legal/licenses.html)

Send over Wi-Fi, scan or show a QR code, connect by USB, or share from Finder.

## Screenshots

| Receive | Send |
| :---: | :---: |
| ![Nearby Drop’s Receive screen, ready for files from Android with the device name redacted](docs/assets/nearby-drop-receive.webp) | ![Nearby Drop’s Send screen, with file selection and QR sharing](docs/assets/nearby-drop-send.webp) |

## Similar names

This GitHub repository is named **NearByDrop**; the app is branded **Nearby Drop**. It is separate from [NearDrop by grishka](https://github.com/grishka/NearDrop). See the [sourced comparison of the two Mac apps](https://arslanbasharat-o-o.github.io/NearByDrop/blog/neardrop-vs-nearby-drop.html).

## Pick your path

| Quick Share | QR codes | USB MTP | Finder |
| --- | --- | --- | --- |
| Send and receive files over a reachable local network. | Scan a phone’s code in the app, or show a code for the phone to scan. | Browse Android storage and move files over a cable. | Share files, folders, and links from the Finder menu. |

## Track and manage transfers

- **Progress:** Follow transfer direction, status, progress, speed, and estimated time remaining.
- **History:** Review recent incoming and outgoing items, including their file, device, size, and time. Open a saved item in Finder.
- **USB MTP:** Browse Android storage and upload or download files and folders over a cable.
- **Settings:** Choose the download folder, appearance, accent color, launch-at-login, sound, and haptic feedback.
- **Trusted devices:** Manage devices that can accept transfers automatically.
- **Updates:** Check for new versions from the About screen and install an available update from the app.

## Transfer guides

- [Receive Android files on a Mac with Quick Share or USB MTP](https://arslanbasharat-o-o.github.io/NearByDrop/blog/how-to-transfer-files-mac-android.html)
- [Send files from a Mac to Android with Quick Share](https://arslanbasharat-o-o.github.io/NearByDrop/blog/mac-to-android-quick-share.html)
- [Compare Android-to-Mac file transfer options](https://arslanbasharat-o-o.github.io/NearByDrop/blog/airdrop-alternative-for-android.html)
- [Use Quick Share between Mac and Windows](https://arslanbasharat-o-o.github.io/NearByDrop/blog/quick-share-mac-windows.html)
- [Compare NearDrop and Nearby Drop](https://arslanbasharat-o-o.github.io/NearByDrop/blog/neardrop-vs-nearby-drop.html)

## Install Nearby Drop

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
| Android USB MTP | Browse, upload, and download passed with Pixel and Nexus devices. |
| Phone hotspot using LTE | Not verified; use a shared Wi-Fi network or USB if discovery does not work. |

See the [device verification page](https://arslanbasharat-o-o.github.io/NearByDrop/device-verification.html) for the tested scope and limitations, or read the [Markdown source](docs/DEVICE-VERIFICATION.md). Results on one device do not guarantee compatibility with every Android phone or Windows PC.

## Network and privacy

- Both devices need a reachable local network. Guest Wi-Fi and client isolation can block discovery.
- Wireless Quick Share sessions are encrypted. Files travel directly between devices; Nearby Drop does not relay them through a cloud service. USB MTP uses the connected cable.
- The app contacts GitHub to check for signed updates. It does not send transfer history or personal files.
- Quick Share is a Google trademark. Nearby Drop is independent and is not affiliated with Google or Apple.

## For developers

See [Contributing](CONTRIBUTING.md) for the universal release build and automated test commands. Protocol notes are in [PROTOCOL.md](PROTOCOL.md); USB library notices and source details are in [Vendor/USB](Vendor/USB/README.md).

### Website development

The site is static HTML under `docs/` so GitHub Pages can serve its pages and search metadata without a client-side app shell. React is used only for the homepage component islands. From the repository root:

```sh
npm ci
npx tsc --noEmit
npm run test:site
npm run build:css
npm run build:components
python3 scripts/check_site_seo.py
python3 -m http.server 8765 --directory docs
```

The live project site is published under `/NearByDrop/`; keep asset, canonical, and sitemap paths aligned with that base path. See the [site privacy page](https://arslanbasharat-o-o.github.io/NearByDrop/legal/privacy.html) for browser storage and hosting details.

To monitor search indexing, verify the URL-prefix property `https://arslanbasharat-o-o.github.io/NearByDrop/` in Google Search Console, submit `https://arslanbasharat-o-o.github.io/NearByDrop/sitemap.xml`, then use URL Inspection and the indexing reports to review important pages. Verification and monitoring require access to the project’s Search Console account; sitemap submission does not guarantee indexing.

## License

Nearby Drop is free to download and proprietary. Third-party components retain their own licenses; see [LICENSE](LICENSE) and [Vendor/USB](Vendor/USB/README.md).
