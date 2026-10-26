import Cocoa
import SwiftUI
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
        controller.window?.positionOnInteractionScreen()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 680),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Nearby Drop"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in
            self?.finish()
        }))
    }

    required init?(coder: NSCoder) { return nil }

    func finish(acceptedDiagnostics: Bool = true) {
        guard !hasFinished else { return }
        hasFinished = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        if acceptedDiagnostics && !UserDefaults.standard.bool(forKey: "diagnosticsDisclosureSeen") {
            UserDefaults.standard.set(true, forKey: "diagnosticsDisclosureSeen")
            UsageAnalytics.start()
        }
        window?.orderOut(nil)
        close()
        OnboardingWindowController.current = nil
        onFinished()
    }

    func windowWillClose(_ notification: Notification) {
        finish(acceptedDiagnostics: false)
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @State private var cameraAllowed: Bool = false
    @State private var shareUsageData = UsageAnalytics.isEnabled

    var body: some View {
        ScrollView {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.currentAccent.color.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(theme.currentAccent.color)
                }

                Text("Welcome to Nearby Drop")
                    .font(.title2.weight(.bold))

                Text("Send and receive files between Mac and Android.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            // Features list
            VStack(alignment: .leading, spacing: 12) {
                featureItem(
                    icon: "arrow.up.and.down.circle.fill",
                    color: theme.currentAccent.color,
                    title: "Wireless sharing",
                    text: "Choose a nearby device or scan a Quick Share code."
                )

                featureItem(
                    icon: "lock.shield.fill",
                    color: .green,
                    title: "Private transfers",
                    text: "Files are encrypted over local Wi-Fi. No account or cloud service is needed."
                )

                featureItem(
                    icon: "cable.connector",
                    color: .orange,
                    title: "USB transfers",
                    text: "Connect your phone by cable to browse and transfer files."
                )
            }
            .padding(.horizontal, 6)

            Divider()

            // Permissions
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(cameraAllowed ? Color.green : theme.currentAccent.color)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Camera")
                            .font(.subheadline.weight(.medium))
                        Text("For scanning Quick Share QR codes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if cameraAllowed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow", action: requestCamera)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 8)

            diagnosticsCard

            // Action
            Button(action: {
                onFinish()
            }) {
                Text("Get Started")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.currentAccent.color)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 22)
        }
        .frame(width: 500, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            checkPermissions()
        }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Send diagnostic reports", isOn: $shareUsageData)
                .onChange(of: shareUsageData) { _, enabled in
                    UsageAnalytics.setEnabled(enabled)
                }

            Text(UsageAnalytics.endpointIsConfigured
                 ? "On by default. Includes app and macOS versions, Mac hardware model, this Mac’s name, and nearby device name and type after successful wireless transfers. No file names or contents."
                 : "On by default. Reports start after the dashboard is configured. They include app and macOS versions, Mac hardware model, this Mac’s name, and nearby device name and type after successful wireless transfers. No file names or contents.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Timing and installation details") {
                Text("Reports also record first launch and app opens, using a random installation ID and hour-rounded timestamps. Turn reports off anytime in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .font(.caption.weight(.medium))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func featureItem(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkPermissions() {
        cameraAllowed = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
    }

    private func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraAllowed = granted
            }
        }
    }
}
