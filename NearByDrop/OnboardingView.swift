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
            contentRect: NSRect(origin: .zero, size: NearbyWindowMetrics.onboardingContentSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Nearby Drop"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NearByDropOnboardingV2")
        window.setContentSize(NearbyWindowMetrics.onboardingContentSize)
        window.contentMinSize = NearbyWindowMetrics.onboardingMinimumContentSize
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
        if acceptedDiagnostics {
            UserDefaults.standard.set(true, forKey: "diagnosticsDisclosureSeen")
            UsageAnalytics.start()
            UsageAnalytics.recordOperational(.onboardingCompleted)
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
    @State private var currentStep = 0
    @State private var cameraAllowed: Bool = false
    @State private var isPreview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stepCount = 7

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

#if DEBUG
    init(onFinish: @escaping () -> Void, previewStep: Int) {
        self.onFinish = onFinish
        _currentStep = State(initialValue: min(max(previewStep, 0), 6))
        _isPreview = State(initialValue: true)
    }
#endif

    private var stepTitle: String {
        ["Welcome to Nearby Drop", "Send to Android", "Receive on Your Mac", "Pair with QR", "Connect with USB", "Make It Yours", "Privacy and Diagnostics"][currentStep]
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Nearby Drop")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                HStack {
                    Spacer()
                    Text("\(currentStep + 1) of \(stepCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 42)
            .padding(.top, 14)
            .padding(.bottom, 11)
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text(stepTitle)
                    .font(NearbyTypography.pageTitle)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    stepContent.frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, 42)
            .padding(.top, 24)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { currentStep -= 1 }
                    }
                    .buttonStyle(.nearbySecondary)
                    .keyboardShortcut(.cancelAction)
                } else {
                    Color.clear
                        .frame(width: 56, height: 1)
                        .accessibilityHidden(true)
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Capsule()
                            .fill(index == currentStep ? theme.presentationAccent : Color.primary.opacity(0.12))
                            .frame(width: index == currentStep ? 22 : 7, height: 5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Onboarding progress")
                .accessibilityValue("Step \(currentStep + 1) of \(stepCount)")
                Spacer()
                if currentStep < stepCount - 1 {
                    Button("Skip to Privacy") { currentStep = stepCount - 1 }.buttonStyle(.nearbyQuiet)
                }
                Button(footerActionTitle) {
                    if currentStep == stepCount - 1 {
                        onFinish()
                    } else {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { currentStep += 1 }
                    }
                }
                .buttonStyle(.nearbyPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 12)
        }
        .frame(
            minWidth: NearbyWindowMetrics.onboardingMinimumContentSize.width,
            minHeight: NearbyWindowMetrics.onboardingMinimumContentSize.height,
            alignment: .topLeading
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nearbyThemedWindow()
        .onAppear {
            checkPermissions()
        }
    }

    private var footerActionTitle: String {
        switch currentStep {
        case 6: return "Get Started"
        default: return "Continue"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            welcomeIllustration
            Text("Quick Share between your Mac and compatible Android or Windows clients, plus Android USB file management.")
                .foregroundStyle(theme.secondaryText)
        case 1:
            onboardingMethodCard(icon: "paperplane", title: "Choose files, then a nearby receiver")
            Text("Open Quick Share on the receiving device and make it discoverable. Choose files in Send, select the device, and confirm the transfer there. Both devices need a reachable local network.")
                .foregroundStyle(theme.secondaryText)
        case 2:
            onboardingMethodCard(icon: "arrow.down.circle", title: "Stay visible, stay in control")
            Text("Keep receiving enabled on your Mac. Select this Mac in Quick Share on the other device. Review the incoming request and accept or decline it. Favorites never bypass approval.")
                .foregroundStyle(theme.secondaryText)
        case 3: cameraPermissionContent
        case 4:
            wirelessAndUSBContent
            Text("Use a data cable, unlock the phone, and choose File transfer / Android Auto on Android. Open USB in Nearby Drop to browse, upload, or download. USB is a separate workflow; it does not resume an interrupted wireless transfer.")
                .foregroundStyle(theme.secondaryText)
        case 5:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                ForEach(AppTheme.allCases) { appearance in
                    Button { theme.currentTheme = appearance } label: {
                        VStack(spacing: 8) {
                            Image(systemName: appearance.icon).font(.title2)
                            Text(appearance.rawValue)
                            if theme.resolvedTheme == appearance { Image(systemName: "checkmark.circle.fill") }
                        }.frame(maxWidth: .infinity, minHeight: 85).padding(8)
                            .foregroundStyle(theme.resolvedTheme == appearance ? theme.presentationAccent : theme.primaryText)
                            .nearbyCardSurface()
                            .background { NearbyThemeArtwork(appearance: appearance) }
                    }.buttonStyle(.plain).nearbyCardFocus().accessibilityValue(theme.resolvedTheme == appearance ? "Selected" : "Not selected")
                }
            }
            Text("You can change appearance anytime in Settings.").foregroundStyle(theme.secondaryText)
        default: diagnosticsCard
        }
    }

    private var welcomeIllustration: some View {
        VStack(spacing: 22) {
            VStack(spacing: 15) {
                HStack(spacing: 8) {
                    Text("Finder   File   Edit   View")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(theme.presentationAccent)
                        .padding(3)
                        .background(theme.presentationAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Image(systemName: "wifi")
                        .foregroundStyle(theme.secondaryText)
                    Text("10:42").font(.system(size: 9)).foregroundStyle(theme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .nearbyControlSurface(cornerRadius: 8)

                HStack(spacing: 22) {
                    illustrationDevice(icon: "arrow.up.arrow.down", name: "Your Mac", width: 132, showsUnderline: true)
                    HStack(spacing: 3) {
                        Text("•••")
                        Image(systemName: "arrow.left.arrow.right")
                        Text("•••")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.presentationAccent)
                    illustrationDevice(icon: "iphone", name: "Android", width: 50)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .padding(18)
            .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        }
    }

    private func illustrationDevice(icon: String, name: String, width: CGFloat, showsUnderline: Bool = false) -> some View {
        VStack(spacing: 7) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(theme.presentationAccent)
                    .frame(width: width, height: 80)
                    .nearbyControlSurface(cornerRadius: 8)
                    .overlay {
                        if icon == "iphone" {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(theme.presentationAccent)
                                .offset(y: 1)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                if showsUnderline {
                    Capsule().fill(theme.presentationAccent.opacity(0.35)).frame(width: width, height: 4)
                }
            }
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var wirelessAndUSBContent: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                onboardingMethodCard(
                    icon: "wifi",
                    title: "Wireless"
                )
                onboardingMethodCard(
                    icon: "cable.connector",
                    title: "USB"
                )
            }

        }
    }

    private func onboardingMethodCard(icon: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.presentationAccent)
                .frame(width: 38, height: 38)
                .background(theme.presentationAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(12)
        .nearbyCardSurface(cornerRadius: 11)
    }

    private var cameraPermissionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(theme.presentationAccent)
                    .frame(width: 72, height: 72)
                    .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Camera access")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Used only to scan pairing QR codes. Images are not saved or sent.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .nearbyCardSurface(cornerRadius: 11)

            cameraPermissionAction
                .frame(maxWidth: .infinity)

            Text("Optional. Nearby discovery and USB work without camera access. Change access in System Settings.")
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("To send, create a pairing QR in Send. To receive, scan a supported Android-generated Quick Share QR. QR pairing still needs a compatible network connection.")
                .font(NearbyTypography.supporting).foregroundStyle(theme.secondaryText)
        }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Automatic diagnostic reports").font(NearbyTypography.prominentBody)

            Text("This build sends reports automatically after setup. There is no in-app switch. Reports include app and macOS versions, Mac hardware model, this Mac’s name, and nearby device name and type after successful wireless transfers. No file names or contents.")
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Timing and installation details") {
                Text("Reports also record first launch and app opens, using a random installation ID and hour-rounded timestamps. Operational reports add transfer starts/outcomes, retries, USB operations, error categories, bucketed sizes/counts/timings and queue depth, with minute-rounded timestamps. Reports are retained for 90 days; up to 200 pending reports can remain on this Mac for seven days.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            }
            .font(.system(size: 10, weight: .medium))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nearbyCardSurface(cornerRadius: 11)
    }

    @ViewBuilder
    private var cameraPermissionAction: some View {
        if isPreview {
            Button {
            } label: {
                Label(cameraAllowed ? "Camera is enabled" : "Enable camera…", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.nearbyPrimary)
                .disabled(cameraAllowed)
        } else if cameraAllowed {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.successColor)
                .accessibilityLabel("Camera access allowed")
        } else if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            Button(action: requestCamera) {
                Label("Allow Camera…", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(.nearbySecondary)
        } else if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
            Button("Open Camera Settings") {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.nearbySecondary)
        } else {
            EmptyView()
        }
    }

    private func checkPermissions() {
        guard !isPreview else { return }
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

#if DEBUG
#Preview("Onboarding · Welcome") {
    FigmaCanvasPreview { OnboardingView(onFinish: {}, previewStep: 0) }
}
#Preview("Onboarding · Wireless and USB") {
    FigmaCanvasPreview { OnboardingView(onFinish: {}, previewStep: 1) }
}
#Preview("Onboarding · Camera permission") {
    FigmaCanvasPreview { OnboardingView(onFinish: {}, previewStep: 2) }
}
#endif
