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
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
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

    required init?(coder: NSCoder) { return nil }

    func show(tab: SettingsTab? = nil) {
        if let tab = tab {
            selectedTab = tab
        }
        window?.positionOnInteractionScreen()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general = "General"
    case appearance = "Appearance"
    case devices = "Devices"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .devices: return "iphone.and.arrow.forward"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {

    @ObservedObject var model: TransferModel
    @ObservedObject var controller: SettingsWindowController
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var feedback = FeedbackManager.shared
    @State private var customName: String = ""
    @State private var usageAnalyticsEnabled = UsageAnalytics.isEnabled

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
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(
                            controller.selectedTab == tab ? theme.currentAccent.color.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.regular)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(width: 195)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch controller.selectedTab {
                    case .general: generalTab
                    case .appearance: appearanceTab
                    case .devices: devicesTab
                    case .about: aboutTab
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 660, height: 500)
        .onAppear {
            customName = UserDefaults.standard.string(forKey: "customDeviceName") ?? model.deviceName
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Device Name", subtitle: "Name shown to nearby devices.")
            HStack {
                TextField("Device Name", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .onSubmit {
                        NearbyConnectionManager.customDeviceName = customName.isEmpty ? nil : customName
                    }
                Button("Save") {
                    NearbyConnectionManager.customDeviceName = customName.isEmpty ? nil : customName
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.currentAccent.color)
                .controlSize(.small)

                Button("Reset") {
                    customName = Host.current().localizedName ?? "This Mac"
                    NearbyConnectionManager.customDeviceName = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Downloads", subtitle: "Folder for received files.")
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(theme.currentAccent.color)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 1) {
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
                    model.chooseDownloadDirectory(relativeTo: controller.window)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.currentAccent.color)
                .controlSize(.small)

                Button("Open") {
                    TransferModel.openDownloads()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Diagnostics", subtitle: "Help improve compatibility across Macs and phones.")
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Send diagnostic reports", isOn: $usageAnalyticsEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: usageAnalyticsEnabled) { _, enabled in
                        UsageAnalytics.setEnabled(enabled)
                    }
                Text(UsageAnalytics.endpointIsConfigured
                     ? "On by default. Sends app and macOS versions, Mac hardware model, this Mac’s name, and nearby device name and type after successful wireless transfers. No file names or contents."
                     : "On by default. Sends app and macOS versions, Mac hardware model, this Mac’s name, and nearby device name and type after successful wireless transfers once the dashboard is configured. No file names or contents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Timing and installation details") {
                    Text("Reports include first launch and app opens, using a random installation ID and hour-rounded timestamps. Turn reports off anytime here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.caption.weight(.medium))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Options", subtitle: "System startup preferences.")
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.toggleLaunchAtLogin(enabled: $0) }
                ))
                .toggleStyle(.checkbox)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Feedback", subtitle: "Transfer status appears in the menu bar dropdown.")
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Play Sound Effects", isOn: $feedback.soundEnabled)
                    .toggleStyle(.checkbox)

                Toggle("Trackpad Vibration (Haptics)", isOn: $feedback.hapticsEnabled)
                    .toggleStyle(.checkbox)


            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Appearance Tab
    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Theme", subtitle: "Choose light, dark, or system appearance.")
            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { t in
                    Button {
                        theme.currentTheme = t
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: t.icon)
                                .font(.system(size: 22))
                                .foregroundStyle(theme.currentTheme == t ? theme.currentAccent.color : .secondary)
                            Text(t.rawValue)
                                .font(.caption.weight(theme.currentTheme == t ? .bold : .regular))
                        }
                        .frame(width: 86, height: 68)
                        .background(
                            theme.currentTheme == t ? theme.currentAccent.color.opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(theme.currentTheme == t ? theme.currentAccent.color : Color.primary.opacity(0.08), lineWidth: theme.currentTheme == t ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(t.rawValue)
                    .accessibilityValue(theme.currentTheme == t ? "Selected" : "Not selected")
                }
            }

            sectionHeader(title: "Accent Color", subtitle: "Highlight color for buttons and controls.")
            HStack(spacing: 10) {
                ForEach(AccentOption.allCases) { opt in
                    Button {
                        theme.currentAccent = opt
                    } label: {
                        Circle()
                            .fill(opt.color)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(theme.currentAccent == opt ? 0.8 : 0.15), lineWidth: theme.currentAccent == opt ? 2.5 : 1)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .opacity(theme.currentAccent == opt ? 1 : 0)
                            )
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .help(opt.rawValue)
                    .accessibilityLabel(opt.rawValue)
                    .accessibilityValue(theme.currentAccent == opt ? "Selected" : "Not selected")
                }
            }

            sectionHeader(title: "Menu Bar Icon", subtitle: "Icon shown in your macOS menu bar.")
            HStack(spacing: 12) {
                ForEach(MenuBarIconStyle.allCases) { style in
                    Button {
                        theme.menuBarIconStyle = style
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: style.sfSymbol)
                                .font(.system(size: 14))
                            Text(style.rawValue)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            theme.menuBarIconStyle == style ? theme.currentAccent.color.opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.menuBarIconStyle == style ? theme.currentAccent.color : Color.primary.opacity(0.08), lineWidth: theme.menuBarIconStyle == style ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(style.rawValue)
                    .accessibilityValue(theme.menuBarIconStyle == style ? "Selected" : "Not selected")
                }
            }
        }
    }

    // MARK: - Devices Tab (Trusted Devices)
    private var devicesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Trusted Devices", subtitle: "Transfers from these devices are accepted automatically.")

            let list = Array(Set(UserDefaults.standard.stringArray(forKey: "trustedDevices") ?? [])).sorted()
            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No Trusted Devices")
                        .font(.headline)
                    Text("Transfers from trusted devices are accepted automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(spacing: 6) {
                    ForEach(list, id: \.self) { key in
                        let parts = key.split(separator: "#", omittingEmptySubsequences: false)
                        let displayName = parts.count > 1 ? parts.dropLast().joined(separator: "#") : (key.contains("|") ? String(key.split(separator: "|", maxSplits: 1).last ?? "") : key)
                        let identitySuffix = parts.count > 1 ? String(parts.last ?? "").suffix(6) : nil
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(theme.currentAccent.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName)
                                    .font(.subheadline)
                                if let identitySuffix, !identitySuffix.isEmpty {
                                    Text("Connection ID · …\(identitySuffix)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                removeTrusted(key)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Remove trust for \(displayName)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack {
                        Spacer()
                        Button("Revoke All", role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: "trustedDevices")
                            model.trustedDevices.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(theme.currentAccent.color.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(theme.currentAccent.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nearby Drop")
                        .font(.title2.weight(.bold))
                    Text(AppRelease.versionDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("By Arslan Basharat")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(title: "Updates", subtitle: "Keep Nearby Drop up to date.")
                HStack(alignment: .top, spacing: 12) {
                    Button("Check for Updates") { AppUpdater.shared.check() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    AppUpdateView()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What’s New").font(.subheadline.weight(.semibold))
                Text("Inline QR scanning, improved Quick Share handshakes, and safer transfer cancellation.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Text("Open Source Licenses")
                    .font(.subheadline.weight(.semibold))

                Text("libmtp and libusb are distributed under LGPL 2.1 or later. Licenses and matching USB source are included with each release.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 12) {
                Button("View on GitHub") {
                    if let url = URL(string: "https://github.com/arslanbasharat-o-o/NearByDrop") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.currentAccent.color)



                Button("Welcome Tour…") {
                    OnboardingWindowController.showOnboarding()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func removeTrusted(_ key: String) {
        var list = UserDefaults.standard.stringArray(forKey: "trustedDevices") ?? []
        list.removeAll { $0 == key }
        UserDefaults.standard.set(list, forKey: "trustedDevices")
        model.trustedDevices.remove(key)
    }
}
