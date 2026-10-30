import Cocoa
import SwiftUI
import NearbyShare
import CoreImage.CIFilterBuiltins
import ServiceManagement

struct TransferHistoryItem: Codable, Identifiable, Hashable {
    enum Direction: String, Codable {
        case incoming = "Received"
        case outgoing = "Sent"
    }
    let id: UUID
    let fileName: String
    let fileSize: Int64
    let direction: Direction
    let peerName: String
    let timestamp: Date
    let fileURL: URL?
}

struct CompletedTransferInfo: Identifiable, Equatable {
    let id: String
    let fileName: String
    let fileCount: Int
    let fileURL: URL?
    let destinationPath: String
}

final class TransferModel: NSObject, ObservableObject, ShareExtensionDelegate {
    enum Tab: String, CaseIterable { case send = "Send", receive = "Receive", history = "Transfers", usb = "USB" }
    @Published var tab: Tab = .receive {
        didSet {
            scanning = false
            if tab == .send || showingQR {
                startSendingDiscovery()
            } else {
                stopSendingDiscovery()
            }
        }
    }
    @Published var urls: [URL] = []
    @Published var devices: [RemoteDeviceInfo] = []
    @Published var advertisement = NearbyConnectionManager.AdvertisementState.idle
    @Published var qrImage: NSImage?
    @Published var showingQR = false
    @Published var scanning = false
    @Published var waitingForQR = false
    @Published var qrTransferStatus: String = "Waiting for phone to scan…"
    @Published var incoming: [String: TransferInfo] = [:]
    @Published var accepted: Set<String> = []
    @Published var receiveMessage = ""
    @Published var sendMessage = ""
    @Published var progress: Double = 0
    @Published var sending = false
    @Published var recipient = ""
    @Published var error: String?
    @Published var selectionNotice: String?
    @Published var lastCompletedTransfer: CompletedTransferInfo?
    @Published var lastTransferError: String?

    @Published var incomingProgress: [String: ReceiveProgress] = [:]
    var qrTransferID: String?

    func updateIncomingProgress(id: String, bytesTransferred: Int64, totalBytes: Int64) {
        guard incoming[id] != nil else { return }
        var progress = incomingProgress[id] ?? ReceiveProgress()
        progress.bytes = bytesTransferred
        progress.total = totalBytes
        progress.updated = Date()
        incomingProgress[id] = progress
    }

    func cancelIncomingTransfer(_ id: String) {
        NearbyConnectionManager.shared.cancelIncomingTransfer(id: id)
        incoming.removeValue(forKey: id)
        incomingProgress.removeValue(forKey: id)
        accepted.remove(id)
        clearCompletedTransfer()
        FeedbackManager.shared.vibrateTap()
    }

    func clearCompletedTransfer() {
        withAnimation {
            lastCompletedTransfer = nil
            lastTransferError = nil
            if incoming.isEmpty { incomingProgress.removeAll() }
        }
    }

    // Folder & relative path transfers
    @Published var displayNames: [String] = []
    private(set) var totalBytes: Int64 = 0
    private var selectionIdentities: [TransferFileIdentity] = []

    // Transfer speed and ETA
    @Published var transferSpeed: String = ""
    @Published var timeRemaining: String = ""
    private var speedSamples: [(time: Date, bytes: Int64)] = []

    // Preferences & persistence
    @Published var downloadDirectory: URL = NearbyConnectionManager.downloadDirectory
    var downloadDirectoryDisplayPath: String {
        let home = NSHomeDirectory()
        let path = downloadDirectory.path
        if path.hasPrefix(home + "/Downloads") {
            let relative = path.dropFirst(home.count + 1)
            return String(relative)
        } else if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return downloadDirectory.lastPathComponent
    }
    @Published var isChoosingDirectory: Bool = false
    @Published var isChoosingFiles: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var history: [TransferHistoryItem] = []
    private static let historyKey = "transferHistory"

    let usb = USBModel()
    var deviceName: String { NearbyConnectionManager.currentDeviceName }
    var onConsent: ((String, Bool) -> Void)?
    private var chosenID: String?
    private var chosenPeer: RemoteDeviceInfo?
    private var scopedURLs: [URL] = []
    private var selectionGeneration = UUID()
    private let fileSelectionQueue = DispatchQueue(label: "com.arslanbasharat.NearByDrop.file-selection", qos: .userInitiated)
    private var qrExpiry: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    private var adDebounce: DispatchWorkItem?

    private var isDiscoveringDevices = false
    func startSendingDiscovery() {
        guard !isDiscoveringDevices else { return }
        isDiscoveringDevices = true
        NearbyConnectionManager.shared.startDeviceDiscovery()
    }
    func stopSendingDiscovery() {
        guard isDiscoveringDevices else { return }
        isDiscoveringDevices = false
        NearbyConnectionManager.shared.stopDeviceDiscovery()
    }

    deinit {
        stopSendingDiscovery()
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
    }

    func setAdvertisementState(_ state: NearbyConnectionManager.AdvertisementState) {
        adDebounce?.cancel()
        if state == .published {
            advertisement = .published
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.advertisement = state
            }
            adDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    enum QRTransferStatus: Equatable {
        case idle
        case connecting(sender: String?)
        case downloading(sender: String, description: String?)
        case completed(filename: String, count: Int)
        case failed(error: String)
    }

    @Published var lastScannedURL: URL?
    @Published var qrStatus: QRTransferStatus = .idle

    override init() {
        super.init()
        loadHistory()
        updateLaunchAtLoginStatus()
        NearbyConnectionManager.shared.addShareExtensionDelegate(self)
    }

    func setFiles(_ newURLs: [URL], completion: (() -> Void)? = nil) {
        guard !sending, !usb.busy else { return }
        selectionGeneration = UUID()
        let generation = selectionGeneration
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedURLs = []
        urls = []
        displayNames = []
        selectionIdentities = []
        totalBytes = 0
        selectionNotice = nil
        sendMessage = ""
        error = nil
        resetSpeedTracking()

        guard !newURLs.isEmpty else {
            completion?()
            return
        }
        let newScopedURLs = newURLs.filter { $0.startAccessingSecurityScopedResource() }
        fileSelectionQueue.async { [weak self] in
            let selection = TransferFileSafety.expandSelection(newURLs)
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == generation else {
                    newScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                    return
                }
                self.scopedURLs = newScopedURLs
                self.urls = selection.urls
                self.displayNames = selection.displayNames
                self.selectionIdentities = selection.identities
                self.totalBytes = selection.identities.reduce(Int64(0)) { total, identity in
                    let (sum, overflow) = total.addingReportingOverflow(identity.size)
                    return overflow ? Int64.max : sum
                }
                self.selectionNotice = selection.skipped.message
                if selection.urls.isEmpty {
                    self.error = selection.emptyMessage
                } else if selection.urls.count > TransferFileSafety.maximumFileCount {
                    let limitNotice = "Quick Share supports up to \(TransferFileSafety.maximumFileCount) files per transfer. Choose fewer files."
                    self.selectionNotice = [self.selectionNotice, limitNotice].compactMap { $0 }.joined(separator: " ")
                }
                completion?()
            }
        }
    }

    func chooseFiles() {
        chooseFiles(thenSendTo: nil)
    }

    func chooseFiles(thenSendTo device: RemoteDeviceInfo?, thenShowQR: Bool = false) {
        guard !sending, !usb.busy else { return }
        scanning = false
        showingQR = false
        isChoosingFiles = true
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.isChoosingFiles = false
                NotificationCenter.default.post(name: .didFinishChoosingFiles, object: nil)
            }
            guard result == .OK, let self else { return }
            self.setFiles(panel.urls) {
                FeedbackManager.shared.vibrateClick()
                if let device = device {
                    self.send(to: device)
                } else if thenShowQR {
                    self.showQR()
                }
            }
        }
        panel.presentForInteraction(completion: handler)
    }
    func send(to device: RemoteDeviceInfo) {
        guard !sending, !urls.isEmpty, let id = device.id else { return }
        guard urls.filter(\.isFileURL).count <= TransferFileSafety.maximumFileCount else {
            error = "Quick Share supports up to \(TransferFileSafety.maximumFileCount) files per transfer. Choose fewer files and try again."
            return
        }
        chosenID = id
        chosenPeer = device
        recipient = device.name
        sending = true
        showingQR = false
        progress = 0
        error = nil
        resetSpeedTracking()
        FeedbackManager.shared.playStart()
        FeedbackManager.shared.vibrateClick()
        sendMessage = "Connecting…"
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.sending else { return }
            self.cancelSend()
            self.error = "The phone did not respond. Open Quick Share in Receive mode and try again."
        }
        timeout?.cancel(); timeout = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: expiry)
        NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: id, delegate: self, urls: urls, displayNames: displayNames.isEmpty ? nil : displayNames, fileIdentities: selectionIdentities)
        NearbyConnectionManager.shared.clearQrCodeKey()
    }
    func cancelSend() {
        timeout?.cancel()
        if let id = chosenID { NearbyConnectionManager.shared.cancelOutgoingTransfer(id: id) }
        chosenID = nil; chosenPeer = nil; sending = false; sendMessage = "Canceled"
        resetSpeedTracking()
    }
    func showQR() {
        guard !urls.isEmpty, !sending else { return }
        guard urls.filter(\.isFileURL).count <= TransferFileSafety.maximumFileCount else {
            error = "Quick Share supports up to \(TransferFileSafety.maximumFileCount) files per transfer. Choose fewer files and try again."
            return
        }

        NearbyConnectionManager.shared.clearQrCodeKey()
        startSendingDiscovery()
        let qrKey = NearbyConnectionManager.shared.generateQrCodeKey()
        let quickShareURL = "https://quickshare.google/qrcode#key=\(qrKey)"

        qrTransferStatus = "Waiting for phone to scan…"

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(quickShareURL.utf8)
        filter.correctionLevel = "M"
        if let output = filter.outputImage, let cg = CIContext().createCGImage(output.transformed(by: .init(scaleX: 8, y: 8)), from: output.extent.applying(.init(scaleX: 8, y: 8))) {
            qrImage = NSImage(cgImage: cg, size: NSSize(width: 240, height: 240))
            showingQR = true
        } else {
            NearbyConnectionManager.shared.clearQrCodeKey()
            error = "Could not generate a QR code."
        }
    }

    func dismissQR() {
        if tab != .send { stopSendingDiscovery() }
        NearbyConnectionManager.shared.clearQrCodeKey()
        showingQR = false
        qrImage = nil
        qrTransferStatus = "Waiting for phone to scan…"
    }
    func scan(_ value: String) -> String? {
        guard let url = URL(string: value) else { return "Invalid QR code" }
        do {
            try NearbyConnectionManager.shared.receiveQRCode(value)
            lastScannedURL = url
            scanning = false
            waitingForQR = true
            qrStatus = .connecting(sender: "Phone")
            receiveMessage = "Waiting for phone to connect…"
            qrExpiry?.cancel()
            let expiry = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if case .completed = self.qrStatus {}
                else {
                    self.stopQRReceive()
                    self.qrStatus = .failed(error: "Transfer timed out. Try scanning again.")
                }
            }
            qrExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: expiry)
            return nil
        } catch { return Self.errorMessage(error) }
    }
    func stopQRReceive() {
        qrExpiry?.cancel()
        qrExpiry = nil
        waitingForQR = false
        lastScannedURL = nil
        NearbyConnectionManager.shared.stopReceivingQRCode()
    }
    func resetQRTransfer() {
        stopQRReceive()
        if let id = qrTransferID { cancelIncomingTransfer(id) }
        qrTransferID = nil
        qrStatus = .idle
    }
    func addDevice(device: RemoteDeviceInfo) {
        DispatchQueue.main.async {
            self.devices.removeAll { $0.id == device.id }
            self.devices.append(device)
            self.devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    func removeDevice(id: String) {
        DispatchQueue.main.async {
            self.devices.removeAll { $0.id == id }
        }
    }
    func startTransferWithQrCode(device: RemoteDeviceInfo) {
        DispatchQueue.main.async {
            if self.showingQR {
                self.send(to: device)
            }
        }
    }
    func connectionWasEstablished(pinCode: String) {
        DispatchQueue.main.async {
            self.sendMessage = "Confirm code \(pinCode) on \(self.recipient)"
        }
    }
    func connectionFailed(with error: Error) {
        DispatchQueue.main.async {
            guard self.sending else { return }
            self.timeout?.cancel()
            self.sending = false
            self.chosenID = nil
            self.error = Self.errorMessage(error)
            self.sendMessage = ""
            self.resetSpeedTracking()
            FeedbackManager.shared.playError()
            FeedbackManager.shared.vibrateTap()
        }
    }
    func transferAccepted() {
        DispatchQueue.main.async {
            self.timeout?.cancel()
            self.sendMessage = "Sending to \(self.recipient)…"
            FeedbackManager.shared.vibrateTap()
        }
    }
    func transferProgress(progress: Double) {
        DispatchQueue.main.async {
            self.progress = min(1, max(0, progress))
            let currentBytes = Int64(Double(self.totalBytes) * self.progress)
            self.updateSpeedAndETA(currentBytes: currentBytes, total: self.totalBytes)
        }
    }
    func transferFinished() {
        DispatchQueue.main.async { [self] in
            self.timeout?.cancel()
            let peer = self.recipient
            let peerInfo = self.chosenPeer
            self.chosenPeer = nil
            self.chosenID = nil
            self.progress = 1
            self.sendMessage = "Sent to \(peer)"
            let fileName = self.displayNames.first ?? self.urls.first?.lastPathComponent ?? "Files"
            let display = self.urls.count > 1 ? "\(fileName) (+\(self.urls.count - 1))" : fileName
            self.recordTransfer(fileName: display, fileSize: self.totalBytes, direction: .outgoing, peerName: peer, fileURL: self.urls.first)
            if let peerInfo { UsageAnalytics.completedTransfer(direction: "outgoing", peer: peerInfo) }
            FeedbackManager.shared.playSuccess()
            FeedbackManager.shared.vibrateSuccess()
            self.resetSpeedTracking()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.chosenID == nil else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    self.sending = false
                    self.setFiles([])
                    self.sendMessage = ""
                    self.progress = 0
                }
            }
        }
    }

    func updateSpeedAndETA(currentBytes: Int64, total: Int64) {
        let now = Date()
        speedSamples.append((time: now, bytes: currentBytes))
        speedSamples.removeAll { now.timeIntervalSince($0.time) > 2.5 }
        guard speedSamples.count >= 2,
              let oldest = speedSamples.first,
              let latest = speedSamples.last else { return }
        let duration = latest.time.timeIntervalSince(oldest.time)
        let byteDelta = latest.bytes - oldest.bytes
        guard duration > 0.2, byteDelta > 0 else { return }

        let bytesPerSec = Double(byteDelta) / duration
        if bytesPerSec >= 1_048_576 {
            transferSpeed = String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            transferSpeed = String(format: "%.0f KB/s", bytesPerSec / 1024)
        } else {
            transferSpeed = String(format: "%.0f B/s", bytesPerSec)
        }

        let remainingBytes = max(0, total - currentBytes)
        if bytesPerSec > 0 && remainingBytes > 0 {
            let seconds = Int(Double(remainingBytes) / bytesPerSec)
            if seconds < 60 {
                timeRemaining = "\(seconds)s left"
            } else {
                let m = seconds / 60
                let s = seconds % 60
                timeRemaining = "\(m)m \(s)s left"
            }
        } else if remainingBytes == 0 {
            timeRemaining = "Finishing…"
        }
    }

    func resetSpeedTracking() {
        speedSamples.removeAll()
        transferSpeed = ""
        timeRemaining = ""
    }

    func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let items = try? JSONDecoder().decode([TransferHistoryItem].self, from: data) else { return }
        history = items
    }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }

    func recordTransfer(fileName: String, fileSize: Int64, direction: TransferHistoryItem.Direction, peerName: String, fileURL: URL?) {
        let item = TransferHistoryItem(
            id: UUID(),
            fileName: fileName,
            fileSize: fileSize,
            direction: direction,
            peerName: peerName,
            timestamp: Date(),
            fileURL: fileURL
        )
        history.insert(item, at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }
    }

    func recordIncoming(info: TransferInfo, fileURLs: [URL]) {
        let name: String
        if let text = info.transfer.textDescription {
            name = text
        } else if let first = info.transfer.files.first {
            name = info.transfer.files.count > 1 ? "\(first.name) (+\(info.transfer.files.count - 1))" : first.name
        } else {
            name = "Unknown file"
        }
        let total = info.transfer.files.reduce(0) { $0 + $1.size }
        recordTransfer(fileName: name, fileSize: total, direction: .incoming, peerName: info.device.name, fileURL: fileURLs.first)
        UsageAnalytics.completedTransfer(direction: "incoming", peer: info.device)
    }

    func setDownloadDirectory(_ url: URL) {
        NearbyConnectionManager.downloadDirectory = url
        downloadDirectory = url
    }

    func chooseDownloadDirectory(relativeTo window: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a download folder for received files"
        panel.directoryURL = downloadDirectory
        isChoosingDirectory = true
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.isChoosingDirectory = false
                NotificationCenter.default.post(name: .didFinishChoosingFiles, object: nil)
            }
            guard result == .OK, let url = panel.url, let self = self else { return }
            self.setDownloadDirectory(url)
        }
        panel.presentForInteraction(relativeTo: window, completion: handler)
    }

    func resetDownloadDirectoryToDefault() {
        let defaultURL = NearbyConnectionManager.defaultDownloadDirectory
        setDownloadDirectory(defaultURL)
    }

    func updateLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("SMAppService error: \(error)")
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: bytes)
    }

    static func formatDate(_ date: Date) -> String {
        let r = RelativeDateTimeFormatter()
        r.unitsStyle = .short
        return r.localizedString(for: date, relativeTo: Date())
    }

    static func errorMessage(_ error: Error) -> String {
        return error.localizedDescription
    }
    static func openDownloads() {
        NSWorkspace.shared.open(NearbyConnectionManager.downloadDirectory)
    }
}

struct TransferCompletionCard: View {
    let completed: CompletedTransferInfo
    @ObservedObject var model: TransferModel
    @ObservedObject var theme = ThemeManager.shared
    @State private var checkmarkScale: CGFloat = 0.3
    @State private var checkmarkOpacity: Double = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 6)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }
            .onAppear {
                guard !reduceMotion else {
                    checkmarkScale = 1.0
                    checkmarkOpacity = 1.0
                    return
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    checkmarkScale = 1.0
                    checkmarkOpacity = 1.0
                }
            }

            VStack(spacing: 4) {
                Text("Transfer Complete")
                    .font(.headline)
                Text(completed.fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(completed.destinationPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 10) {
                Button("Show in Finder") {
                    if let url = completed.fileURL, FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        TransferModel.openDownloads()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("Receive Another") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.clearCompletedTransfer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.currentAccent.color)
                .controlSize(.regular)
            }
            .padding(.top, 4)

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TransferErrorCard: View {
    let error: String
    @ObservedObject var model: TransferModel
    @ObservedObject var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 6)

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.red)

            Text("Transfer Failed")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 20)

            Button("Dismiss", role: .cancel) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.clearCompletedTransfer()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IncomingTransferReceivingCard: View {
    let id: String
    let item: TransferInfo
    @ObservedObject var model: TransferModel
    @ObservedObject var theme = ThemeManager.shared

    var totalBytes: Int64 {
        if let progress = model.incomingProgress[id], progress.total > 0 { return progress.total }
        return item.transfer.files.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.device.type == .computer ? "laptopcomputer" : "iphone")
                    .foregroundStyle(theme.currentAccent.color)
                Text(item.device.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let progress = model.incomingProgress[id], progress.bytesPerSecond > 0 {
                    Text("\(TransferModel.formatBytes(Int64(progress.bytesPerSecond)))/s")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            Text(item.transfer.textDescription ?? "\(item.transfer.files.count) \(item.transfer.files.count == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            ProgressView(value: totalBytes > 0 ? Double(model.incomingProgress[id]?.bytes ?? 0) / Double(totalBytes) : nil)
                .progressViewStyle(.linear)
                .accessibilityLabel("Receiving files from \(item.device.name)")
                .accessibilityValue(totalBytes > 0 ? "\(Int(Double(model.incomingProgress[id]?.bytes ?? 0) / Double(totalBytes) * 100)) percent" : "In progress")

            HStack {
                Text("\(TransferModel.formatBytes((model.incomingProgress[id]?.bytes ?? 0))) of \(TransferModel.formatBytes(totalBytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()

            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    model.cancelIncomingTransfer(id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickShareGuideCard: View {
    let deviceName: String
    @ObservedObject var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How to Send to This Mac", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.caption)
                        .foregroundStyle(theme.currentAccent.color)
                        .frame(width: 16)
                    Text("Connect both devices to the same Wi-Fi network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(theme.currentAccent.color)
                        .frame(width: 16)
                    Text("On Android or Windows, tap Share → Quick Share.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "laptopcomputer")
                        .font(.caption)
                        .foregroundStyle(theme.currentAccent.color)
                        .frame(width: 16)
                    Text("Select '\(deviceName)' to send your files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}
