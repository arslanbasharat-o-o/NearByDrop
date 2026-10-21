import Cocoa
import SwiftUI
import UserNotifications
import AVFoundation

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static var current: OnboardingWindowController?

    let onFinished: () -> Void
    private var hasFinished = false

    static func showOnboarding(onFinished: @escaping () -> Void = {}) {
        if let existing = current {
            existing.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = OnboardingWindowController(onFinished: onFinished)
        current = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to NearByDrop"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in
            self?.finish()
        }))
    }

    required init?(coder: NSCoder) { fatalError() }

    func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        window?.orderOut(nil)
        close()
        OnboardingWindowController.current = nil
        onFinished()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @State private var currentStep = 0
    @State private var notificationsAllowed: Bool = false
    @State private var cameraAllowed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header / Step progress
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentStep ? theme.currentAccent.color : Color.secondary.opacity(0.3))
                            .frame(width: idx == currentStep ? 8 : 6, height: idx == currentStep ? 8 : 6)
                            .animation(.easeInOut(duration: 0.2), value: currentStep)
                    }
                }
                Spacer()
                if currentStep < 3 {
                    Button("Skip") {
                        onFinish()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            // Content Area
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: stepsGuideStep
                case 2: permissionsStep
                case 3: privacyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)

            Divider()

            // Footer controls
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()

                if currentStep < 3 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.regular)
                } else {
                    Button("Get Started") {
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
        }
        .frame(width: 620, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            checkPermissions()
        }
    }

    // Step 0: Welcome
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(theme.currentAccent.color.opacity(0.15))
                    .frame(width: 90, height: 90)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(theme.currentAccent.color)
            }

            VStack(spacing: 8) {
                Text("Welcome to NearByDrop")
                    .font(.system(size: 26, weight: .bold))
                Text("Seamless Quick Share & AirDrop parity for macOS.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureRow(icon: "bolt.fill", title: "Direct Peer-to-Peer", subtitle: "Transfer photos, videos, and large folders at maximum Wi-Fi speed.")
                featureRow(icon: "lock.shield.fill", title: "100% Offline & Private", subtitle: "End-to-end encrypted with UKEY2 and AES-256. Zero cloud uploads.")
                featureRow(icon: "cable.connector", title: "Wired USB Fallback", subtitle: "Transfer directly over a USB cable using built-in MTP file browsing.")
            }
            .padding(.top, 12)

            Spacer()
        }
    }

    // Step 1: How to Use
    private var stepsGuideStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How to Use NearByDrop")
                    .font(.title2.weight(.bold))
                Text("Follow these simple steps to share files with any device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            VStack(spacing: 12) {
                stepCard(
                    number: "1",
                    title: "Receiving from Android or PC",
                    description: "Open Quick Share on your phone or PC, pick your files, and tap 'This Mac'. Confirm the PIN code on your Mac to accept.",
                    icon: "arrow.down.circle.fill",
                    color: .green
                )

                stepCard(
                    number: "2",
                    title: "Sending to Nearby Devices",
                    description: "Drag and drop any files or folders onto the NearByDrop menu bar icon or window, then tap your device in the Nearby Devices list.",
                    icon: "arrow.up.circle.fill",
                    color: theme.currentAccent.color
                )

                stepCard(
                    number: "3",
                    title: "QR Code & USB Wired Mode",
                    description: "Use the Camera QR scanner when devices are on separate networks, or plug in a USB cable to browse Android storage directly.",
                    icon: "qrcode.viewfinder",
                    color: .orange
                )
            }

            Spacer()
        }
    }

    // Step 2: Permissions
    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Permissions")
                    .font(.title2.weight(.bold))
                Text("NearByDrop needs the following permissions to function smoothly:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            VStack(spacing: 14) {
                // Notifications
                HStack(spacing: 14) {
                    Image(systemName: "bell.badge.fill")
                        .font(.title)
                        .foregroundStyle(notificationsAllowed ? Color.green : theme.currentAccent.color)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications")
                            .font(.headline)
                        Text("Alerts you of incoming transfers and displays pairing PIN codes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if notificationsAllowed {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow") {
                            requestNotifications()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.currentAccent.color)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                // Camera
                HStack(spacing: 14) {
                    Image(systemName: "camera.fill")
                        .font(.title)
                        .foregroundStyle(cameraAllowed ? Color.green : theme.currentAccent.color)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Camera Access")
                            .font(.headline)
                        Text("Required only when using the built-in Quick Share QR code scanner.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if cameraAllowed {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow") {
                            requestCamera()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.currentAccent.color)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

                // Local Network
                HStack(spacing: 14) {
                    Image(systemName: "network")
                        .font(.title)
                        .foregroundStyle(.green)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Network (Bonjour / mDNS)")
                            .font(.headline)
                        Text("Discovers and advertises with nearby devices on your Wi-Fi network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
    }

    // Step 3: Privacy
    private var privacyStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hand.raised.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(theme.currentAccent.color)

            VStack(spacing: 6) {
                Text("Your Privacy is Absolute")
                    .font(.title2.weight(.bold))
                Text("NearByDrop is engineered with zero telemetry and zero cloud dependencies.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                privacyItem(icon: "server.rack", text: "No Cloud Servers: Transfers travel directly between your Mac and phone.")
                privacyItem(icon: "person.crop.circle.badge.xmark", text: "No Accounts: No Google or third-party login required.")
                privacyItem(icon: "key.fill", text: "End-to-End Encrypted: Every packet is authenticated with UKEY2 / AES-256.")
                privacyItem(icon: "chevron.left.forwardslash.chevron.right", text: "Open Source: Fully auditable public code on GitHub.")
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(theme.currentAccent.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepCard(number: String, title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func privacyItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(theme.currentAccent.color)
                .frame(width: 20)
            Text(text)
                .font(.callout)
        }
    }

    private func checkPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsAllowed = (settings.authorizationStatus == .authorized)
            }
        }
        cameraAllowed = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.notificationsAllowed = granted
            }
        }
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraAllowed = granted
            }
        }
    }
}
