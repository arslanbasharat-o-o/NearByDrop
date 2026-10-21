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
                    .buttonStyle(.plain)
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
                    model.chooseDownloadDirectory()
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

            sectionHeader(title: "Options", subtitle: "System startup, menu bar, and Dock preferences.")
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Run as Menu Bar Only", isOn: $model.menuBarOnly)
                    .toggleStyle(.checkbox)
                Text("Operate NearByDrop directly from the menu bar without opening the main window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)

                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.toggleLaunchAtLogin(enabled: $0) }
                ))
                .toggleStyle(.checkbox)

                Toggle("Show NearByDrop in Dock", isOn: $theme.showInDock)
                    .toggleStyle(.checkbox)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            sectionHeader(title: "Feedback & Notifications", subtitle: "Audio artifacts, haptics, and transfer notifications.")
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Play Sound Effects", isOn: $feedback.soundEnabled)
                    .toggleStyle(.checkbox)

                Toggle("Trackpad Vibration (Haptics)", isOn: $feedback.hapticsEnabled)
                    .toggleStyle(.checkbox)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transfer Notifications")
                            .font(.subheadline)
                        Text("Show a sample transfer notification banner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Preview Notification") {
                        FeedbackManager.shared.vibrateClick()
                        TransferNotificationManager.shared.showPreview()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
                    .buttonStyle(.plain)
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
                    }
                    .buttonStyle(.plain)
                    .help(opt.rawValue)
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
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Devices Tab (Trusted Devices)
    private var devicesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Trusted Devices", subtitle: "Transfers from these devices are accepted automatically.")

            let list = UserDefaults.standard.stringArray(forKey: "trustedDevices") ?? []
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
                        let displayName = key.contains("|") ? String(key.split(separator: "|", maxSplits: 1).last ?? "") : key
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(theme.currentAccent.color)
                            Text(displayName)
                                .font(.subheadline)
                            Spacer()
                            Button("Remove") {
                                removeTrusted(key)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack {
                        Spacer()
                        Button("Revoke All") {
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
        VStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(theme.currentAccent.color.opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(theme.currentAccent.color)
            }

            VStack(spacing: 2) {
                Text("NearByDrop")
                    .font(.title2.weight(.bold))
                Text("Version 2.2.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Created by Arslan Basharat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Open Source Attribution")
                    .font(.subheadline.weight(.semibold))

                Text("• Built upon the Nearby Share protocol from Grishka's open-source NearDrop project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("• Bundles libmtp and libusb under LGPL v2.1/v3. Licenses and rebuild instructions located in Vendor/USB/licenses/.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button("View on GitHub") {
                    if let url = URL(string: "https://github.com/arslanbasharat/NearByDrop") {
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
        .frame(maxWidth: .infinity)
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
