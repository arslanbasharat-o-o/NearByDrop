<h1 align="center">Nearby Drop</h1>

<div align="center">
  <img src="docs/assets/icon.png" alt="Nearby Drop app icon" width="88" />
  <p><strong>Quick Share between your Mac and Android.</strong><br />Wi-Fi, QR, or USB. Compatible Windows clients are supported too.</p>
  <p>
    <a href="https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest"><strong>Download for Mac</strong></a> ·
    <a href="https://arslanbasharat-o-o.github.io/NearByDrop/">Website & setup</a> ·
    <a href="https://github.com/arslanbasharat-o-o/NearByDrop/releases">Release notes</a>
  </p>
  <p>
    <img alt="macOS 14 or newer" src="https://img.shields.io/badge/macOS-14%2B-black" />
    <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/Mac-Apple%20silicon%20%2B%20Intel-blue" />
    <img alt="Proprietary license" src="https://img.shields.io/badge/license-proprietary-red" />
  </p>
</div>

<table align="center">
  <tr>
    <td width="50%" align="center"><strong>Send</strong><br /><img src="docs/assets/screenshots/send.jpg" alt="Nearby Drop Send screen, searching for nearby devices" width="360" /></td>
    <td width="50%" align="center"><strong>Receive</strong><br /><img src="docs/assets/screenshots/receive.jpg" alt="Nearby Drop Receive screen, ready to receive files" width="360" /></td>
  </tr>
  <tr>
    <td width="50%" align="center"><strong>Transfers</strong><br /><img src="docs/assets/screenshots/transfers.jpg" alt="Nearby Drop Transfers screen with no recent transfers" width="360" /></td>
    <td width="50%" align="center"><strong>USB</strong><br /><img src="docs/assets/screenshots/usb.jpg" alt="Nearby Drop USB screen with no device connected" width="360" /></td>
  </tr>
</table>

Nearby Drop is an independent macOS menu bar app. It is not affiliated with Google or Apple.

## Install

Download the [latest DMG](https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest), drag Nearby Drop to **Applications**, then open it. Requires **macOS 14 or newer**.

The app is ad hoc signed, not notarized. If macOS blocks it, open it once and approve it in **System Settings → Privacy & Security**. Keep Gatekeeper enabled.

## Send files

- **Android → Mac:** Put both devices on reachable Wi-Fi. Leave Nearby Drop on **Receive**, then select this Mac in Quick Share and accept the transfer. Scan a QR code if discovery fails.
- **Mac → Android:** In **Send**, choose files and select the Android device. Accept on the phone.
- **USB:** Unlock the phone, choose **File transfer**, connect a data cable, then use the **USB** tab.

Nearby Drop also supports Finder sharing, transfer history, and signed in-app updates. Windows Quick Share was tested with one PC; see the [device verification record](docs/DEVICE-VERIFICATION.md).

## Upgrade candidate

The development branch adds **Vice Nights**, **Coastal Sunrise**, and **Midnight Route**, alongside System, Light, and Dark. Original sunset, coast, and route artwork coordinates with readable controls and state colors. Appearance changes apply immediately and persist.

The candidate also includes Connection Doctor, favorite-recipient selection hints, explicit text/link sharing as UTF-8 files, screenshot preview, a seven-step setup guide, and USB current-folder filtering/sorting. Favorites do not authenticate devices or bypass approval. Native text/link Quick Share payload support is unverified; receivers get a clearly labeled `.txt` file. Screenshot capture requires explicit user action, macOS permission, and review.

Large-batch execution remains disabled; the 128-file limit is retained. The diagnostics RC (build 23) fixes custom-theme navigation contrast and sends diagnostic reports automatically after its setup disclosure, without in-app reporting switches. The operational collector/dashboard have been deployed after isolated MySQL checks and backups; configured builds enable operational reporting by default. No public app release has occurred. See [the implementation checklist](docs/upgrade/CHECKLIST.md), [diagnostics contract](docs/upgrade/ANALYTICS.md), and [batch limits](docs/upgrade/EXPERIMENTAL-BATCHES.md).

The public download above remains the current stable release. Nearby Drop is not affiliated with Rockstar Games.

## Privacy

Wireless transfers go directly over your local network; Nearby Drop does not relay files through its own cloud service. Incoming transfers need your approval unless you trust that device. The current development candidate sends diagnostic reports automatically after setup and offers no in-app off switch. Older public versions may still have reporting controls. They include first launch and app opens (hour-rounded), a random installation ID, app and macOS versions, Mac hardware model, your Mac's advertised name, and the other device's advertised name and broad type after a successful wireless transfer. They never include file names, file contents, or device IDs. See the [privacy policy](https://arslanbasharat-o-o.github.io/NearByDrop/legal/privacy.html).

## Help

[Setup and FAQs](https://arslanbasharat-o-o.github.io/NearByDrop/) ·
[Report a bug](https://github.com/arslanbasharat-o-o/NearByDrop/issues) ·
[Security policy](SECURITY.md)

When reporting a bug, include the app and macOS versions, Mac type, phone model, and connection method. Do not post personal files, credentials, or active pairing codes.

## Project

[Contributing](CONTRIBUTING.md) · [Protocol notes](PROTOCOL.md) · [License](LICENSE) · [Third-party notices](Vendor/USB/README.md)

Nearby Drop is proprietary software, free to download. Quick Share is a Google trademark.
