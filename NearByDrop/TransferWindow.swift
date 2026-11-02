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
    private var isPreviewFixture = false
    @Published var tab: Tab = .receive {
        didSet {
            scanning = false
            guard !isPreviewFixture else { return }
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
    @Published var choosingRecipient = false
    @Published var scanning = false
    @Published var waitingForQR = false
    @Published var qrTransferStatus: String = "Waiting for phone to scan…"
    @Published var incoming: [String: TransferInfo] = [:]
    @Published var accepted: Set<String> = []
    @Published var receiveMessage = ""
    @Published var sendMessage = ""
    @Published var progress: Double = 0
    @Published var sending = false
    @Published private(set) var outgoingPhase: OutgoingAttemptPhase = .idle
    @Published private(set) var outgoingStatusMessage = ""
    @Published var recipient = ""
    @Published var error: String?
    @Published var selectionNotice: String?
    @Published var lastCompletedTransfer: CompletedTransferInfo?
    @Published var lastTransferError: String?
    @Published var lastFailedIncoming: TransferInfo?

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
            lastFailedIncoming = nil
            if incoming.isEmpty { incomingProgress.removeAll() }
        }
    }

    // Folder & relative path transfers
    @Published var displayNames: [String] = []
    private(set) var totalBytes: Int64 = 0
    private var selectionIdentities: [TransferFileIdentity] = []
#if DEBUG
    private var previewFileSizes: [Int64] = []
#endif
    var selectedFileSizes: [Int64] {
#if DEBUG
        if isPreviewFixture { return previewFileSizes }
#endif
        return selectionIdentities.map(\.size)
    }

    // Transfer speed and ETA
    @Published var transferSpeed: String = ""
    @Published var timeRemaining: String = ""
    private var speedSamples: [(time: Date, bytes: Int64)] = []

    // Preferences & persistence
    @Published var downloadDirectory: URL
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
    @Published var launchAtLoginMessage: String?
    @Published var history: [TransferHistoryItem] = []
    private static let historyKey = "transferHistory"
    private static let launchAtLoginDisabledByUserKey = "launchAtLoginDisabledByUser"
    @Published private(set) var receivingPaused: Bool

    let usb = USBModel()
    var deviceName: String { isPreviewFixture ? "Alex’s MacBook Pro" : NearbyConnectionManager.currentDeviceName }
    var canManageLaunchAtLogin: Bool { isInstalledInApplicationsFolder }
    var onConsent: ((String, Bool) -> Void)?
    private var chosenID: String?
    private var chosenPeer: RemoteDeviceInfo?
    private var retryPeer: RemoteDeviceInfo?
    private var scopedURLs: [URL] = []
    private var selectedSourceURLs: [URL] = []
    private var selectedFileSnapshot: TransferFileSelection?
    private var outgoingLifecycle = OutgoingAttemptLifecycle()
    private var activeOutgoingAttemptID: UUID?
    private var activeOutgoingDelegate: OutgoingAttemptDelegate?
    private var activeAttemptIsRetry = false
    private var lastDiagnosticsErrorCategory: DiagnosticsErrorCategory?
    private var selectionGeneration = UUID()
    private let fileSelectionQueue = DispatchQueue(label: "com.arslanbasharat.NearByDrop.file-selection", qos: .userInitiated)
    private var qrExpiry: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    private var adDebounce: DispatchWorkItem?

    var canRetryFailedOutgoing: Bool {
        outgoingPhase == .failed && outgoingLifecycle.retryAvailable && retryPeer?.id != nil
    }

    var retryPeerIsNearby: Bool {
        guard canRetryFailedOutgoing, let id = retryPeer?.id else { return false }
        return devices.contains { $0.id == id }
    }

    private var isDiscoveringDevices = false
    func startSendingDiscovery() {
        guard !isPreviewFixture, !isDiscoveringDevices else { return }
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
        if !isPreviewFixture {
            NearbyConnectionManager.shared.removeShareExtensionDelegate(self)
        }
    }

    func setAdvertisementState(_ state: NearbyConnectionManager.AdvertisementState) {
        adDebounce?.cancel()
        receivingPaused = state == .paused
        if state == .published || state == .paused {
            advertisement = state
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
        let isPreview = PreviewRuntime.isSwiftUIPreviews
        isPreviewFixture = isPreview
        downloadDirectory = isPreview
            ? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
            : NearbyConnectionManager.downloadDirectory
        receivingPaused = isPreview ? false : UserDefaults.standard.bool(forKey: "receivingPaused")
        super.init()
        guard !isPreview else { return }
        loadHistory()
        updateLaunchAtLoginStatus()
        NearbyConnectionManager.shared.addShareExtensionDelegate(self)
    }

#if DEBUG
    enum PreviewState: Equatable {
        case empty, sendReady, sendSearching, sendRecipients, sendQR, sendProgress, sendFailure
        case receiveReady, receivePaused, receiveConsent, receiveProgress, receiveComplete, receiveFailure
        case camera, cameraDenied, historyRecent, historyEmpty
        case usbSearching, usbEmpty, usbBrowse, usbProgress, usbComplete, usbFailure
    }
    private(set) var previewState: PreviewState?
    var previewScannerState: QRScannerPreviewState? {
        switch previewState {
        case .camera: return .scanning
        case .cameraDenied: return .permissionDenied
        default: return nil
        }
    }

    static func makePreviewFixture(tab: Tab, state: PreviewState? = nil) -> TransferModel {
        let model = TransferModel()
        model.isPreviewFixture = true
        model.usb.isPreviewFixture = true
        model.history = []
        model.devices = []
        model.advertisement = .published
        model.receivingPaused = false
        model.tab = tab
        model.previewState = state

        let previewFiles = [
            FileMetadata(name: "Coast weekend.zip", size: 134_217_728, mimeType: "application/zip"),
            FileMetadata(name: "Route.pdf", size: 2_516_582, mimeType: "application/pdf")
        ]
        let previewURLs = [
            URL(fileURLWithPath: "/tmp/NearbyDrop Preview/Coast weekend.zip"),
            URL(fileURLWithPath: "/tmp/NearbyDrop Preview/Route.pdf")
        ]
        let peer = RemoteDeviceInfo(name: "Alex’s Pixel 8", type: .phone, id: "preview-pixel-8")
        let windowsPeer = RemoteDeviceInfo(name: "Jamie’s Surface", type: .computer, id: "preview-surface")
        let transferID = "preview-incoming-transfer"

        func setPreviewFiles() {
            model.urls = previewURLs
            model.displayNames = previewFiles.map(\.name)
            model.totalBytes = previewFiles.reduce(0) { $0 + $1.size }
            model.previewFileSizes = previewFiles.map(\.size)
        }

        switch state ?? (tab == .send ? .empty : tab == .receive ? .receiveReady : tab == .history ? .historyEmpty : .usbEmpty) {
        case .empty:
            break
        case .sendReady, .sendSearching, .sendRecipients, .sendQR, .sendProgress, .sendFailure:
            setPreviewFiles()
            model.devices = state == .sendSearching ? [] : [peer, windowsPeer]
            model.recipient = peer.name
            if state == .sendSearching || state == .sendRecipients {
                model.choosingRecipient = true
            }
            if state == .sendQR {
                model.showingQR = true
                model.qrTransferStatus = "Waiting for phone to scan…"
                model.qrImage = Self.previewQRCode()
            } else if state == .sendProgress {
                model.sending = true
                model.progress = 0.62
                model.transferSpeed = "4.2 MB/s"
                model.timeRemaining = "About 12 seconds remaining"
                model.sendMessage = "Sending to Alex’s Pixel 8…"
                model.outgoingStatusMessage = "Sending files"
                model.outgoingPhase = .transferring
            } else if state == .sendFailure {
                model.error = "Alex’s Pixel 8 went out of range. Your files haven’t finished sending."
                model.outgoingPhase = .failed
                model.retryPeer = peer
                model.chosenPeer = peer
                if let attemptID = model.outgoingLifecycle.begin(retry: false) {
                    _ = model.outgoingLifecycle.fail(for: attemptID, retryAllowed: true)
                }
            }
        case .receiveReady:
            break
        case .receivePaused:
            model.receivingPaused = true
            model.advertisement = .paused
        case .receiveConsent, .receiveProgress:
            let metadata = TransferMetadata(files: [
                FileMetadata(name: "Trail photos.zip", size: 88_080_384, mimeType: "application/zip")
            ], id: transferID, pinCode: "482 619")
            model.incoming = [transferID: TransferInfo(device: peer, transfer: metadata)]
            model.qrTransferID = transferID
            if state == .receiveProgress {
                model.accepted = [transferID]
                model.incomingProgress[transferID] = ReceiveProgress(bytes: 54_009_600, total: 88_080_384)
            }
        case .receiveComplete:
            model.lastFailedIncoming = nil
            model.lastCompletedTransfer = CompletedTransferInfo(
                id: transferID, fileName: "Trail photos.zip", fileCount: 1,
                fileURL: nil, destinationPath: "Downloads"
            )
        case .receiveFailure:
            model.lastTransferError = "The connection ended before the file finished saving."
            model.lastFailedIncoming = TransferInfo(
                device: peer,
                transfer: TransferMetadata(files: [
                    FileMetadata(name: "Trail photos.zip", size: 88_080_384, mimeType: "application/zip")
                ], id: transferID, pinCode: nil)
            )
        case .camera:
            model.scanning = true
        case .cameraDenied:
            model.scanning = true
        case .historyRecent:
            let now = Date()
            model.history = [
                TransferHistoryItem(id: UUID(), fileName: "Trail photos.zip", fileSize: 88_080_384, direction: .incoming, peerName: peer.name, timestamp: now, fileURL: nil),
                TransferHistoryItem(id: UUID(), fileName: "Coast weekend.zip + 1 file", fileSize: 136_734_310, direction: .outgoing, peerName: peer.name, timestamp: now.addingTimeInterval(-240), fileURL: nil),
                TransferHistoryItem(id: UUID(), fileName: "IMG_2048.jpg + 1 file", fileSize: 10_066_329, direction: .incoming, peerName: "USB · Alex’s Pixel 8", timestamp: now.addingTimeInterval(-1_080), fileURL: nil),
                TransferHistoryItem(id: UUID(), fileName: "Coast weekend.zip + 1 file", fileSize: 136_734_310, direction: .outgoing, peerName: peer.name, timestamp: now.addingTimeInterval(-86_400), fileURL: nil)
            ]
        case .historyEmpty:
            model.history = []
        case .usbSearching:
            model.usb.busy = true
            model.usb.message = "Looking for a phone…"
        case .usbEmpty:
            break
        case .usbBrowse, .usbProgress, .usbComplete, .usbFailure:
            model.usb.deviceName = "Alex’s Pixel 8"
            model.usb.storages = [(id: 1, name: "Internal shared storage")]
            model.usb.storage = 1
            model.usb.path = [(id: 10, name: "DCIM"), (id: 11, name: "Camera")]
            model.usb.items = [
                USBItem(id: 101, name: "Screenshots", size: 0, folder: true),
                USBItem(id: 102, name: "IMG_2048.jpg", size: 5_033_164, folder: false),
                USBItem(id: 103, name: "IMG_2049.jpg", size: 5_033_165, folder: false),
                USBItem(id: 104, name: "VID_2050.mp4", size: 38_064_128, folder: false)
            ]
            model.usb.selectedItemIds = [102, 103]
            model.usb.lastTransferredItems = model.usb.items.filter { model.usb.selectedItemIds.contains($0.id) }
            if state == .usbProgress {
                model.usb.busy = true
                model.usb.transferring = true
                model.usb.progress = 0.72
                model.usb.message = "Receiving 2 photos…"
            } else if state == .usbComplete {
                model.usb.lastDownloadedURL = URL(fileURLWithPath: "/tmp/NearbyDrop Preview/Downloads")
                model.usb.message = "Saved 2 photos to Downloads"
            } else if state == .usbFailure {
                model.usb.error = "The download stopped before both photos were saved."
            }
        }
        return model
    }

    private static func previewQRCode() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("Nearby Drop Preview Pairing Code".utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 180, height: 180))
    }
#endif

    @MainActor
    func setFiles(_ newURLs: [URL], completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard !sending, !usb.busy else { return }
        selectionGeneration = UUID()
        let generation = selectionGeneration
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedURLs = []
        selectedSourceURLs = newURLs
        selectedFileSnapshot = nil
        outgoingLifecycle = OutgoingAttemptLifecycle()
        activeOutgoingAttemptID = nil
        activeOutgoingDelegate = nil
        activeAttemptIsRetry = false
        outgoingPhase = .idle
        outgoingStatusMessage = ""
        retryPeer = nil
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
        let applySelection: @MainActor @Sendable (TransferFileSelection) -> Void = { [weak self] selection in
            guard let self, self.selectionGeneration == generation else {
                newScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                return
            }
            newScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            self.selectedFileSnapshot = selection
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
        fileSelectionQueue.async {
            let selection = TransferFileSafety.expandSelection(newURLs)
            DispatchQueue.main.async {
                applySelection(selection)
            }
        }
    }

    @MainActor
    func chooseFiles() {
        chooseFiles(thenSendTo: nil)
    }

    @MainActor
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
        let handler: @MainActor @Sendable (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self else { return }
            self.isChoosingFiles = false
            NotificationCenter.default.post(name: .didFinishChoosingFiles, object: nil)
            guard result == .OK else { return }
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

    @MainActor
    func addFiles() {
        guard !sending, !usb.busy else { return }
        isChoosingFiles = true
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.presentForInteraction { [weak self] response in
            guard let self else { return }
            self.isChoosingFiles = false
            NotificationCenter.default.post(name: .didFinishChoosingFiles, object: nil)
            guard response == .OK else { return }
            self.setFiles(self.selectedSourceURLs + panel.urls)
        }
    }
    func send(to device: RemoteDeviceInfo) {
        guard !sending, !usb.busy, !urls.isEmpty, selectedFileSnapshot != nil, device.id != nil else { return }
        guard urls.filter(\.isFileURL).count <= TransferFileSafety.maximumFileCount else {
            error = "Quick Share supports up to \(TransferFileSafety.maximumFileCount) files per transfer. Choose fewer files and try again."
            return
        }
        guard let attemptID = outgoingLifecycle.begin(retry: false) else { return }
        activeOutgoingAttemptID = attemptID
        outgoingPhase = .connecting
        outgoingStatusMessage = "Checking selected files…"
        prepareOutgoingAttempt(device, attemptID: attemptID, isRetry: false)
    }

    func retryFailedOutgoing() {
        guard !sending, !usb.busy, canRetryFailedOutgoing,
              let retryPeer, let id = retryPeer.id else { return }
        guard let device = devices.first(where: { $0.id == id }) else {
            outgoingStatusMessage = "Device is no longer nearby. Select it again to start a new attempt."
            return
        }
        guard let attemptID = outgoingLifecycle.begin(retry: true) else { return }
        activeOutgoingAttemptID = attemptID
        outgoingPhase = .retrying
        outgoingStatusMessage = "Retrying…"
        prepareOutgoingAttempt(device, attemptID: attemptID, isRetry: true)
    }

    private func prepareOutgoingAttempt(_ device: RemoteDeviceInfo, attemptID: UUID, isRetry: Bool) {
        guard let expected = selectedFileSnapshot, !selectedSourceURLs.isEmpty,
              let deviceID = device.id else {
            failPreparation(attemptID, message: "Choose the files again before sending.", category: .fileAccess)
            return
        }
        activeAttemptIsRetry = isRetry
        let sourceRoots = selectedSourceURLs
        let newlyScopedURLs = sourceRoots.filter { $0.startAccessingSecurityScopedResource() }
        let generation = selectionGeneration
        sending = true
        chosenID = deviceID
        chosenPeer = device
        recipient = device.name
        showingQR = false
        progress = 0
        error = nil
        sendMessage = isRetry ? "Retrying…" : "Checking selected files…"
        resetSpeedTracking()
        timeout?.cancel()

        fileSelectionQueue.async { [weak self] in
            let validation = Result { try TransferFileSafety.revalidateSelection(roots: sourceRoots, matching: expected) }
            DispatchQueue.main.async {
                guard let self,
                      self.activeOutgoingAttemptID == attemptID,
                      self.selectionGeneration == generation else {
                    newlyScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                    return
                }
                switch validation {
                case .failure(let failure):
                    newlyScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                    self.failPreparation(
                        attemptID,
                        message: failure.localizedDescription,
                        category: DiagnosticsReportBuilder.category(for: failure) ?? .fileAccess
                    )
                case .success(let selection):
                    self.scopedURLs = newlyScopedURLs
                    self.urls = selection.urls
                    self.displayNames = selection.displayNames
                    self.selectionIdentities = selection.identities
                    self.totalBytes = selection.identities.reduce(Int64(0)) { total, identity in
                        let (sum, overflow) = total.addingReportingOverflow(identity.size)
                        return overflow ? Int64.max : sum
                    }
                    guard self.outgoingLifecycle.transition(to: .connecting, for: attemptID) else {
                        self.releaseOutgoingFileAccess()
                        return
                    }
                    self.outgoingPhase = .connecting
                    self.outgoingStatusMessage = "Connecting…"
                    self.sendMessage = "Connecting…"
                    self.retryPeer = device
                    self.lastDiagnosticsErrorCategory = nil
                    FeedbackManager.shared.playStart()
                    FeedbackManager.shared.vibrateClick()
                    let expiry = DispatchWorkItem { [weak self] in
                        guard let self, self.activeOutgoingAttemptID == attemptID,
                              self.sending else { return }
                        NearbyConnectionManager.shared.cancelOutgoingTransfer(id: deviceID)
                        self.finishOutgoingFailure(
                            NearbyError.canceled(reason: .timedOut),
                            attemptID: attemptID,
                            retryAllowed: true
                        )
                    }
                    self.timeout = expiry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: expiry)
                    let attemptDelegate = OutgoingAttemptDelegate(model: self, attemptID: attemptID)
                    self.activeOutgoingDelegate = attemptDelegate
                    NearbyConnectionManager.shared.startOutgoingTransfer(
                        deviceID: deviceID,
                        delegate: attemptDelegate,
                        urls: selection.urls,
                        displayNames: selection.displayNames,
                        fileIdentities: selection.identities
                    )
                    NearbyConnectionManager.shared.clearQrCodeKey()
                }
            }
        }
    }

    private func failPreparation(_ attemptID: UUID, message: String, category: DiagnosticsErrorCategory) {
        guard outgoingLifecycle.fail(for: attemptID, retryAllowed: false) else { return }
        sending = false
        chosenID = nil
        chosenPeer = nil
        retryPeer = nil
        error = message
        sendMessage = ""
        outgoingPhase = .failed
        outgoingStatusMessage = "Failed"
        lastDiagnosticsErrorCategory = category
        resetSpeedTracking()
    }

    private func releaseOutgoingFileAccess() {
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedURLs = []
    }

    func cancelSend() {
        timeout?.cancel()
        timeout = nil
        if let id = chosenID { NearbyConnectionManager.shared.cancelOutgoingTransfer(id: id) }
        if let activeOutgoingAttemptID {
            _ = outgoingLifecycle.cancel(for: activeOutgoingAttemptID)
        }
        activeOutgoingAttemptID = nil
        activeOutgoingDelegate = nil
        activeAttemptIsRetry = false
        chosenID = nil
        chosenPeer = nil
        sending = false
        sendMessage = "Cancelled"
        outgoingPhase = .cancelled
        outgoingStatusMessage = "Cancelled. Select a nearby device to start a new attempt."
        releaseOutgoingFileAccess()
        resetSpeedTracking()
    }

    private func finishOutgoingFailure(_ error: Error, attemptID: UUID, retryAllowed: Bool) {
        guard outgoingLifecycle.fail(for: attemptID, retryAllowed: retryAllowed) else { return }
        timeout?.cancel()
        timeout = nil
        sending = false
        chosenID = nil
        retryPeer = chosenPeer
        chosenPeer = nil
        self.error = Self.errorMessage(error)
        sendMessage = ""
        outgoingPhase = .failed
        outgoingStatusMessage = "Failed"
        lastDiagnosticsErrorCategory = DiagnosticsReportBuilder.category(for: error)
        activeOutgoingDelegate = nil
        releaseOutgoingFileAccess()
        resetSpeedTracking()
        FeedbackManager.shared.playError()
        FeedbackManager.shared.vibrateTap()
    }

    fileprivate func receiveOutgoingConnectionEstablished(pinCode: String, attemptID: UUID) {
        DispatchQueue.main.async {
            guard self.activeOutgoingAttemptID == attemptID,
                  self.outgoingLifecycle.transition(to: .waitingForReceiver, for: attemptID) else { return }
            self.outgoingPhase = .waitingForReceiver
            self.outgoingStatusMessage = "Waiting for receiver approval"
            self.sendMessage = "Confirm code \(pinCode) on \(self.recipient)"
        }
    }

    fileprivate func receiveOutgoingAccepted(attemptID: UUID) {
        DispatchQueue.main.async {
            guard self.activeOutgoingAttemptID == attemptID,
                  self.outgoingLifecycle.transition(to: .transferring, for: attemptID) else { return }
            self.timeout?.cancel()
            self.outgoingPhase = .transferring
            self.outgoingStatusMessage = "Transferring"
            self.sendMessage = "Sending to \(self.recipient)…"
            FeedbackManager.shared.vibrateTap()
        }
    }

    fileprivate func receiveOutgoingProgress(_ progress: Double, attemptID: UUID) {
        DispatchQueue.main.async {
            guard self.activeOutgoingAttemptID == attemptID,
                  self.outgoingLifecycle.phase == .transferring else { return }
            self.progress = min(1, max(0, progress))
            let currentBytes = Int64(Double(self.totalBytes) * self.progress)
            self.updateSpeedAndETA(currentBytes: currentBytes, total: self.totalBytes)
        }
    }

    fileprivate func receiveOutgoingFailure(_ error: Error, attemptID: UUID) {
        DispatchQueue.main.async {
            guard self.activeOutgoingAttemptID == attemptID else { return }
            let isUserCancellation: Bool
            if let nearbyError = error as? NearbyError,
               case .canceled(reason: .userCanceled) = nearbyError {
                isUserCancellation = true
            } else {
                isUserCancellation = false
            }
            let retryAllowed = !isUserCancellation
            self.finishOutgoingFailure(error, attemptID: attemptID, retryAllowed: retryAllowed)
        }
    }

    fileprivate func receiveOutgoingFinished(attemptID: UUID) {
        DispatchQueue.main.async { [self] in
            guard activeOutgoingAttemptID == attemptID,
                  outgoingLifecycle.complete(for: attemptID) else { return }
            timeout?.cancel()
            timeout = nil
            let peer = recipient
            let peerInfo = chosenPeer
            chosenPeer = nil
            chosenID = nil
            retryPeer = nil
            progress = 1
            sendMessage = "Sent to \(peer)"
            TransferNotificationManager.post(
                title: "Transfer complete",
                body: "Sent to \(peer).",
                action: TransferNotificationManager.openAppAction
            )
            outgoingPhase = .completed
            outgoingStatusMessage = "Completed"
            let fileName = displayNames.first ?? urls.first?.lastPathComponent ?? "Files"
            let display = urls.count > 1 ? "\(fileName) (+\(urls.count - 1))" : fileName
            recordTransfer(
                fileName: display,
                fileSize: totalBytes,
                direction: .outgoing,
                peerName: peer,
                fileURL: OutgoingHistoryPolicy.sourceURL(for: urls.first, isRetry: activeAttemptIsRetry)
            )
            activeAttemptIsRetry = false
            if let peerInfo { UsageAnalytics.completedTransfer(direction: "outgoing", peer: peerInfo) }
            releaseOutgoingFileAccess()
            FeedbackManager.shared.playSuccess()
            FeedbackManager.shared.vibrateSuccess()
            resetSpeedTracking()

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

    func setReceivingPaused(_ paused: Bool) {
        guard receivingPaused != paused else { return }
        if paused {
            scanning = false
            if waitingForQR {
                stopQRReceive()
                qrStatus = .failed(error: "Receiving is paused. Resume receiving before scanning again.")
            }
        }
        NearbyConnectionManager.shared.setReceivingPaused(paused)
    }

    func scan(_ value: String) -> String? {
        guard !receivingPaused else { return "Receiving is paused. Resume receiving before scanning a QR code." }
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

    var diagnosticsReportSnapshot: DiagnosticsReportSnapshot {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let networkState: DiagnosticsNetworkState
        if receivingPaused {
            networkState = .paused
        } else {
            networkState = switch advertisement {
            case .published: .ready
            case .paused: .paused
            case .failed: .unavailable
            case .starting, .idle: .starting
            }
        }
        return DiagnosticsReportSnapshot(
            appVersion: version,
            buildNumber: build,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            architecture: Self.processArchitecture,
            networkState: networkState,
            outgoingState: outgoingPhase,
            incomingTransferCount: incoming.count,
            outgoingTransferCount: sending ? 1 : 0,
            lastErrorCategory: lastDiagnosticsErrorCategory
        )
    }

    private static var processArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "other"
        #endif
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
        guard let attemptID = activeOutgoingAttemptID else { return }
        receiveOutgoingFailure(error, attemptID: attemptID)
    }
    func transferAccepted() {
        guard let attemptID = activeOutgoingAttemptID else { return }
        receiveOutgoingAccepted(attemptID: attemptID)
    }
    func transferProgress(progress: Double) {
        guard let attemptID = activeOutgoingAttemptID else { return }
        receiveOutgoingProgress(progress, attemptID: attemptID)
    }
    func transferFinished() {
        guard let attemptID = activeOutgoingAttemptID else { return }
        receiveOutgoingFinished(attemptID: attemptID)
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

    @MainActor
    func enableDefaultLaunchAtLoginIfNeeded() {
        guard #available(macOS 13.0, *) else { return }
        guard !UserDefaults.standard.bool(forKey: Self.launchAtLoginDisabledByUserKey) else {
            updateLaunchAtLoginStatus()
            return
        }
        guard isInstalledInApplicationsFolder else {
            updateLaunchAtLoginStatus()
            return
        }

        if SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
                launchAtLoginMessage = nil
            } catch {
                launchAtLoginMessage = "Could not enable Launch at Login: \(error.localizedDescription)"
            }
        }
        updateLaunchAtLoginStatus()
        if SMAppService.mainApp.status == .requiresApproval {
            launchAtLoginMessage = "Allow Nearby Drop in System Settings → General → Login Items."
        }
    }

    @MainActor
    func toggleLaunchAtLogin(enabled: Bool) {
        guard isInstalledInApplicationsFolder else {
            launchAtLoginMessage = enabled
                ? "Move Nearby Drop to Applications before enabling Launch at Login."
                : "Open the installed copy of Nearby Drop to change this setting."
            updateLaunchAtLoginStatus()
            return
        }

        launchAtLoginMessage = nil
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
                UserDefaults.standard.set(!enabled, forKey: Self.launchAtLoginDisabledByUserKey)
            } catch {
                launchAtLoginMessage = "Could not update Launch at Login: \(error.localizedDescription)"
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            if SMAppService.mainApp.status == .requiresApproval {
                launchAtLoginMessage = "Allow Nearby Drop in System Settings → General → Login Items."
            }
        }
    }

    private var isInstalledInApplicationsFolder: Bool {
        let installedBundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        return applicationRoots.contains { root in
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            return installedBundlePath.hasPrefix(rootPath + "/")
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

private final class OutgoingAttemptDelegate: ShareExtensionDelegate {
    private weak var model: TransferModel?
    private let attemptID: UUID

    init(model: TransferModel, attemptID: UUID) {
        self.model = model
        self.attemptID = attemptID
    }

    func addDevice(device: RemoteDeviceInfo) { model?.addDevice(device: device) }
    func removeDevice(id: String) { model?.removeDevice(id: id) }
    func startTransferWithQrCode(device: RemoteDeviceInfo) { model?.startTransferWithQrCode(device: device) }
    func connectionWasEstablished(pinCode: String) { model?.receiveOutgoingConnectionEstablished(pinCode: pinCode, attemptID: attemptID) }
    func connectionFailed(with error: Error) { model?.receiveOutgoingFailure(error, attemptID: attemptID) }
    func transferAccepted() { model?.receiveOutgoingAccepted(attemptID: attemptID) }
    func transferProgress(progress: Double) { model?.receiveOutgoingProgress(progress, attemptID: attemptID) }
    func transferFinished() { model?.receiveOutgoingFinished(attemptID: attemptID) }
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

            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Transfer complete")
                    .font(.system(size: 16, weight: .semibold))
                Text(completed.fileCount > 1
                     ? "Received \(completed.fileCount) files."
                     : "Received \(completed.fileName).")
                    .font(NearbyTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                     .multilineTextAlignment(.center)
                     .padding(.horizontal, 16)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Transfer complete")
            .accessibilityValue(completed.fileCount > 1 ? "Received \(completed.fileCount) files" : "Received \(completed.fileName)")

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
            .nearbyCardSurface(cornerRadius: 7)

            Button("Show in Finder") {
                if let url = completed.fileURL, FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    TransferModel.openDownloads()
                }
            }
            .buttonStyle(.nearbyFullWidthPrimary)
            .frame(maxWidth: .infinity)

            Button("Done") {
                withAnimation(.easeInOut(duration: 0.2)) { model.clearCompletedTransfer() }
            }
            .buttonStyle(.nearbyFullWidthSecondary)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .nearbyCardSurface(cornerRadius: 14)
    }
}

struct TransferErrorCard: View {
    let error: String
    @ObservedObject var model: TransferModel
    @ObservedObject var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 6)

            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 38))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("Couldn’t save the file")
                .font(.system(size: 16, weight: .semibold))

            Text(error)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 20)
                .accessibilityLabel("Transfer error")

            if let failed = model.lastFailedIncoming {
                VStack(spacing: 0) {
                    ForEach(Array(failed.transfer.files.prefix(3).enumerated()), id: \.offset) { index, file in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.system(size: 13)).foregroundStyle(theme.presentationAccent)
                                .frame(width: 28, height: 28)
                                .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).font(NearbyTypography.emphasizedMetadata).lineLimit(1)
                                Text(TransferModel.formatBytes(file.size)).font(NearbyTypography.metadata).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 3)
                        }
                        .padding(7)
                        if index < min(failed.transfer.files.count, 3) - 1 { Divider().padding(.leading, 42) }
                    }
                }
                .nearbyControlSurface(cornerRadius: 9)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 1))

                Label("Some files may already be saved. Check the download folder.", systemImage: "exclamationmark.circle")
                    .font(NearbyTypography.metadata).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                Button("Open Downloads", action: TransferModel.openDownloads)
                    .buttonStyle(.nearbyFullWidthSecondary)
                    .frame(maxWidth: .infinity)
                Button("Done", role: .cancel) {
                    withAnimation(.easeInOut(duration: 0.2)) { model.clearCompletedTransfer() }
                }
                .buttonStyle(.nearbyFullWidthPrimary)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .nearbyCardSurface(cornerRadius: 14)
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
            Text("Receiving from \(item.device.name)")
                .font(.system(size: 14, weight: .semibold)).lineLimit(1)

            if !item.transfer.files.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(item.transfer.files.prefix(3).enumerated()), id: \.offset) { index, file in
                        HStack(spacing: 7) {
                            Image(systemName: "doc").font(.system(size: 12)).foregroundStyle(theme.presentationAccent)
                                .frame(width: 27, height: 28)
                                .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name).font(NearbyTypography.emphasizedMetadata).lineLimit(1)
                                Text(TransferModel.formatBytes(file.size)).font(NearbyTypography.metadata).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 2)
                        }
                        .padding(7)
                        if index < min(item.transfer.files.count, 3) - 1 { Divider().padding(.leading, 41) }
                    }
                }
                .nearbyControlSurface(cornerRadius: 9)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 1))
            } else if let description = item.transfer.textDescription {
                Text(description).font(.system(size: 10)).foregroundStyle(.secondary)
            }

            let progress = model.incomingProgress[id]
            let fraction = totalBytes > 0 ? Double(progress?.bytes ?? 0) / Double(totalBytes) : 0
            HStack {
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                Spacer()
                Text("\(TransferModel.formatBytes(progress?.bytes ?? 0)) of \(TransferModel.formatBytes(totalBytes))")
                    .font(NearbyTypography.metadata).foregroundStyle(.secondary).monospacedDigit()
            }

            ProgressView(value: totalBytes > 0 ? fraction : nil)
                .progressViewStyle(.linear)
                .accessibilityLabel("Receiving files from \(item.device.name)")
                .accessibilityValue(totalBytes > 0 ? "\(Int(fraction * 100)) percent" : "In progress")

            HStack {
                if let progress, progress.bytesPerSecond > 0 {
                    Text("\(TransferModel.formatBytes(Int64(progress.bytesPerSecond)))/s")
                    Text("·")
                    let remainingBytes = max(Int64(0), totalBytes - progress.bytes)
                    Text("About \(max(1, Int(Double(remainingBytes) / progress.bytesPerSecond))) sec remaining")
                }
                Text("Saving")
                Spacer()
            }
            .font(NearbyTypography.metadata).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Transfer status")
            .accessibilityValue(progress.map { "\(TransferModel.formatBytes($0.bytes)) received" } ?? "Preparing")

            Button("Cancel transfer", role: .cancel) {
                model.cancelIncomingTransfer(id)
            }
            .buttonStyle(.nearbyCompactFullWidthSecondary).frame(maxWidth: .infinity)
        }
        .padding(12)
        .nearbyCardSurface(cornerRadius: 12)
    }
}
