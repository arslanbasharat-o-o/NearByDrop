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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
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
    @State private var cameraAllowed: Bool = false

    var body: some View {
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
        .frame(width: 480, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            checkPermissions()
        }
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
