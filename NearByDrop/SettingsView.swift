import Cocoa
import SwiftUI
import ServiceManagement
import NearbyShare

final class SettingsWindowController: NSWindowController, ObservableObject {
    let model: TransferModel
    @Published var selectedTab: SettingsTab = .general

    init(model: TransferModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NearByDropSettings")
        window.center()
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(model: model, controller: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(tab: SettingsTab? = nil) {
        if let tab = tab {
            selectedTab = tab
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case appearance = "Appearance"
    case trusted = "Trusted Devices"
    case guide = "How to Use"
    case privacy = "Privacy & Security"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .trusted: return "shield.checkmark"
        case .guide: return "questionmark.circle"
        case .privacy: return "hand.raised.shield"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: TransferModel
    @ObservedObject var controller: SettingsWindowController
    @ObservedObject private var theme = ThemeManager.shared
    @State private var customName: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        controller.selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                                .frame(width: 20)
                                .foregroundStyle(controller.selectedTab == tab ? theme.currentAccent.color : .secondary)
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: controller.selectedTab == tab ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            controller.selectedTab == tab ? theme.currentAccent.color.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 190)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch controller.selectedTab {
                    case .general: generalTab
                    case .appearance: appearanceTab
                    case .trusted: trustedTab
                    case .guide: guideTab
                    case .privacy: privacyTab
                    case .about: aboutTab
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 680, height: 560)
        .onAppear {
            customName = UserDefaults.standard.string(forKey: "customDeviceName") ?? model.deviceName
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Device Identity", subtitle: "How this Mac appears to nearby Quick Share phones and PCs.")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Device Name:")
                        .frame(width: 120, alignment: .leading)
                        .font(.subheadline)
                    TextField("Device Name", text: $customName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit {
                            NearbyConnectionManager.customDeviceName = customName.isEmpty ? nil : customName
                        }
                    Button("Reset") {
                        customName = Host.current().localizedName ?? "This Mac"
                        NearbyConnectionManager.customDeviceName = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Download Destination", subtitle: "Where received files and directories are automatically saved.")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(theme.currentAccent.color)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.downloadDirectory.lastPathComponent)
                            .font(.headline)
                        Text(model.downloadDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…") {
                        model.chooseDownloadDirectory()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.small)

                    Button("Open in Finder") {
                        TransferModel.openDownloads()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Application Behavior", subtitle: "Control how NearByDrop integrates with macOS.")

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.toggleLaunchAtLogin(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.subheadline.weight(.medium))
                        Text("Automatically start NearByDrop when you log into your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Divider()

                Toggle(isOn: $theme.showInDock) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show NearByDrop in Dock (Full Mac App)")
                            .font(.subheadline.weight(.medium))
                        Text("When enabled, NearByDrop appears in the Dock and App Switcher like a standard Mac app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Appearance Tab
    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "App Theme", subtitle: "Select the appearance mode for windows and menus.")

            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { t in
                    Button {
                        theme.currentTheme = t
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: t.icon)
                                .font(.system(size: 24))
                                .foregroundStyle(theme.currentTheme == t ? theme.currentAccent.color : .secondary)
                            Text(t.rawValue)
                                .font(.caption.weight(theme.currentTheme == t ? .bold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            theme.currentTheme == t ? theme.currentAccent.color.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.currentTheme == t ? theme.currentAccent.color : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            sectionHeader(title: "Accent Color", subtitle: "Choose a custom highlight color used throughout NearByDrop.")

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ForEach(AccentOption.allCases) { opt in
                        Button {
                            theme.currentAccent = opt
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(opt.color)
                                    .frame(width: 32, height: 32)
                                    .shadow(color: opt.color.opacity(0.3), radius: 3, y: 1)
                                if theme.currentAccent == opt {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(opt.rawValue)
                    }
                }
                .padding(.vertical, 6)

                Text("Active Color: \(theme.currentAccent.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Menu Bar Icon Style", subtitle: "Choose which icon appears in the macOS menu bar.")

            HStack(spacing: 12) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    Button {
                        theme.menuBarIconStyle = style
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: style.sfSymbol)
                                .font(.title3)
                                .foregroundStyle(theme.menuBarIconStyle == style ? theme.currentAccent.color : .secondary)
                            Text(style.rawValue)
                                .font(.subheadline)
                            Spacer()
                            if theme.menuBarIconStyle == style {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.currentAccent.color)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.menuBarIconStyle == style ? theme.currentAccent.color : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            sectionHeader(title: "Live Preview", subtitle: "Sample button and card with the selected theme.")

            HStack(spacing: 14) {
                Button("Primary Action") {}
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)

                Button("Secondary Action") {}
                    .buttonStyle(.bordered)

                ProgressView(value: 0.65)
                    .frame(maxWidth: 160)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Trusted Devices Tab
    private var trustedTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Trusted Devices", subtitle: "Transfers from trusted devices are accepted automatically without a PIN prompt.")

            let list = UserDefaults.standard.stringArray(forKey: "trustedDevices") ?? []

            if list.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("No Trusted Devices")
                        .font(.headline)
                    Text("Check 'Trust this device' when receiving a transfer to add it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 8) {
                    ForEach(list, id: \.self) { devKey in
                        let displayName = devKey.contains("|") ? String(devKey.split(separator: "|").last ?? "") : devKey
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .font(.title3)
                                .foregroundStyle(theme.currentAccent.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName)
                                    .font(.subheadline.weight(.medium))
                                Text("Auto-accept enabled")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Button("Remove") {
                                removeTrusted(devKey)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack {
                        Spacer()
                        Button("Clear All Trusted Devices") {
                            UserDefaults.standard.set([], forKey: "trustedDevices")
                            model.trustedDevices.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .controlSize(.small)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - How to Use Tab
    private var guideTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(title: "Quick Start Guide", subtitle: "Everything you need to know about sharing with NearByDrop.")

            VStack(spacing: 12) {
                guideCard(
                    title: "Receiving Files from Android or Windows",
                    steps: [
                        "1. Open Quick Share on your Android phone, tablet, or Windows PC.",
                        "2. Select the photos, videos, documents, or folders you wish to share.",
                        "3. Select '\(model.deviceName)' from the list of nearby devices.",
                        "4. Check the PIN code shown on your Mac and click Accept."
                    ],
                    icon: "arrow.down.circle.fill",
                    color: .green
                )

                guideCard(
                    title: "Sending Files from your Mac",
                    steps: [
                        "1. Drag and drop any files or directories onto the NearByDrop popover or window.",
                        "2. Choose your phone from the 'Nearby Devices' list.",
                        "3. Accept the incoming transfer prompt on your phone."
                    ],
                    icon: "arrow.up.circle.fill",
                    color: theme.currentAccent.color
                )

                guideCard(
                    title: "QR Code Fallback Pairing",
                    steps: [
                        "• When devices are on different subnets or Wi-Fi discovery is blocked:",
                        "• On phone: Tap the QR code icon in Quick Share.",
                        "• On Mac: Click 'Scan QR' in NearByDrop and point your camera at the phone's screen."
                    ],
                    icon: "qrcode.viewfinder",
                    color: .orange
                )

                guideCard(
                    title: "Wired USB Transfer (MTP Mode)",
                    steps: [
                        "• Plug your Android phone into your Mac via a USB cable.",
                        "• On the phone: Select 'File Transfer / Android Auto' under USB settings.",
                        "• In NearByDrop: Switch to the 'USB' tab to browse internal storage directly."
                    ],
                    icon: "cable.connector",
                    color: .purple
                )
            }

            Button("Replay Welcome Tour…") {
                OnboardingWindowController.showOnboarding()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 6)
        }
    }

    // MARK: - Privacy & Security Tab
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Privacy & Security Policy", subtitle: "NearByDrop is built with absolute user privacy as its core foundation.")

            VStack(alignment: .leading, spacing: 14) {
                privacyPoint(
                    icon: "network.badge.shield.half.filled",
                    title: "100% Peer-to-Peer Architecture",
                    text: "Files and metadata are transferred directly over your local Wi-Fi or USB connection. Data never passes through Google, Apple, or any proxy server."
                )

                Divider()

                privacyPoint(
                    icon: "key.horizontal.fill",
                    title: "End-to-End Cryptography",
                    text: "Every wireless transfer session is protected with UKEY2 elliptic curve Diffie-Hellman (P-256) key exchange, AES-256-CBC payload encryption, and HMAC-SHA256 authentication."
                )

                Divider()

                privacyPoint(
                    icon: "camera.fill",
                    title: "Camera Usage Transparency",
                    text: "Camera access is used solely in real-time when the QR scanner is open. Frames are processed in-memory using Apple Vision and are never recorded, cached, or transmitted."
                )

                Divider()

                privacyPoint(
                    icon: "chart.bar.xaxis",
                    title: "Zero Analytics or Telemetry",
                    text: "NearByDrop contains no analytics, crash reporters, telemetry SDKs, or cloud accounts. We collect absolutely zero information about your device or transfers."
                )
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Open macOS Privacy & Security Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(theme.currentAccent.color.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(theme.currentAccent.color)
            }

            VStack(spacing: 4) {
                Text("NearByDrop")
                    .font(.title.weight(.bold))
                Text("Version 1.0.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Created by Arslan Basharat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Open Source Attribution & Licenses")
                    .font(.headline)

                Text("• Built upon the foundational reverse-engineered Nearby Share protocol from Grishka's open-source NearDrop project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("• USB transfer component bundles libmtp and libusb dynamic libraries under LGPL v2.1/v3. License files and rebuild instructions are located in Vendor/USB/licenses/.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("• Dependencies: SwiftECC, swift-protobuf, and QRCode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button("View on GitHub") {
                    if let url = URL(string: "https://github.com/arslanbasharat/NearByDrop") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.currentAccent.color)

                Button("Open Downloads") {
                    TransferModel.openDownloads()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func guideCard(title: String, steps: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(steps, id: \.self) { step in
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func privacyPoint(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(theme.currentAccent.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func removeTrusted(_ key: String) {
        var list = UserDefaults.standard.stringArray(forKey: "trustedDevices") ?? []
        list.removeAll { $0 == key }
        UserDefaults.standard.set(list, forKey: "trustedDevices")
        model.trustedDevices.remove(key)
    }
}
