import Cocoa
import SwiftUI
import NearbyShare

enum NotificationTransferState: Equatable {
    case incoming
    case receiving
    case completed(fileURL: URL?)
    case failed(message: String)
}

final class TransferNotificationItem: ObservableObject, Identifiable {
    let id: String
    let deviceName: String
    let deviceType: RemoteDeviceInfo.DeviceType
    let summary: String
    let pinCode: String?
    let fileURL: URL?
    var onConsent: ((Bool) -> Void)?
    var onTrust: ((Bool) -> Void)?

    @Published var state: NotificationTransferState
    @Published var isTrusted: Bool = false

    init(
        id: String,
        deviceName: String,
        deviceType: RemoteDeviceInfo.DeviceType,
        summary: String,
        pinCode: String?,
        fileURL: URL? = nil,
        state: NotificationTransferState = .incoming,
        onConsent: ((Bool) -> Void)? = nil,
        onTrust: ((Bool) -> Void)? = nil
    ) {
        self.id = id
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.summary = summary
        self.pinCode = pinCode
        self.fileURL = fileURL
        self.state = state
        self.onConsent = onConsent
        self.onTrust = onTrust
    }
}

final class TransferNotificationPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.popUpMenuWindow)) + 2)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class TransferNotificationManager: ObservableObject {
    static let shared = TransferNotificationManager()

    @Published var currentItem: TransferNotificationItem?
    private var panel: TransferNotificationPanel?
    private var dismissTimer: Timer?
    private let panelWidth: CGFloat = 360
    private let panelHeight: CGFloat = 190

    private init() {}

    func showIncoming(
        transfer: TransferMetadata,
        device: RemoteDeviceInfo,
        isTrusted: Bool = false,
        onConsent: @escaping (Bool) -> Void,
        onTrust: @escaping (Bool) -> Void
    ) {
        dismissTimer?.invalidate()
        let summary: String
        if let text = transfer.textDescription {
            summary = text
        } else if let first = transfer.files.first {
            let totalBytes = transfer.files.reduce(0) { $0 + $1.size }
            let sizeStr = totalBytes > 0 ? " • \(TransferModel.formatBytes(totalBytes))" : ""
            if transfer.files.count > 1 {
                summary = "\(transfer.files.count) files (\(first.name)...)\(sizeStr)"
            } else {
                summary = "\(first.name)\(sizeStr)"
            }
        } else {
            summary = "1 item"
        }

        let item = TransferNotificationItem(
            id: transfer.id,
            deviceName: device.name,
            deviceType: device.type,
            summary: summary,
            pinCode: transfer.pinCode,
            state: .incoming,
            onConsent: onConsent,
            onTrust: onTrust
        )
        item.isTrusted = isTrusted
        presentItem(item)
    }

    func showAutoAccepted(transfer: TransferMetadata, device: RemoteDeviceInfo) {
        dismissTimer?.invalidate()
        let summary = transfer.files.first.map { f in
            transfer.files.count > 1 ? "\(transfer.files.count) files" : f.name
        } ?? "1 item"
        let item = TransferNotificationItem(
            id: transfer.id,
            deviceName: device.name,
            deviceType: device.type,
            summary: summary,
            pinCode: transfer.pinCode,
            state: .receiving
        )
        item.isTrusted = true
        presentItem(item)
    }

    func transferDidConsent(id: String, accept: Bool) {
        guard let item = currentItem, item.id == id else { return }
        if accept {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                item.state = .receiving
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                item.state = .failed(message: "Transfer Declined")
            }
            scheduleDismiss(after: 1.2)
        }
    }

    func transferDidFinish(id: String, error: Error?, fileURL: URL?, fileName: String) {
        guard let item = currentItem, item.id == id else { return }
        dismissTimer?.invalidate()
        if let error = error {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                item.state = .failed(message: error.localizedDescription)
            }
            scheduleDismiss(after: 2.5)
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
                item.state = .completed(fileURL: fileURL)
            }
            scheduleDismiss(after: 6.0)
        }
    }

    func showPreview() {
        dismissTimer?.invalidate()
        let item = TransferNotificationItem(
            id: "preview_\(UUID().uuidString)",
            deviceName: "Google Pixel 8 Pro",
            deviceType: .phone,
            summary: "IMG_20261021_AirDrop.jpg • 4.8 MB",
            pinCode: "8492",
            state: .incoming,
            onConsent: { [weak self] accept in
                guard let self = self, let item = self.currentItem else { return }
                if accept {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        item.state = .receiving
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        if self.currentItem?.id == item.id {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                item.state = .completed(fileURL: NearbyConnectionManager.downloadDirectory)
                            }
                            self.scheduleDismiss(after: 5.0)
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        item.state = .failed(message: "Transfer Declined")
                    }
                    self.scheduleDismiss(after: 1.2)
                }
            },
            onTrust: { _ in }
        )
        presentItem(item)
    }

    func dismiss(animated: Bool = true) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let panel = panel else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.panel?.orderOut(nil)
                self?.panel = nil
                self?.currentItem = nil
            })
        } else {
            panel.orderOut(nil)
            self.panel = nil
            self.currentItem = nil
        }
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.dismiss(animated: true)
        }
    }

    private func presentItem(_ item: TransferNotificationItem) {
        currentItem = item
        if panel == nil {
            let p = TransferNotificationPanel(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
            let hosting = NSHostingView(rootView: TransferNotificationBannerView(manager: self))
            p.contentView = hosting
            panel = p
        }
        positionPanel()
        panel?.alphaValue = 1.0
        panel?.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let panel = panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screenFrame = screen?.visibleFrame else { return }
        let x = screenFrame.maxX - panelWidth - 20
        let y = screenFrame.maxY - panelHeight - 16
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}

struct TransferNotificationBannerView: View {
    @ObservedObject var manager: TransferNotificationManager
    @ObservedObject private var theme = ThemeManager.shared
    @State private var isVisible: Bool = false
    @State private var isPulsing: Bool = false
    @State private var checkmarkPop: Bool = false

    var body: some View {
        Group {
            if let item = manager.currentItem {
                contentCard(item: item)
            } else {
                EmptyView()
            }
        }
        .frame(width: 360)
        .offset(x: isVisible ? 0 : 380)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                isVisible = true
            }
        }
    }

    @ViewBuilder
    private func contentCard(item: TransferNotificationItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Device avatar + Device Name + Close
            HStack(spacing: 12) {
                deviceAvatar(item: item)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.deviceName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let pin = item.pinCode, item.state == .incoming {
                            Text("PIN \(pin)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.currentAccent.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.currentAccent.color.opacity(0.12), in: Capsule())
                        }
                    }

                    Text(stateSubtitle(for: item.state))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    FeedbackManager.shared.vibrateTap()
                    manager.dismiss(animated: true)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }

            // Summary text
            Text(item.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Dynamic State Body
            switch item.state {
            case .incoming:
                HStack(alignment: .center) {
                    Toggle("Trust device", isOn: Binding(
                        get: { item.isTrusted },
                        set: {
                            item.isTrusted = $0
                            item.onTrust?($0)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Decline") {
                        FeedbackManager.shared.playError()
                        FeedbackManager.shared.vibrateTap()
                        item.onConsent?(false)
                        manager.transferDidConsent(id: item.id, accept: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Accept") {
                        FeedbackManager.shared.playIncoming()
                        FeedbackManager.shared.vibrateClick()
                        item.onConsent?(true)
                        manager.transferDidConsent(id: item.id, accept: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.small)
                }
                .padding(.top, 2)

            case .receiving:
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(theme.currentAccent.color)
                    HStack {
                        Text("Receiving file…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.top, 2)

            case .completed(let fileURL):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.green)
                        .scaleEffect(checkmarkPop ? 1.0 : 0.4)
                        .onAppear {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                                checkmarkPop = true
                            }
                        }

                    Text("Transfer Complete")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)

                    Spacer()

                    Button("Finder") {
                        FeedbackManager.shared.vibrateClick()
                        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            TransferModel.openDownloads()
                        }
                        manager.dismiss(animated: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Open") {
                        FeedbackManager.shared.vibrateClick()
                        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.open(url)
                        } else {
                            TransferModel.openDownloads()
                        }
                        manager.dismiss(animated: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.small)
                }
                .padding(.top, 2)

            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            // Clicking body of notification brings main window or popover
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.openApp(nil)
            }
        }
    }

    @ViewBuilder
    private func deviceAvatar(item: TransferNotificationItem) -> some View {
        ZStack {
            if item.state == .incoming {
                Circle()
                    .stroke(theme.currentAccent.color.opacity(isPulsing ? 0 : 0.6), lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.55 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) {
                            isPulsing = true
                        }
                    }
            }

            Circle()
                .fill(theme.currentAccent.color.opacity(0.15))

            Image(systemName: deviceSymbol(item.deviceType))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.currentAccent.color)
        }
        .frame(width: 40, height: 40)
    }

    private func deviceSymbol(_ type: RemoteDeviceInfo.DeviceType) -> String {
        switch type {
        case .computer: return "laptopcomputer"
        case .tablet: return "ipad"
        case .phone: return "iphone"
        case .unknown: return "dot.radiowaves.left.and.right"
        @unknown default: return "iphone"
        }
    }

    private func stateSubtitle(for state: NotificationTransferState) -> String {
        switch state {
        case .incoming: return "Incoming Transfer"
        case .receiving: return "Receiving…"
        case .completed: return "Saved to Downloads"
        case .failed: return "Transfer Failed"
        }
    }
}
