# Launch & Distribution Guide: Nearby Drop v2.3.0

Complete launch and distribution kit with ready-to-post copy for Reddit, X (Twitter), Discord, Hacker News, and Product Hunt. Formatted for high engagement, genuine technical credibility, zero false claims, and immediate traffic to the repository.

---

## 1. Quick Links

- **Repository**: `https://github.com/arslanbasharat-o-o/NearByDrop`
- **Landing Page**: `https://arslanbasharat-o-o.github.io/NearByDrop/`
- **Latest Universal DMG (v2.3.0)**: `https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest/download/Nearbydrop-2.3.0.dmg`
- **Terminal 1-Line Installer**:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/arslanbasharat-o-o/NearByDrop/main/scripts/install.sh | sh
  ```

---

## 2. Reddit Posts

### Post A: For `r/macapps` & `r/mac`
**Title**: `I built an open-source macOS menu bar daemon to receive files from Android via Quick Share (AirDrop alternative)`

**Body**:
```markdown
Hey r/macapps,

If you daily drive an Android phone alongside a Mac, you know how annoying file transfers can be. Apple keeps AirDrop exclusive, Google's Android File Transfer app is abandoned, and uploading to Google Drive or Telegram burns bandwidth and compresses video.

I built **Nearby Drop** to solve this properly: https://github.com/arslanbasharat-o-o/NearByDrop

### How it works:
- **Native Quick Share**: Uses Android's built-in Quick Share sheet. No companion app required on your phone.
- **Local P2P Wi-Fi**: Streams directly over your local router or hotspot using raw TCP sockets (typically 25–80 MB/s on 5GHz Wi-Fi).
- **USB-C MTP Explorer**: When Wi-Fi is unavailable or you have huge video folders, plug in a USB cable and browse phone storage with drag-and-drop.
- **Zero Cloud & Private**: Mutual cryptographic UKEY2 ECDH (P-256) handshake with on-screen 6-digit confirmation PIN.
- **Pure Native macOS**: Lightweight AppKit/SwiftUI menu bar resident daemon with near-zero idle CPU and memory consumption.
- **100% Free & Open Source**: Licensed under GPL-3.0. No accounts, no paywalls, zero telemetry.

Universal DMG for macOS 14 Sonoma and Sequoia (Apple Silicon M1–M4 & Intel):
https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest

Live site & specifications: https://arslanbasharat-o-o.github.io/NearByDrop/

Would love your feedback and bug reports on GitHub!
```

---

### Post B: For `r/Android` & `r/opensource`
**Title**: `Nearby Drop: Open-source macOS daemon to receive Quick Share / Nearby Share files from any Android device`

**Body**:
```markdown
Hey everyone,

One of the biggest friction points when switching between Android and Mac is sending photos, raw videos, and folders without cables or cloud uploads.

I built **Nearby Drop** (https://github.com/arslanbasharat-o-o/NearByDrop), a free and open-source menu bar daemon for macOS that implements Google's Quick Share wire protocol.

### Key Details:
- **Zero phone apps needed**: Uses the native Quick Share button pre-installed on Samsung, Pixel, OnePlus, Xiaomi, and other modern Android devices.
- **Real-world local Wi-Fi speeds**: Direct socket streaming (typically 25–80 MB/s over 5GHz Wi-Fi depending on your router).
- **Offline operation**: Works completely offline on local Wi-Fi, airplane hotspots, or direct USB-C via libmtp.
- **Security**: Cryptographically verified via UKEY2 (ECDH P-256) matching PINs before any bytes are transmitted.
- **Open source**: GPL-3.0 licensed, full source code public, universal binary.

Website: https://arslanbasharat-o-o.github.io/NearByDrop/
GitHub: https://github.com/arslanbasharat-o-o/NearByDrop

PRs and issues are welcome!
```

---

## 3. X / Twitter Launch Posts

### Main Tweet (Hook + Call to Action):
```text
Tired of emailing yourself files or uploading 4K videos to Google Drive just to get them from Android to your Mac?

I built Nearby Drop — an open-source macOS menu bar daemon that brings AirDrop-like wireless transfers to Android via Quick Share.

⚡ Direct local Wi-Fi (25–80 MB/s)
🔌 Wired USB-C MTP storage mode
🔒 UKEY2 ECDH encryption • 100% offline
🍎 Universal binary (Apple Silicon + Intel)
🆓 Free & Open Source (GPL-3.0)

GitHub: https://github.com/arslanbasharat-o-o/NearByDrop
Website: https://arslanbasharat-o-o.github.io/NearByDrop/

#Android #macOS #OpenSource #AirDrop #SwiftUI #Developer
```

### Follow-up Reply (Installation & Terminal):
```text
Install in seconds with one terminal command:

curl -fsSL https://raw.githubusercontent.com/arslanbasharat-o-o/NearByDrop/main/scripts/install.sh | sh

Or grab the official .DMG release on GitHub:
https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest

Star the repo if you find it useful! ⭐
```

---

## 4. Discord Community Announcements

**Ideal channels**: `#showcase`, `#projects`, `#general-dev` in developer, Mac, Android, and self-hosted communities.

```markdown
**Nearby Drop v2.3.0 — Native Quick Share Daemon for macOS**
Hey everyone! Just launched **Nearby Drop**, an open-source macOS menu bar application that lets you receive files from Android devices via Google Quick Share.

- **No phone app required**: Uses native Android Quick Share.
- **Local P2P transfer**: Fast Wi-Fi streaming (25–80 MB/s) + USB-C MTP mode.
- **Zero cloud**: UKEY2 ECDH encryption with 6-digit confirmation PIN.
- **Free & Open Source**: Universal Mach-O for Apple Silicon & Intel.

Check it out:
- GitHub: https://github.com/arslanbasharat-o-o/NearByDrop
- Web: https://arslanbasharat-o-o.github.io/NearByDrop/
- Download: https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest
```

---

## 5. Hacker News ("Show HN")

**Submit URL**: `https://news.ycombinator.com/submit`  
**Title**: `Show HN: Nearby Drop – Native macOS Quick Share daemon for Android transfers`  
**URL**: `https://github.com/arslanbasharat-o-o/NearByDrop`

**Text / First Comment**:
```text
Hey HN,

I built Nearby Drop (https://github.com/arslanbasharat-o-o/NearByDrop) to solve the cross-platform file transfer friction between Android and macOS.

Apple's AirDrop is strictly Apple-only, and Google's official Android File Transfer app for Mac has long been discontinued. Cloud relays require uploading payloads twice and burn bandwidth.

Nearby Drop is an open-source AppKit/SwiftUI daemon that runs in the macOS menu bar and implements Google's Quick Share protocol:
- Discovers Android devices via mDNS (_FC9F5ED42C8A._tcp.local.)
- Negotiates mutual cryptographic handshakes via UKEY2 (ECDH P-256)
- Streams files directly over local Wi-Fi TCP sockets (real-world 25–80 MB/s on 5GHz LAN)
- Features a built-in USB-C MTP storage browser via libmtp for wired transfers
- Zero external servers, zero telemetry, 100% offline

Pre-built universal binary (macOS 14+ Sonoma & Sequoia):
https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest

Feedback on device compatibility and network edge cases is very welcome!
```

---

## 6. Product Hunt Launch Copy

- **Product Name**: Nearby Drop
- **Tagline**: Native AirDrop-like Quick Share daemon for Mac & Android
- **Category**: Developer Tools, Open Source, macOS, Utilities
- **Website URL**: `https://arslanbasharat-o-o.github.io/NearByDrop/`
- **Pricing**: Free / Open Source
- **Short Description**:
  Nearby Drop is an open-source macOS menu bar resident daemon that implements Google's Quick Share protocol. Wirelessly beam photos, 4K videos, and directories directly from any modern Android phone to your Mac at local Wi-Fi speeds with zero cloud servers or third-party accounts. Includes integrated USB-C MTP storage management for wired transfers.
