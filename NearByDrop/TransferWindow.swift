import Cocoa
import SwiftUI
import NearbyShare
import CoreImage.CIFilterBuiltins
import ServiceManagement
import WebKit

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

final class TransferModel: NSObject, ObservableObject, ShareExtensionDelegate {
    enum Tab: String, CaseIterable { case send = "Send", receive = "Receive", usb = "USB" }
    @Published var tab: Tab = .send
    @Published var urls: [URL] = []
    @Published var devices: [RemoteDeviceInfo] = []
    @Published var advertisement = NearbyConnectionManager.AdvertisementState.idle
    @Published var scanning = false
    @Published var qrImage: NSImage?
    @Published var showingQR = false
    @Published var waitingForQR = false
    @Published var incoming: [String: TransferInfo] = [:]
    @Published var accepted: Set<String> = []
    @Published var receiveMessage = ""
    @Published var sendMessage = ""
    @Published var progress: Double = 0
    @Published var sending = false
    @Published var recipient = ""
    @Published var error: String?

    // Folder & relative path transfers
    @Published var displayNames: [String] = []
    private(set) var totalBytes: Int64 = 0

    // Transfer speed and ETA
    @Published var transferSpeed: String = ""
    @Published var timeRemaining: String = ""
    private var speedSamples: [(time: Date, bytes: Int64)] = []

    // Preferences & persistence
    @Published var downloadDirectory: URL = NearbyConnectionManager.downloadDirectory
    @Published var launchAtLogin: Bool = false
    @Published var trustedDevices: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "trustedDevices") ?? [])
    @Published var history: [TransferHistoryItem] = []
    private static let historyKey = "transferHistory"

    let usb = USBModel()
    let deviceName = Host.current().localizedName ?? "This Mac"
    weak var window: NSWindow?
    var onConsent: ((String, Bool) -> Void)?
    private var chosenID: String?
    private var scopedURLs: [URL] = []
    private var qrExpiry: DispatchWorkItem?
    private var timeout: DispatchWorkItem?
    private var adDebounce: DispatchWorkItem?

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
    private let qrDownloader = QuickShareDownloader()

    override init() {
        super.init()
        loadHistory()
        updateLaunchAtLoginStatus()
        NearbyConnectionManager.shared.startDeviceDiscovery()
        NearbyConnectionManager.shared.addShareExtensionDelegate(self)
        setupQRDownloader()
    }

    private func setupQRDownloader() {
        qrDownloader.onMetadata = { [weak self] sender, desc in
            guard let self = self else { return }
            let s = sender.isEmpty ? "Phone" : sender
            self.qrStatus = .downloading(sender: s, description: desc.isEmpty ? nil : desc)
        }
        qrDownloader.onProgress = { [weak self] message in
            guard let self = self else { return }
            if case .connecting(let s) = self.qrStatus {
                self.qrStatus = .downloading(sender: s ?? "Phone", description: message)
            }
        }
        qrDownloader.onFileReceived = { [weak self] filename, url in
            guard let self = self else { return }
            self.qrExpiry?.cancel()
            if case .completed(_, let count) = self.qrStatus {
                self.qrStatus = .completed(filename: filename, count: count + 1)
            } else {
                self.qrStatus = .completed(filename: filename, count: 1)
            }
            self.receiveMessage = "Saved \(filename) to Downloads"
        }
        qrDownloader.onError = { [weak self] error in
            guard let self = self else { return }
            self.qrStatus = .failed(error: error)
        }
    }

    private func expandFilesAndDirectories(_ inputURLs: [URL]) -> (urls: [URL], displayNames: [String]) {
        var flatURLs: [URL] = []
        var names: [String] = []
        let fm = FileManager.default

        for url in inputURLs {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let parentURL = url.deletingLastPathComponent()
                let parentPath = parentURL.path
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        var subIsDir: ObjCBool = false
                        if fm.fileExists(atPath: fileURL.path, isDirectory: &subIsDir), !subIsDir.boolValue {
                            flatURLs.append(fileURL)
                            var relPath = fileURL.path
                            if relPath.hasPrefix(parentPath) {
                                relPath = String(relPath.dropFirst(parentPath.count))
                                if relPath.hasPrefix("/") { relPath = String(relPath.dropFirst()) }
                            } else {
                                relPath = fileURL.lastPathComponent
                            }
                            names.append(relPath)
                        }
                    }
                }
            } else {
                flatURLs.append(url)
                names.append(url.lastPathComponent)
            }
        }
        return (flatURLs, names)
    }

    func setFiles(_ newURLs: [URL]) {
        guard !sending, !usb.busy else { return }
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedURLs = newURLs.filter { $0.startAccessingSecurityScopedResource() }
        let (expanded, names) = expandFilesAndDirectories(newURLs)
        urls = expanded
        displayNames = names
        totalBytes = expanded.reduce(0) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
        sendMessage = ""
        error = nil
        resetSpeedTracking()
    }

    func chooseFiles() {
        chooseFiles(thenSendTo: nil)
    }

    func chooseFiles(thenSendTo device: RemoteDeviceInfo?, thenShowQR: Bool = false) {
        guard !sending, !usb.busy else { return }
        scanning = false
        showingQR = false
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard result == .OK, let self else { return }
            self.setFiles(panel.urls)
            self.window?.makeKeyAndOrderFront(nil)
            if let device = device {
                self.send(to: device)
            } else if thenShowQR {
                self.showQR()
            }
        }
        if let window = self.window, window.isVisible, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            let result = panel.runModal()
            handler(result)
        }
    }
    func send(to device: RemoteDeviceInfo) {
        guard !sending, !urls.isEmpty, let id = device.id else { return }
        chosenID = id
        recipient = device.name
        sending = true
        showingQR = false
        progress = 0
        error = nil
        resetSpeedTracking()
        sendMessage = "Connecting…"
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.sending else { return }
            self.cancelSend()
            self.error = "The phone did not respond. Open Quick Share in Receive mode and try again."
        }
        timeout?.cancel(); timeout = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: expiry)
        NearbyConnectionManager.shared.startOutgoingTransfer(deviceID: id, delegate: self, urls: urls, displayNames: displayNames.isEmpty ? nil : displayNames)
        NearbyConnectionManager.shared.clearQrCodeKey()
    }
    func cancelSend() {
        timeout?.cancel()
        if let id = chosenID { NearbyConnectionManager.shared.cancelOutgoingTransfer(id: id) }
        chosenID = nil; sending = false; sendMessage = "Canceled"
        resetSpeedTracking()
    }
    func showQR() {
        guard !urls.isEmpty, !sending else { return }
        let key = NearbyConnectionManager.shared.generateQrCodeKey()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("https://quickshare.google/qrcode#key=\(key)".utf8)
        filter.correctionLevel = "M"
        if let output = filter.outputImage, let cg = CIContext().createCGImage(output.transformed(by: .init(scaleX: 8, y: 8)), from: output.extent.applying(.init(scaleX: 8, y: 8))) {
            qrImage = NSImage(cgImage: cg, size: NSSize(width: 240, height: 240))
            showingQR = true
        }
    }
    func dismissQR() { NearbyConnectionManager.shared.clearQrCodeKey(); showingQR = false; qrImage = nil }
    func scan(_ value: String) -> String? {
        guard let url = URL(string: value) else { return "Invalid QR code" }
        lastScannedURL = url
        do {
            try NearbyConnectionManager.shared.receiveQRCode(value)
            scanning = false
            waitingForQR = true
            if url.host == "quickshare.google" || url.host == "www.quickshare.google" {
                qrStatus = .connecting(sender: nil)
                qrDownloader.start(url: url, inWindow: window)
            } else {
                receiveMessage = "Waiting for sender to connect…"
            }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: expiry)
            window?.makeKeyAndOrderFront(nil)
            return nil
        } catch { return Self.errorMessage(error) }
    }
    func stopQRReceive() {
        qrExpiry?.cancel()
        waitingForQR = false
        qrDownloader.cancel()
        NearbyConnectionManager.shared.stopReceivingQRCode()
    }
    func resetQRTransfer() {
        stopQRReceive()
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
    func startTransferWithQrCode(device: RemoteDeviceInfo) { if showingQR { send(to: device) } }
    func connectionWasEstablished(pinCode: String) { sendMessage = "Confirm code \(pinCode) on \(recipient)" }
    func connectionFailed(with error: Error) { timeout?.cancel(); sending = false; chosenID = nil; self.error = Self.errorMessage(error); sendMessage = ""; resetSpeedTracking() }
    func transferAccepted() { timeout?.cancel(); sendMessage = "Sending to \(recipient)…" }
    func transferProgress(progress: Double) {
        self.progress = min(1, max(0, progress))
        let currentBytes = Int64(Double(totalBytes) * self.progress)
        updateSpeedAndETA(currentBytes: currentBytes, total: totalBytes)
    }
    func transferFinished() {
        timeout?.cancel()
        sending = false
        let peer = recipient
        chosenID = nil
        progress = 1
        sendMessage = "Sent to \(peer)"
        let fileName = displayNames.first ?? urls.first?.lastPathComponent ?? "Files"
        let display = urls.count > 1 ? "\(fileName) (+\(urls.count - 1))" : fileName
        recordTransfer(fileName: display, fileSize: totalBytes, direction: .outgoing, peerName: peer, fileURL: urls.first)
        resetSpeedTracking()
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

    func recordIncoming(info: TransferInfo) {
        let name: String
        if let text = info.transfer.textDescription {
            name = text
        } else if let first = info.transfer.files.first {
            name = info.transfer.files.count > 1 ? "\(first.name) (+\(info.transfer.files.count - 1))" : first.name
        } else {
            name = "Unknown file"
        }
        let total = info.transfer.files.reduce(0) { $0 + $1.size }
        let url: URL? = info.transfer.files.first.map {
            downloadDirectory.appendingPathComponent($0.name)
        }
        recordTransfer(fileName: name, fileSize: total, direction: .incoming, peerName: info.device.name, fileURL: url)
    }

    func isDeviceTrusted(_ device: RemoteDeviceInfo) -> Bool {
        return NearbyConnectionManager.isTrusted(name: device.name, id: device.id) ||
            trustedDevices.contains(device.name) ||
            (device.id != nil && trustedDevices.contains(device.id!))
    }

    func setDeviceTrusted(_ device: RemoteDeviceInfo, trusted: Bool) {
        NearbyConnectionManager.setTrusted(name: device.name, id: device.id, trusted: trusted)
        var list = UserDefaults.standard.stringArray(forKey: "trustedDevices") ?? []
        let key = NearbyConnectionManager.trustedDeviceKey(name: device.name, id: device.id)
        if trusted {
            if !list.contains(key) { list.append(key) }
            if !list.contains(device.name) { list.append(device.name) }
            if let id = device.id, !list.contains(id) { list.append(id) }
            trustedDevices.insert(device.name)
            if let id = device.id { trustedDevices.insert(id) }
        } else {
            list.removeAll { $0 == key || $0 == device.name || (device.id != nil && $0 == device.id) }
            trustedDevices.remove(device.name)
            if let id = device.id { trustedDevices.remove(id) }
        }
        UserDefaults.standard.set(list, forKey: "trustedDevices")
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a download folder for received files"
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard result == .OK, let url = panel.url, let self = self else { return }
            _ = url.startAccessingSecurityScopedResource()
            NearbyConnectionManager.downloadDirectory = url
            self.downloadDirectory = url
        }
        if let window = self.window, window.isVisible, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            let result = panel.runModal()
            handler(result)
        }
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
        if let error = error as? NearbyError {
            switch error {
            case .protocolError(let message): return message
            case .inputOutput: return "The connection was interrupted. Try again."
            case .canceled: return "The transfer was declined or canceled."
            default: return "Could not connect securely. Try again."
            }
        }
        return error.localizedDescription
    }
    static func openDownloads() {
        NSWorkspace.shared.open(NearbyConnectionManager.downloadDirectory)
    }
}

final class TransferWindowController: NSWindowController {
    init(model: TransferModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 530), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "NearByDrop"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 480)
        window.setFrameAutosaveName("Transfers")
        window.contentView = NSHostingView(rootView: TransferView(model: model))
        window.center()
        model.window = window
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}

struct PrimaryAction: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderedProminent)
            .tint(.blue)
    }
}
struct NavigationSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency { content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16)) }
        else if #available(macOS 26, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16)) }
        else { content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
    }
}
struct StatusLabel: View {
    @ObservedObject var model: TransferModel
    var body: some View {
        Label {
            Text(!model.incoming.isEmpty ? "Receiving" : model.advertisement == .published ? "Ready to receive" : model.advertisement == .failed ? "Network unavailable" : "Connecting…")
        } icon: {
            Image(systemName: model.advertisement == .failed ? "wifi.slash" : "circle.fill")
                .font(.system(size: 8)).foregroundStyle(model.advertisement == .published ? Color.green : Color.secondary)
        }.font(.callout).foregroundStyle(.secondary)
    }
}
struct TransferView: View {
    @ObservedObject var model: TransferModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NearByDrop").font(.system(size: 22, weight: .semibold))
                    Text("Created by Arslan Basharat").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: TransferModel.openDownloads) { Image(systemName: "folder").frame(width: 26, height: 26) }
                    .buttonStyle(.bordered).help("Open Downloads").accessibilityLabel("Open Downloads")
            }.padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 16)
            Picker("Transfer method", selection: $model.tab) {
                ForEach(TransferModel.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(8).modifier(NavigationSurface()).padding(.horizontal, 28).padding(.bottom, 20)
            Group {
                switch model.tab {
                case .send: sendView
                case .receive: receiveView
                case .usb: USBView(usb: model.usb, files: model.urls, chooseFiles: model.chooseFiles)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                StatusLabel(model: model)
                Text("•").foregroundStyle(.quaternary)
                Text("Visible as \"\(model.deviceName)\"").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("Quick Share & Nearby Share").font(.caption).foregroundStyle(.tertiary)
            }.padding(.horizontal, 28).padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.scanning) { QRScannerView(onCode: model.scan) }
        .sheet(isPresented: $model.showingQR, onDismiss: model.dismissQR) {
            VStack(spacing: 20) {
                Text("Scan to receive").font(.title2.weight(.semibold))
                Text("Scan this code with your phone’s camera.").foregroundStyle(.secondary)
                if let image = model.qrImage { Image(nsImage: image).interpolation(.none).resizable().frame(width: 240, height: 240).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16)) }
                Button("Done", action: model.dismissQR).keyboardShortcut(.cancelAction)
            }.padding(28).frame(width: 380)
        }
    }
    private var sendView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: model.urls.count > 1 ? "doc.on.doc" : "doc").font(.system(size: 28)).foregroundStyle(.blue).frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.urls.isEmpty ? "Choose what to send" : model.urls.count == 1 ? model.urls[0].lastPathComponent : "\(model.urls.count) files selected").font(.headline).lineLimit(2)
                    Text(model.urls.isEmpty ? "Drag files here or click Choose." : "Ready to share").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(model.urls.isEmpty ? "Choose Files…" : "Change…") { model.chooseFiles() }.modifier(PrimaryAction()).disabled(model.sending || model.usb.busy)
            }
            Divider()
            if model.sending {
                VStack(alignment: .leading, spacing: 16) {
                    Label(model.recipient, systemImage: "iphone").font(.title3.weight(.semibold))
                    ProgressView(value: model.progress)
                    HStack {
                        Text(model.sendMessage).foregroundStyle(.secondary)
                        Spacer()
                        if !model.transferSpeed.isEmpty {
                            Text(model.transferSpeed)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if !model.timeRemaining.isEmpty {
                            Text("• \(model.timeRemaining)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Button("Cancel", action: model.cancelSend)
                    }
                }.padding(.vertical, 8)
                Spacer()
            } else {
                HStack {
                    Text("Nearby devices").font(.headline)
                    Spacer()
                    Button {
                        if model.urls.isEmpty {
                            model.chooseFiles(thenSendTo: nil, thenShowQR: true)
                        } else {
                            model.showQR()
                        }
                    } label: {
                        Label("Show QR Code", systemImage: "qrcode")
                    }
                }
                if model.devices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("Looking for devices").font(.headline)
                        Text("Open Quick Share in Receive mode on your phone.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.devices, id: \.id) { device in
                                Button {
                                    if model.urls.isEmpty {
                                        model.chooseFiles(thenSendTo: device)
                                    } else {
                                        model.send(to: device)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: device.type == .computer ? "laptopcomputer" : "iphone").font(.title2).frame(width: 36)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.name).font(.headline)
                                            Text(model.urls.isEmpty ? "Click to choose files and send" : "Click to send").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                                    }.padding(14).frame(maxWidth: .infinity).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !model.sendMessage.isEmpty { Label(model.sendMessage, systemImage: model.progress == 1 ? "checkmark.circle.fill" : "info.circle").foregroundStyle(.secondary) }
            }
            if let error = model.error { Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
        }
        .padding(.horizontal, 28).padding(.bottom, 20)
        .dropDestination(for: URL.self) { items, _ in
            guard !items.isEmpty else { return false }
            model.setFiles(items)
            return true
        }
    }
    private var receiveView: some View {
        Group {
            if model.qrStatus != .idle {
                VStack(spacing: 18) {
                    switch model.qrStatus {
                    case .connecting(let sender):
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(.blue)
                            .padding(.top, 28)
                        Text(sender ?? "Connecting to phone…")
                            .font(.title2.weight(.semibold))
                        ProgressView()
                            .controlSize(.regular)
                        Text("Preparing transfer…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Cancel", action: model.resetQRTransfer)
                            .buttonStyle(.bordered)
                            .padding(.top, 8)

                    case .downloading(let sender, let description):
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(.blue)
                            .padding(.top, 28)
                        Text(sender)
                            .font(.title2.weight(.semibold))
                        if let desc = description {
                            Text(desc)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView()
                            .controlSize(.regular)
                        Text("Downloading to Downloads folder…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Cancel", action: model.resetQRTransfer)
                            .buttonStyle(.bordered)
                            .padding(.top, 8)

                    case .completed(let filename, let count):
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.green)
                            .padding(.top, 28)
                        Text("Transfer Complete")
                            .font(.title2.weight(.semibold))
                        Text(count > 1 ? "\(count) files saved to Downloads folder" : "\(filename) saved to Downloads folder")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Done", action: model.resetQRTransfer)
                            Button("Open Downloads", action: TransferModel.openDownloads)
                                .modifier(PrimaryAction())
                        }
                        .padding(.top, 12)

                    case .failed(let error):
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(.red)
                            .padding(.top, 28)
                        Text("Transfer Failed")
                            .font(.title2.weight(.semibold))
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again", action: model.resetQRTransfer)
                            .modifier(PrimaryAction())
                            .padding(.top, 8)

                    case .idle:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        if model.incoming.isEmpty {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 46, weight: .light))
                                .foregroundStyle(.blue)
                                .padding(.top, 20)
                            Text("Send to this Mac")
                                .font(.title2.weight(.semibold))
                            Text("Choose \(model.deviceName) in Quick Share or scan a code.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button { model.scanning = true } label: {
                                Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            }
                            .modifier(PrimaryAction())
                            .controlSize(.large)
                            if !model.receiveMessage.isEmpty {
                                Text(model.receiveMessage)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Connecting from Android:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "switch.2")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.blue)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Quick Settings Tile")
                                            .font(.caption.weight(.medium))
                                        Text("Swipe down on Android and tap Quick Share to turn on discovery.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "qrcode")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.blue)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("QR Code Pairing")
                                            .font(.caption.weight(.medium))
                                        Text("Tap the QR icon in Android Quick Share, then click Scan QR Code above.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "wifi")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.blue)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Same Wi-Fi Network")
                                            .font(.caption.weight(.medium))
                                        Text("Both devices must be on the same local network.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.top, 6)
                        } else {
                            ForEach(model.incoming.keys.sorted(), id: \.self) { id in
                                if let item = model.incoming[id] {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Label(item.device.name, systemImage: "iphone").font(.headline)
                                        Text(item.transfer.textDescription ?? item.transfer.files.map(\.name).joined(separator: ", ")).lineLimit(4)
                                        if model.accepted.contains(id) { ProgressView("Receiving…") }
                                        else {
                                            Text("Confirm code \(item.transfer.pinCode ?? "—")").font(.title3.monospacedDigit())
                                            Toggle("Trust this device (auto-accept)", isOn: Binding(
                                                get: { model.isDeviceTrusted(item.device) },
                                                set: { model.setDeviceTrusted(item.device, trusted: $0) }
                                            ))
                                            .toggleStyle(.checkbox)
                                            .font(.callout)
                                            HStack { Spacer(); Button("Decline") { model.onConsent?(id, false) }; Button("Accept") { model.onConsent?(id, true) }.modifier(PrimaryAction()) }
                                        }
                                    }.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                        }

                        // Custom download location card
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text("Download folder: \(model.downloadDirectory.lastPathComponent)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Change…") {
                                model.chooseDownloadDirectory()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                        // Recent Transfers
                        if !model.history.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Recent Transfers")
                                        .font(.headline)
                                    Spacer()
                                }
                                VStack(spacing: 6) {
                                    ForEach(model.history.prefix(5)) { item in
                                        HStack(spacing: 12) {
                                            Image(systemName: item.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(item.direction == .incoming ? Color.green : Color.blue)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.fileName)
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                                Text("\(item.peerName) • \(TransferModel.formatBytes(item.fileSize)) • \(TransferModel.formatDate(item.timestamp))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            if let url = item.fileURL {
                                                Button("Show in Finder") {
                                                    if FileManager.default.fileExists(atPath: url.path) {
                                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                                    } else {
                                                        TransferModel.openDownloads()
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.mini)
                                            }
                                        }
                                        .padding(10)
                                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity).padding(.horizontal, 28).padding(.bottom, 24)
                }
            }
        }
    }
}

final class QuickShareDownloader: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    private var webView: WKWebView?
    var onMetadata: ((_ sender: String, _ description: String) -> Void)?
    var onProgress: ((_ message: String) -> Void)?
    var onFileReceived: ((_ filename: String, _ url: URL) -> Void)?
    var onError: ((_ error: String) -> Void)?
    private var downloadedFiles: [URL] = []
    private var downloadDestinations: [WKDownload: URL] = [:]

    func start(url: URL, inWindow: NSWindow? = nil) {
        cancel()

        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(self, name: "nearbyDrop")

        let scriptSource = """
        const origLog = console.log;
        console.log = function(...args) {
            try {
                window.webkit.messageHandlers.nearbyDrop.postMessage({
                    type: "log",
                    msg: args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ')
                });
            } catch(e) {}
            origLog.apply(console, args);
        };
        const origErr = console.error;
        console.error = function(...args) {
            try {
                window.webkit.messageHandlers.nearbyDrop.postMessage({
                    type: "log",
                    msg: "ERROR: " + args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ')
                });
            } catch(e) {}
            origErr.apply(console, args);
        };

        const capturedBlobs = new Map();
        const origCreate = URL.createObjectURL;
        URL.createObjectURL = function(obj) {
            const u = origCreate.apply(URL, arguments);
            if (obj instanceof Blob) {
                capturedBlobs.set(u, obj);
            }
            return u;
        };

        const origRevoke = URL.revokeObjectURL;
        URL.revokeObjectURL = function(u) {
            setTimeout(() => {
                capturedBlobs.delete(u);
                origRevoke.call(URL, u);
            }, 45000);
        };

        function sendBlob(blob, name) {
            if (!blob) return;
            const fname = name || "QuickShare_" + Date.now();
            const reader = new FileReader();
            reader.onload = function() {
                const res = reader.result;
                const base64 = (typeof res === "string" && res.includes(",")) ? res.split(",")[1] : "";
                window.webkit.messageHandlers.nearbyDrop.postMessage({
                    type: "file_data",
                    filename: fname,
                    base64: base64
                });
            };
            reader.readAsDataURL(blob);
        }

        const customShare = async function(data) {
            if (data && data.files && data.files.length > 0) {
                for (let i = 0; i < data.files.length; i++) {
                    const f = data.files[i];
                    sendBlob(f, f.name);
                }
                return Promise.resolve();
            }
            return Promise.resolve();
        };
        try {
            Object.defineProperty(navigator, "share", { get: () => customShare, set: () => {}, configurable: true });
            Object.defineProperty(navigator, "canShare", { get: () => ((d) => true), set: () => {}, configurable: true });
        } catch(e) {}

        function handleAnchor(a) {
            if (a && a.href && a.href.startsWith("blob:")) {
                const fname = a.download || a.getAttribute("download") || "QuickShare_file";
                const b = capturedBlobs.get(a.href);
                if (b) {
                    sendBlob(b, fname);
                } else {
                    fetch(a.href).then(r => r.blob()).then(blob => sendBlob(blob, fname)).catch(e => {});
                }
            }
        }

        const origClick = HTMLAnchorElement.prototype.click;
        HTMLAnchorElement.prototype.click = function() {
            handleAnchor(this);
            return origClick.apply(this, arguments);
        };

        document.addEventListener("click", function(e) {
            let t = e.target;
            while (t && t.tagName !== "A") {
                t = t.parentElement;
            }
            if (t && t.tagName === "A") {
                handleAnchor(t);
            }
        }, true);

        let clickedSaveOrShare = false;
        let clickedDownload = false;
        let latestMetaDesc = "";

        function inspect() {
            let sender = "";
            let desc = "";
            const headers = Array.from(document.querySelectorAll("h1, h2, h3, h4, div, span, p"));
            for (const h of headers) {
                const txt = (h.innerText || "").trim();
                if ((txt.includes("Pixel") || txt.includes("Galaxy") || txt.includes("Phone") || txt.includes("’s") || txt.includes("'s")) && txt.length < 50 && !sender) {
                    sender = txt;
                }
                if ((txt.includes("image") || txt.includes("file") || txt.includes("video") || txt.includes("MB") || txt.includes("KB")) && txt.length < 40 && !desc) {
                    desc = txt;
                }
            }
            if (desc) latestMetaDesc = desc;
            if (sender || desc) {
                window.webkit.messageHandlers.nearbyDrop.postMessage({
                    type: "meta",
                    sender: sender,
                    description: desc
                });
            }

            const buttons = Array.from(document.querySelectorAll("button, [role='button'], a.mat-button, a.mat-mdc-button, .mat-mdc-unelevated-button, .mat-mdc-raised-button"));
            for (const b of buttons) {
                const t = (b.innerText || b.textContent || "").trim().toLowerCase();
                if ((t.includes("save or share") || t.includes("accept")) && !clickedSaveOrShare) {
                    clickedSaveOrShare = true;
                    window.webkit.messageHandlers.nearbyDrop.postMessage({ type: "clicking" });
                    b.click();
                    b.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
                }
                if ((t === "download" || t === "save" || t.includes("download file")) && !clickedDownload) {
                    clickedDownload = true;
                    window.webkit.messageHandlers.nearbyDrop.postMessage({ type: "clicking" });
                    b.click();
                    b.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
                }
            }

            if (clickedSaveOrShare && capturedBlobs.size > 0 && !window._nearbyDropSentBlob) {
                for (const [url, blob] of capturedBlobs.entries()) {
                    if (blob.size > 50000) {
                        window._nearbyDropSentBlob = true;
                        sendBlob(blob, latestMetaDesc ? "QuickShare_" + Date.now() : "QuickShare_file");
                        break;
                    }
                }
            }
        }

        const timer = setInterval(inspect, 250);
        setTimeout(() => clearInterval(timer), 120000);
        """

        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(script)
        config.userContentController = ucc
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        self.webView = wv

        if let contentView = inWindow?.contentView {
            wv.frame = NSRect(x: 0, y: 0, width: 2, height: 2)
            wv.alphaValue = 0.02
            contentView.addSubview(wv)
        }

        wv.load(URLRequest(url: url))
    }

    func cancel() {
        webView?.removeFromSuperview()
        webView?.stopLoading()
        webView = nil
        downloadedFiles.removeAll()
        downloadDestinations.removeAll()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "meta":
            let sender = dict["sender"] as? String ?? ""
            let desc = dict["description"] as? String ?? ""
            DispatchQueue.main.async {
                self.onMetadata?(sender, desc)
            }
        case "clicking":
            DispatchQueue.main.async {
                self.onProgress?("Downloading files…")
            }
        case "file_data":
            guard let filename = dict["filename"] as? String,
                  let base64 = dict["base64"] as? String,
                  let data = Data(base64Encoded: base64) else { return }
            saveData(data, filename: filename)
        case "log":
            #if DEBUG
            if let msg = dict["msg"] as? String {
                print("[QuickShareWeb] \(msg)")
            }
            #endif
        default:
            break
        }
    }

    private func saveData(_ data: Data, filename: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let downloadsDir = NearbyConnectionManager.downloadDirectory
            var target = downloadsDir.appendingPathComponent(filename)
            var count = 1
            let base = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            while FileManager.default.fileExists(atPath: target.path) {
                let name = ext.isEmpty ? "\(base) (\(count))" : "\(base) (\(count)).\(ext)"
                target = downloadsDir.appendingPathComponent(name)
                count += 1
            }
            do {
                try data.write(to: target)
                DispatchQueue.main.async {
                    self.downloadedFiles.append(target)
                    self.onFileReceived?(target.lastPathComponent, target)
                }
            } catch {
                DispatchQueue.main.async {
                    self.onError?("Failed to save file: \(error.localizedDescription)")
                }
            }
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
        } else {
            decisionHandler(.allow, preferences)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let downloadsDir = NearbyConnectionManager.downloadDirectory
        var target = downloadsDir.appendingPathComponent(suggestedFilename)
        var count = 1
        let base = (suggestedFilename as NSString).deletingPathExtension
        let ext = (suggestedFilename as NSString).pathExtension
        while FileManager.default.fileExists(atPath: target.path) {
            let name = ext.isEmpty ? "\(base) (\(count))" : "\(base) (\(count)).\(ext)"
            target = downloadsDir.appendingPathComponent(name)
            count += 1
        }
        DispatchQueue.main.async {
            self.downloadDestinations[download] = target
        }
        completionHandler(target)
    }

    func downloadDidFinish(_ download: WKDownload) {
        DispatchQueue.main.async {
            if let dest = self.downloadDestinations[download] {
                self.downloadedFiles.append(dest)
                self.onFileReceived?(dest.lastPathComponent, dest)
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        DispatchQueue.main.async {
            self.onError?(error.localizedDescription)
        }
    }
}
