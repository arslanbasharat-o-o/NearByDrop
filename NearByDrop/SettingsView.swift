import Cocoa
import SwiftUI
import ServiceManagement
import NearbyShare
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, ObservableObject {
    let model: TransferModel
    @Published var selectedTab: SettingsTab = .general

    init(model: TransferModel, createWindow: Bool = true) {
        self.model = model
        let window: NSWindow?
        if createWindow {
            let settingsWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: NearbyWindowMetrics.settingsContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "Nearby Drop Settings"
            settingsWindow.titleVisibility = .visible
            settingsWindow.titlebarAppearsTransparent = false
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.setFrameAutosaveName("NearByDropSettingsV2")
            settingsWindow.setContentSize(NearbyWindowMetrics.settingsContentSize)
            settingsWindow.contentMinSize = NearbyWindowMetrics.settingsMinimumContentSize
            settingsWindow.backgroundColor = .windowBackgroundColor
            settingsWindow.center()
            window = settingsWindow
        } else {
            window = nil
        }
        super.init(window: window)
        window?.contentView = NSHostingView(rootView: SettingsView(model: model, controller: self))
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

private struct DiagnosticsReportPreview: View {
    let report: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview Diagnostics Report")
                .font(.title3.weight(.semibold))
             Text("Review a redacted report before saving it locally.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.nearbySecondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Report…", action: onSave)
                    .buttonStyle(.nearbyPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general = "General"
    case appearance = "Appearance"
    case about = "About"

    var id: String { rawValue }

    var pageTitle: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .about: return "About Nearby Drop"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {

    @ObservedObject var model: TransferModel
    @ObservedObject var controller: SettingsWindowController
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var feedback = FeedbackManager.shared
    @ObservedObject private var updater = AppUpdater.shared
    @State private var customName: String = ""
    @State private var usageAnalyticsEnabled = PreviewRuntime.isSwiftUIPreviews || UsageAnalytics.isEnabled
    @State private var showingDiagnosticsPreview = false
    @State private var diagnosticsReport = ""
    @State private var diagnosticsSaveError: String?

    var body: some View {
        HStack(spacing: 0) {
            navigationSidebar
            Divider()
            VStack(spacing: 0) {
                settingsHeader
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch controller.selectedTab {
                        case .general: generalTab
                        case .appearance: appearanceTab
                        case .about: aboutTab
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(
            minWidth: NearbyWindowMetrics.settingsMinimumContentSize.width,
            minHeight: NearbyWindowMetrics.settingsMinimumContentSize.height
        )
        .sheet(isPresented: $showingDiagnosticsPreview) {
            DiagnosticsReportPreview(report: diagnosticsReport, onSave: saveDiagnosticsReport)
                .frame(
                    minWidth: NearbyWindowMetrics.diagnosticsPreviewMinimumSize.width,
                    idealWidth: NearbyWindowMetrics.diagnosticsPreviewIdealSize.width,
                    minHeight: NearbyWindowMetrics.diagnosticsPreviewMinimumSize.height,
                    idealHeight: NearbyWindowMetrics.diagnosticsPreviewIdealSize.height
                )
        }
        .alert("Could Not Save Report", isPresented: Binding(
            get: { diagnosticsSaveError != nil },
            set: { if !$0 { diagnosticsSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { diagnosticsSaveError = nil }
        } message: {
            Text(diagnosticsSaveError ?? "Choose another location and try again.")
        }
        .onAppear {
            customName = model.deviceName
        }
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = controller.selectedTab == tab
                Button {
                    controller.selectedTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? theme.presentationAccent : Color.primary.opacity(0.78))
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .padding(.horizontal, 11)
                        .background(
                            isSelected ? theme.presentationAccent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tab.rawValue)
                .accessibilityLabel("\(tab.rawValue) settings")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 20)
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var settingsHeader: some View {
        Text(controller.selectedTab.pageTitle)
            .font(NearbyTypography.pageTitle)
            .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Device name")
                    .font(.system(size: 12, weight: .medium))
                TextField("Alex’s MacBook Pro", text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveCustomDeviceName)
                    .help("Press Return to save. Clear to use the Mac’s name.")
            }

            VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Download location")
                                .font(NearbyTypography.body.weight(.medium))
                            Text(model.downloadDirectoryDisplayPath)
                                .font(NearbyTypography.metadata)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Button("Change…") {
                            model.chooseDownloadDirectory(relativeTo: controller.window)
                        }
                        .buttonStyle(.nearbyCompactSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    settingsDivider

                    settingsRow(
                        title: "Launch at login"
                    ) {
                        Toggle("Launch at login", isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.toggleLaunchAtLogin(enabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(theme.presentationAccent)
                        .disabled(!model.canManageLaunchAtLogin && !PreviewRuntime.isSwiftUIPreviews)
                        .accessibilityLabel("Launch at login")
                    }

                    settingsDivider

                    settingsRow(
                        title: "Play transfer sounds",
                        subtitle: "Play a sound when a transfer finishes."
                    ) {
                        Toggle("Play transfer sounds", isOn: $feedback.soundEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.presentationAccent)
                            .accessibilityLabel("Play transfer sounds")
                    }

                    settingsDivider

                    settingsRow(
                        title: "Trackpad vibration",
                        subtitle: "Vibrate on supported trackpads."
                    ) {
                        Toggle("Trackpad vibration", isOn: $feedback.hapticsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.presentationAccent)
                            .accessibilityLabel("Trackpad vibration")
                    }
                }
            .nearbyCardSurface(cornerRadius: 12)

            if let message = model.launchAtLoginMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingsSection("Diagnostics & troubleshooting") {
                VStack(spacing: 0) {
                    settingsRow(
                        title: "Share diagnostics",
                         subtitle: "Share limited device and transfer diagnostics. No file names or contents are sent."
                    ) {
                        Toggle("Share diagnostics", isOn: $usageAnalyticsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.presentationAccent)
                            .accessibilityLabel("Share diagnostics")
                            .onChange(of: usageAnalyticsEnabled) { _, enabled in
                                UsageAnalytics.setEnabled(enabled)
                            }
                    }

                    settingsDivider

                    settingsRow(
                        title: "Local diagnostic report",
                        subtitle: "Create a local report to share with support."
                    ) {
                        Button("Export…", action: prepareDiagnosticsPreview)
                            .buttonStyle(.nearbySecondary)
                    }
                }
            }

        }
    }

    private func saveCustomDeviceName() {
        NearbyConnectionManager.customDeviceName = customName.isEmpty ? nil : customName
    }

    private func resetCustomDeviceName() {
        customName = Host.current().localizedName ?? "This Mac"
        NearbyConnectionManager.customDeviceName = nil
    }

    private func prepareDiagnosticsPreview() {
        do {
            diagnosticsReport = try DiagnosticsReportBuilder.makeJSON(from: model.diagnosticsReportSnapshot)
            showingDiagnosticsPreview = true
        } catch {
            diagnosticsSaveError = error.localizedDescription
        }
    }

    private func saveDiagnosticsReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Nearby Drop Diagnostics.json"
        panel.title = "Export Diagnostics Report"
        panel.prompt = "Save Report"
        panel.message = "Saving creates a local file. Nearby Drop will not send this report."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                _ = try DiagnosticsReportBuilder.write(diagnosticsReport, to: url)
                showingDiagnosticsPreview = false
            } catch {
                diagnosticsSaveError = error.localizedDescription
            }
        }
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Appearance") {
                HStack(spacing: 9) {
                    ForEach(AppTheme.allCases) { option in
                        appearanceThemeCard(option)
                    }
                }
                .padding(12)

                settingsDivider

                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent color")
                        .font(NearbyTypography.body.weight(.medium))
                    HStack(spacing: 7) {
                        ForEach([AccentOption.blue, .purple, .green, .orange, .pink, .graphite]) { option in
                            let isSelected = theme.presentationAccentOption == option
                            Button {
                                theme.currentAccent = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle().stroke(.white.opacity(0.95), lineWidth: isSelected ? 2 : 0)
                                    }
                                    .overlay {
                                        Circle().stroke(option.color.opacity(isSelected ? 0 : 0.28), lineWidth: 1)
                                    }
                                    .overlay {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .opacity(isSelected ? 1 : 0)
                                    }
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(option.rawValue)
                            .accessibilityLabel(option.rawValue)
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        }
                    }
                }
                .padding(12)

                settingsDivider

                VStack(alignment: .leading, spacing: 8) {
                    Text("Menu bar icon")
                        .font(NearbyTypography.body.weight(.medium))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            let isSelected = theme.menuBarIconStyle == style
                            Button {
                                theme.menuBarIconStyle = style
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: style.sfSymbol)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(isSelected ? theme.presentationAccent : Color.secondary)
                                    Text(style.displayName)
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? theme.presentationAccent : Color.primary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(isSelected ? theme.presentationAccent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isSelected ? theme.presentationAccent.opacity(0.65) : Color.primary.opacity(0.10), lineWidth: 1))
                                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(style.displayName) menu bar icon")
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func appearanceThemeCard(_ option: AppTheme) -> some View {
        let isSelected = theme.currentTheme == option
        let isDark = option == .dark
        let surface = isDark ? Color(red: 0.15, green: 0.16, blue: 0.19) : Color.white
        let secondarySurface = isDark ? Color(red: 0.22, green: 0.23, blue: 0.27) : Color(red: 0.94, green: 0.94, blue: 0.97)
        return Button {
            theme.currentTheme = option
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                VStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Circle().fill(Color(red: 1, green: 0.38, blue: 0.35)).frame(width: 4, height: 4)
                        Circle().fill(Color(red: 1, green: 0.76, blue: 0.22)).frame(width: 4, height: 4)
                        Circle().fill(Color(red: 0.25, green: 0.78, blue: 0.35)).frame(width: 4, height: 4)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 5)
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(theme.presentationAccent.opacity(0.75)).frame(width: 18, height: 29)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(secondarySurface).frame(height: 6)
                            RoundedRectangle(cornerRadius: 2).fill(secondarySurface).frame(height: 6)
                            RoundedRectangle(cornerRadius: 2).fill(secondarySurface).frame(height: 6)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity)
                .background(surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                HStack(spacing: 4) {
                    Text(option.rawValue).font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    Spacer(minLength: 0)
                    if isSelected { Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(theme.presentationAccent) }
                }
                .foregroundStyle(isSelected ? theme.presentationAccent : Color.primary)
            }
            .padding(6)
            .background(isSelected ? theme.presentationAccent.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isSelected ? theme.presentationAccent : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.rawValue) appearance")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image("BrandLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nearby Drop").font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("\(AppRelease.versionDescription) · macOS")
                        .font(NearbyTypography.supporting).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Updates")
                        .font(NearbyTypography.sectionTitle)
                    Spacer(minLength: 8)
                    AppUpdateView()
                        .frame(maxWidth: 310)
                }
                .padding(12)

                settingsDivider

                settingsRow(
                    title: "Check for updates automatically",
                    subtitle: "Check in the background. You approve updates before installation."
                ) {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(theme.presentationAccent)
                    .accessibilityLabel("Check for updates automatically")
                }
            }
            .nearbyCardSurface(cornerRadius: 11)

            HStack(spacing: 16) {
                resourceLinkButton("GitHub repository", icon: "arrow.up.right", url: "https://github.com/arslanbasharat-o-o/NearByDrop")
                resourceLinkButton("Release notes", icon: "arrow.up.right", url: "https://github.com/arslanbasharat-o-o/NearByDrop/releases/latest")
            }
            .padding(.horizontal, 10)

            settingsSection("Resources & legal") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 7) {
                    resourceLinkButton("Privacy policy", icon: "arrow.up.right", url: "https://arslanbasharat-o-o.github.io/NearByDrop/legal/privacy.html")
                    resourceLinkButton("Security", icon: "arrow.up.right", url: "https://arslanbasharat-o-o.github.io/NearByDrop/legal/security.html")
                    resourceLinkButton("Terms of use · Draft", icon: "arrow.up.right", url: "https://arslanbasharat-o-o.github.io/NearByDrop/legal/terms.html")
                    resourceLinkButton("Open-source licenses", icon: "arrow.up.right", url: "https://arslanbasharat-o-o.github.io/NearByDrop/legal/licenses.html")
                    resourceLinkButton("Quick start guide", icon: "arrow.up.right", action: { OnboardingWindowController.showOnboarding() })
                    resourceLinkButton("Contact support", icon: "arrow.up.right", url: "https://github.com/arslanbasharat-o-o/NearByDrop/issues")
                }
                .padding(10)
            }

        }
    }

    private func resourceLinkButton(_ title: String, icon: String, url: String) -> some View {
        resourceLinkButton(title, icon: icon) {
            guard let destination = URL(string: url) else { return }
            NSWorkspace.shared.open(destination)
        }
    }

    private func resourceLinkButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: icon).font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(theme.presentationAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.nearbyCompactQuiet)
        .help(title)
    }

    private func openLinkButton(_ label: String, url: String) -> some View {
        Button {
            guard let destination = URL(string: url) else { return }
            NSWorkspace.shared.open(destination)
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.nearbyCompactQuiet)
        .help("Open \(label)")
        .accessibilityLabel("Open \(label)")
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(NearbyTypography.sectionTitle)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nearbyCardSurface(cornerRadius: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow<Accessory: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(NearbyTypography.supporting)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)
            accessory()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 12)
    }
}

#if DEBUG
#Preview("Settings · General") {
    let model = TransferModel.makePreviewFixture(tab: .receive)
    model.launchAtLogin = true
    FeedbackManager.shared.hapticsEnabled = false
    let controller = SettingsWindowController(model: model, createWindow: false)
    return FigmaCanvasPreview { SettingsView(model: model, controller: controller).frame(width: 820, height: 760) }
}
#Preview("Settings · Appearance") {
    let model = TransferModel.makePreviewFixture(tab: .receive)
    let controller = SettingsWindowController(model: model, createWindow: false)
    controller.selectedTab = .appearance
    return FigmaCanvasPreview { SettingsView(model: model, controller: controller).frame(width: 820, height: 760) }
}
#Preview("Settings · About") {
    let model = TransferModel.makePreviewFixture(tab: .receive)
    let controller = SettingsWindowController(model: model, createWindow: false)
    controller.selectedTab = .about
    return FigmaCanvasPreview { SettingsView(model: model, controller: controller).frame(width: 820, height: 760) }
}
#endif
