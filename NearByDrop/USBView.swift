import SwiftUI
import NearbyShare

struct USBItem: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let size: UInt64
    let folder: Bool
}

func fileIconInfo(for name: String, isFolder: Bool) -> (icon: String, color: Color) {
    if isFolder {
        return ("folder.fill", .blue)
    }
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "jpg", "jpeg", "png", "heic", "gif", "webp", "bmp", "raw", "dng":
        return ("photo.fill", .purple)
    case "mp4", "mov", "m4v", "mkv", "avi", "webm", "3gp":
        return ("film.fill", .orange)
    case "mp3", "m4a", "wav", "flac", "aac", "ogg":
        return ("music.note", .pink)
    case "pdf":
        return ("doc.richtext.fill", .red)
    case "txt", "rtf", "md", "csv", "log":
        return ("doc.text.fill", .gray)
    case "zip", "tar", "gz", "rar", "7z":
        return ("archivebox.fill", .brown)
    case "apk":
        return ("app.badge.fill", .green)
    case "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key":
        return ("doc.fill", .blue)
    default:
        return ("doc", .secondary)
    }
}

final class USBModel: ObservableObject {
    @Published var devices: [(id: String, name: String)] = []
    @Published var storages: [(id: UInt32, name: String)] = []
    @Published var storage: UInt32 = 0
    @Published var items: [USBItem] = []
    @Published var path: [(id: UInt32, name: String)] = []
    @Published var deviceName = ""
    @Published var busy = false
    @Published var transferring = false
    @Published var progress = 0.0
    @Published var message = ""
    @Published var error: String?
    @Published var lastDownloadedURL: URL? = nil
    @Published var lastTransferredItems: [USBItem] = []
    @Published var selectedItemIds: Set<UInt32> = []
    @Published var isChoosingFiles = false

    private let bridge = NDUSBTransfer()
    private let queue = DispatchQueue(label: "NearByDrop.USB", qos: .userInitiated)
    private var scopedUploadURLs: [URL] = []
    private var visitedFolders: Set<UInt32> = []
#if DEBUG
    var isPreviewFixture = false
#endif
    private var discoveryGeneration = UUID()
    var parent: UInt32 { path.last?.id ?? UInt32.max }

    deinit {
        scopedUploadURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    func toggleSelection(_ id: UInt32) {
        if selectedItemIds.contains(id) {
            selectedItemIds.remove(id)
        } else {
            selectedItemIds.insert(id)
        }
    }

    func selectAll() {
        selectedItemIds = Set(items.map(\.id))
    }

    func deselectAll() {
        selectedItemIds.removeAll()
    }

    func refresh() {
#if DEBUG
        guard !isPreviewFixture else { return }
#endif
        guard !busy else { return }
        if !deviceName.isEmpty { load(); return }
        busy = true; error = nil; message = "Looking for USB devices…"
        let generation = UUID()
        discoveryGeneration = generation
        selectedItemIds.removeAll()
        lastDownloadedURL = nil
        queue.async {
            self.bridge.close()
            do {
                let values = try self.bridge.devices()
                let devices = values.compactMap { value -> (id: String, name: String)? in
                    guard let id = value["id"] as? String, let name = value["name"] as? String else { return nil }; return (id, name)
                }
                DispatchQueue.main.async {
                    guard self.discoveryGeneration == generation else { return }
                    self.devices = devices; self.deviceName = ""; self.items = []; self.storages = []; self.storage = 0; self.path = []; self.busy = false; self.message = ""
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.discoveryGeneration == generation else { return }
                    self.fail(error)
                }
            }
        }
    }

    func cancelDiscovery() {
        guard deviceName.isEmpty, busy, !transferring else { return }
        discoveryGeneration = UUID()
        busy = false
        message = ""
    }

    func connect(_ id: String, name: String) {
        guard !busy else { return }
        deviceName = ""; storages = []; storage = 0; items = []; path = []
        busy = true; error = nil; message = "Opening \(name)…"
        selectedItemIds.removeAll()
        lastDownloadedURL = nil
        queue.async {
            do {
                let values = try self.bridge.openDevice(id)
                let storages = values.compactMap { value -> (id: UInt32, name: String)? in
                    guard let id = value["id"] as? NSNumber, let name = value["name"] as? String else { return nil }; return (id.uint32Value, name)
                }
                DispatchQueue.main.async {
                    self.storages = storages; self.deviceName = name; self.path = []; self.busy = false; self.message = ""
                    if let first = storages.first { self.storage = first.id; self.load() }
                    else { self.error = "No storage is available. Unlock your phone and choose File Transfer." }
                }
            } catch { self.fail(error) }
        }
    }

    func load() {
        guard !busy, storage != 0 else { return }
        busy = true; error = nil
        selectedItemIds.removeAll()
        lastDownloadedURL = nil
        let storage = storage, parent = parent
        queue.async {
            do {
                let values = try self.bridge.files(inStorage: storage, parent: parent)
                let items = values.compactMap { value -> USBItem? in
                    guard let id = value["id"] as? NSNumber, let name = value["name"] as? String else { return nil }
                    return USBItem(id: id.uint32Value, name: name, size: (value["size"] as? NSNumber)?.uint64Value ?? 0, folder: (value["folder"] as? NSNumber)?.boolValue ?? false)
                }.sorted { $0.folder != $1.folder ? $0.folder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                DispatchQueue.main.async { self.items = items; self.busy = false }
            } catch { self.fail(error) }
        }
    }

    func enter(_ item: USBItem) {
        guard !busy else { return }
        selectedItemIds.removeAll()
        path.append((item.id, item.name))
        load()
    }

    func back() {
        guard !busy else { return }
        selectedItemIds.removeAll()
        if !path.isEmpty { path.removeLast() }
        load()
    }

    func jumpToRoot() {
        guard !busy, !path.isEmpty else { return }
        selectedItemIds.removeAll()
        path.removeAll()
        load()
    }

    func jumpTo(index: Int) {
        guard !busy, index >= 0, index < path.count - 1 else { return }
        selectedItemIds.removeAll()
        path = Array(path.prefix(index + 1))
        load()
    }

    private func prepareTransfer(_ message: String, items: [USBItem] = []) {
        busy = true; transferring = true; error = nil; progress = 0; self.message = message
        lastTransferredItems = items
        visitedFolders.removeAll()
        bridge.cancelRequested = false
        var lastUpdate = DispatchTime.now()
        bridge.progress = { [weak self] progress in
            let now = DispatchTime.now()
            guard progress >= 1 || now > lastUpdate + .milliseconds(100) else { return }
            lastUpdate = now
            DispatchQueue.main.async { self?.progress = progress }
        }
    }

    func upload(_ urls: [URL], to targetParent: UInt32? = nil) {
        guard !busy, storage != 0, !urls.isEmpty else { return }
        let storage = storage
        let parent = targetParent ?? self.parent
        scopedUploadURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        var accessibleURLs: [URL] = []
        var acquiredScopes: [URL] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                acquiredScopes.append(url)
            }
            guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
                acquiredScopes.forEach { $0.stopAccessingSecurityScopedResource() }
                error = "Could not access one or more selected files. Choose them again and retry."
                return
            }
            accessibleURLs.append(url)
        }
        scopedUploadURLs = acquiredScopes
        prepareTransfer("Sending \(urls.count) file\(urls.count == 1 ? "" : "s")…")
        queue.async {
            defer {
                DispatchQueue.main.async {
                    self.scopedUploadURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                    self.scopedUploadURLs.removeAll()
                }
            }
            var sent = 0
            do {
                for url in accessibleURLs {
                    if self.bridge.cancelRequested { throw NSError(domain: "USB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Canceled"]) }
                    try self.bridge.upload(url, storage: storage, parent: parent)
                    sent += 1
                }
                DispatchQueue.main.async { self.busy = false; self.transferring = false; self.message = "Sent \(sent) file\(sent == 1 ? "" : "s") to phone"; self.load() }
            } catch { self.fail(error, prefix: sent > 0 ? "\(sent) files sent. " : "") }
        }
    }

    func chooseAndUploadFiles(to folder: USBItem? = nil) {
        guard !busy, storage != 0 else { return }
        isChoosingFiles = true
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Upload"
        panel.message = "Choose files to send to your phone"
        panel.presentForInteraction { [weak self] response in
            DispatchQueue.main.async {
                self?.isChoosingFiles = false
                NotificationCenter.default.post(name: .didFinishChoosingFiles, object: nil)
            }
            guard response == .OK, !panel.urls.isEmpty else { return }
            self?.upload(panel.urls, to: folder?.id)
        }
    }

    func download(_ item: USBItem) {
        guard !busy, !item.folder else { return }
        let downloads = NearbyConnectionManager.downloadDirectory
        prepareTransfer("Receiving \(item.name)…", items: [item])
        queue.async {
            do {
                let savedURL = try self.bridge.download(item.id, name: item.name, directory: downloads)
                DispatchQueue.main.async {
                    self.busy = false
                    self.transferring = false
                    self.message = "Saved \(item.name) to \(downloads.lastPathComponent)"
                    self.lastDownloadedURL = savedURL
                }
            } catch { self.fail(error) }
        }
    }

    func downloadFolder(_ item: USBItem) {
        guard !busy, item.folder else { return }
        let downloads = NearbyConnectionManager.downloadDirectory
        prepareTransfer("Receiving folder \(item.name)…", items: [item])
        queue.async {
            do {
                let folderTarget = try ReceivedFolder.create(in: downloads, name: item.name)
                let count = try self.downloadFolderContents(folderId: item.id, targetDir: folderTarget)
                DispatchQueue.main.async {
                    self.busy = false
                    self.transferring = false
                    self.message = "Saved folder \(item.name) (\(count) file\(count == 1 ? "" : "s"))"
                    self.lastDownloadedURL = folderTarget
                }
            } catch {
                self.fail(error)
            }
        }
    }

    func downloadCurrentFolder() {
        guard !busy, !items.isEmpty else { return }
        let downloads = NearbyConnectionManager.downloadDirectory
        let currentName = path.last?.name ?? "Folder"
        let currentItems = items
        prepareTransfer("Receiving \(currentName)…", items: currentItems)
        queue.async {
            var fileCount = 0
            do {
                let folderTarget = try ReceivedFolder.create(in: downloads, name: currentName)
                for item in currentItems {
                    if self.bridge.cancelRequested { throw NSError(domain: "USB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Canceled"]) }
                    if item.folder {
                        let subURL = try ReceivedFolder.create(in: folderTarget, name: item.name)
                        fileCount += try self.downloadFolderContents(folderId: item.id, targetDir: subURL)
                    } else {
                        _ = try self.bridge.download(item.id, name: item.name, directory: folderTarget)
                        fileCount += 1
                    }
                }
                DispatchQueue.main.async {
                    self.busy = false
                    self.transferring = false
                    self.message = "Saved \(currentName) (\(fileCount) file\(fileCount == 1 ? "" : "s"))"
                    self.lastDownloadedURL = folderTarget
                }
            } catch {
                self.fail(error, prefix: fileCount > 0 ? "\(fileCount) files saved. " : "")
            }
        }
    }

    func downloadSelected() {
        let selected = items.filter { selectedItemIds.contains($0.id) }
        guard !busy, !selected.isEmpty else { return }
        let downloads = NearbyConnectionManager.downloadDirectory
        prepareTransfer("Receiving \(selected.count) item\(selected.count == 1 ? "" : "s")…", items: selected)
        queue.async {
            var fileCount = 0
            do {
                for item in selected {
                    if self.bridge.cancelRequested { throw NSError(domain: "USB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Canceled"]) }
                    if item.folder {
                        let subURL = try ReceivedFolder.create(in: downloads, name: item.name)
                        fileCount += try self.downloadFolderContents(folderId: item.id, targetDir: subURL)
                    } else {
                        _ = try self.bridge.download(item.id, name: item.name, directory: downloads)
                        fileCount += 1
                    }
                }
                DispatchQueue.main.async {
                    self.busy = false
                    self.transferring = false
                    self.message = "Saved \(selected.count) items (\(fileCount) file\(fileCount == 1 ? "" : "s"))"
                    self.selectedItemIds.removeAll()
                    self.lastDownloadedURL = downloads
                }
            } catch {
                self.fail(error, prefix: fileCount > 0 ? "\(fileCount) files saved. " : "")
            }
        }
    }

    private func downloadFolderContents(folderId: UInt32, targetDir: URL, depth: Int = 0) throws -> Int {
        guard depth < 128, visitedFolders.insert(folderId).inserted else {
            throw NSError(domain: "USB", code: 2, userInfo: [NSLocalizedDescriptionKey: "The phone returned a repeated folder or a folder hierarchy that is too deep."])
        }
        if self.bridge.cancelRequested { throw NSError(domain: "USB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Canceled"]) }
        let list = try self.bridge.files(inStorage: self.storage, parent: folderId)
        var count = 0
        for dict in list {
            if self.bridge.cancelRequested { throw NSError(domain: "USB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Canceled"]) }
            guard let id = (dict["id"] as? NSNumber)?.uint32Value,
                  let name = dict["name"] as? String,
                  let isFolder = (dict["folder"] as? NSNumber)?.boolValue else { continue }
            if isFolder {
                let subURL = try ReceivedFolder.create(in: targetDir, name: name)
                count += try self.downloadFolderContents(folderId: id, targetDir: subURL, depth: depth + 1)
            } else {
                _ = try self.bridge.download(id, name: name, directory: targetDir)
                count += 1
            }
        }
        return count
    }

    func saveItemAs(_ item: USBItem) {
        guard !busy, !item.folder else { return }
        isChoosingFiles = true
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.prompt = "Save"
        panel.message = "Choose where to save this file on your Mac"
        panel.presentForInteraction { [weak self] response in
            DispatchQueue.main.async {
                self?.isChoosingFiles = false
                NotificationCenter.default.post(name: .didFinishChoosingFiles, object: nil)
            }
            guard response == .OK, let targetURL = panel.url, let self = self else { return }
            let dir = targetURL.deletingLastPathComponent()
            self.prepareTransfer("Receiving \(item.name)…", items: [item])
            self.queue.async {
                do {
                    let savedURL = try self.bridge.download(item.id, name: targetURL.lastPathComponent, directory: dir)
                    DispatchQueue.main.async {
                        self.busy = false
                        self.transferring = false
                        self.message = "Saved to \(savedURL.path)"
                        self.lastDownloadedURL = savedURL
                    }
                } catch {
                    self.fail(error)
                }
            }
        }
    }

    func cancel() { bridge.cancelRequested = true }
    func disconnect() {
        guard !busy else { return }
        queue.async { self.bridge.close() }
        deviceName = ""; storage = 0; storages = []; items = []; path = []; message = ""; error = nil; selectedItemIds.removeAll()
    }
    private func fail(_ error: Error, prefix: String = "") {
        bridge.progress = nil
        bridge.close()
        DispatchQueue.main.async {
            self.busy = false
            self.transferring = false
            self.message = ""
            self.error = prefix + error.localizedDescription
        }
    }
}

struct USBView: View {
    @ObservedObject var usb: USBModel
    let files: [URL]
    let chooseFiles: () -> Void
    var horizontalPadding: CGFloat = 14
    var bottomPadding: CGFloat = 10

    @ObservedObject private var theme = ThemeManager.shared
    @State private var isDropTargeted = false

    private var isDiscovery: Bool {
        usb.deviceName.isEmpty && usb.busy && usb.message.localizedCaseInsensitiveContains("looking")
    }

    private var selectedItems: [USBItem] {
        usb.items.filter { usb.selectedItemIds.contains($0.id) }
    }

    private var transferItems: [USBItem] {
        usb.lastTransferredItems.isEmpty ? selectedItems : usb.lastTransferredItems
    }

    private var transferSize: UInt64 {
        transferItems.reduce(UInt64(0)) { partial, item in
            let (sum, overflow) = partial.addingReportingOverflow(item.size)
            return overflow ? UInt64.max : sum
        }
    }

    var body: some View {
        Group {
            if usb.transferring {
                transferProgressView
            } else if let error = usb.error {
                transferFailureView(error: error)
            } else if usb.lastDownloadedURL != nil {
                transferCompleteView
            } else if usb.deviceName.isEmpty && usb.busy {
                discoveryView
            } else if usb.deviceName.isEmpty {
                noDeviceView
            } else {
                browserView
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if usb.deviceName.isEmpty && !usb.busy && usb.devices.isEmpty { usb.refresh() }
        }
    }

    private var discoveryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect over USB")
                .font(.system(size: 16, weight: .semibold))
            Spacer(minLength: 2)
            VStack(spacing: 9) {
                ProgressView().controlSize(.regular)
                    .frame(width: 48, height: 48)
                    .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(isDiscovery ? "Looking for a phone…" : "Connecting to your phone…")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 2)
            if isDiscovery {
                Button("Cancel search", role: .cancel, action: usb.cancelDiscovery)
                    .buttonStyle(.nearbyFullWidthSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    private var noDeviceView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect over USB")
                        .font(.system(size: 16, weight: .semibold))
                }
                Spacer(minLength: 4)
                Button(action: usb.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.nearbyCompactSecondary)
                .help("Refresh USB devices")
                .accessibilityLabel("Refresh USB devices")
                .disabled(usb.busy)
            }

            Spacer(minLength: 2)
            VStack(spacing: 6) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.presentationAccent)
                    .frame(width: 54, height: 54)
                    .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                Text(usb.devices.isEmpty ? "No Android phone detected" : "Choose your phone")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)

            if !usb.devices.isEmpty {
                VStack(spacing: 5) {
                    ForEach(usb.devices, id: \.id) { device in
                        Button { usb.connect(device.id, name: device.name) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "iphone")
                                    .foregroundStyle(theme.presentationAccent)
                                Text(device.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .nearbyControlSurface(cornerRadius: 10)
                         }
                         .buttonStyle(.plain)
                        .accessibilityLabel("Connect to \(device.name)")
                        .accessibilityHint("Browse files on this phone")
                         .disabled(usb.busy)
                    }
                }
            }

            Spacer(minLength: 2)
            HStack(spacing: 8) {
                Button("Refresh") { usb.refresh() }
                    .buttonStyle(.nearbyFullWidthSecondary)
                    .frame(maxWidth: .infinity)
                    .disabled(usb.busy)
                Button("Search") { usb.refresh() }
                    .buttonStyle(.nearbyFullWidthPrimary)
                    .frame(maxWidth: .infinity)
                    .disabled(usb.busy || !usb.devices.isEmpty)
            }
        }
    }

    private var browserView: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                 Image(systemName: "cable.connector").foregroundStyle(theme.presentationAccent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                Text(usb.deviceName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("Connected · \(usb.storages.first(where: { $0.id == usb.storage })?.name ?? "Phone storage")")
                    .font(NearbyTypography.metadata).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 3)
                Button("Disconnect", action: usb.disconnect)
                    .buttonStyle(.nearbyCompactQuiet)
                    .disabled(usb.busy)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .nearbyCardSurface(cornerRadius: 9)

            HStack(spacing: 4) {
                Button(action: usb.back) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.nearbyCompactSecondary).disabled(usb.path.isEmpty || usb.busy)
                if usb.path.isEmpty {
                    Picker("Storage", selection: $usb.storage) {
                        ForEach(usb.storages, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden().controlSize(.small).disabled(usb.busy)
                    .onChange(of: usb.storage) { _, _ in usb.load() }
                } else {
                    Button(usb.storages.first(where: { $0.id == usb.storage })?.name ?? "Phone storage", action: usb.jumpToRoot)
                        .buttonStyle(.nearbyCompactQuiet)
                    ForEach(Array(usb.path.enumerated()), id: \.offset) { index, segment in
                        Image(systemName: "chevron.right").font(.system(size: 7)).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        if index == usb.path.count - 1 {
                            Text(segment.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        } else {
                            Button(segment.name) { usb.jumpTo(index: index) }
                                .buttonStyle(.nearbyCompactQuiet)
                        }
                    }
                }
                Spacer(minLength: 0)
                if !usb.items.isEmpty {
                    Button(usb.selectedItemIds.count == usb.items.count ? "Clear" : "Select all") {
                        usb.selectedItemIds.count == usb.items.count ? usb.deselectAll() : usb.selectAll()
                    }
                    .buttonStyle(.nearbyCompactQuiet)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(usb.items) { item in
                        usbItemRow(item)
                    }
                    if usb.items.isEmpty && !usb.busy {
                        VStack(spacing: 6) {
                            Image(systemName: "folder").font(.system(size: 22)).foregroundStyle(.tertiary)
                            Text("This folder is empty").font(NearbyTypography.supporting).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(18)
                    }
                    if usb.busy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(usb.message.isEmpty ? "Loading files…" : usb.message)
                                .font(NearbyTypography.metadata).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(8)
                    }
                }
                .padding(5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .nearbyControlSurface(cornerRadius: 9)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isDropTargeted ? theme.presentationAccent : Color.primary.opacity(0.10), lineWidth: 1))
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

            HStack(spacing: 8) {
                Button {
                    usb.downloadSelected()
                } label: {
                    Label(usb.selectedItemIds.isEmpty ? "Download to Mac" : "Download \(usb.selectedItemIds.count) to Mac", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nearbyCompactFullWidthPrimary)
                .disabled(usb.busy || usb.selectedItemIds.isEmpty)

                Button {
                    if files.isEmpty { usb.chooseAndUploadFiles() } else { usb.upload(files) }
                } label: {
                    Label("Upload files to phone", systemImage: "arrow.up.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nearbyCompactFullWidthSecondary)
                .disabled(usb.busy)
            }
        }
    }

    private func usbItemRow(_ item: USBItem) -> some View {
        let icon = fileIconInfo(for: item.name, isFolder: item.folder)
        let selected = usb.selectedItemIds.contains(item.id)
        return HStack(spacing: 6) {
            Button { usb.toggleSelection(item.id) } label: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11)).foregroundStyle(selected ? theme.presentationAccent : Color.secondary.opacity(0.55))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(selected ? "Deselect \(item.name)" : "Select \(item.name)")

            Image(systemName: icon.icon).font(.system(size: 11)).foregroundStyle(icon.color).frame(width: 14)
                .accessibilityHidden(true)
            Button {
                if item.folder { usb.enter(item) } else { usb.toggleSelection(item.id) }
            } label: {
                Text(item.name).font(.system(size: 10, weight: item.folder ? .medium : .regular)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 2)
            if !item.folder {
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file))
                    .font(NearbyTypography.metadata).foregroundStyle(.secondary)
            }
            if item.folder {
                Button { usb.enter(item) } label: { Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)) }
                    .buttonStyle(.nearbyCompactQuiet)
                    .help("Open folder")
                    .accessibilityLabel("Open \(item.name)")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(selected ? theme.presentationAccent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            if item.folder {
                Button("Open Folder") { usb.enter(item) }
                Button("Download Folder to Mac") { usb.downloadFolder(item) }
                Button("Upload Files to this Folder…") { usb.chooseAndUploadFiles(to: item) }
            } else {
                Button("Download to Mac") { usb.download(item) }
                Button("Save As…") { usb.saveItemAs(item) }
            }
        }
        .disabled(usb.busy)
    }

    private var transferProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(usb.message.hasPrefix("Receiving") ? "Downloading \(transferItems.count) item\(transferItems.count == 1 ? "" : "s")" : "Sending files to phone")
                .font(.system(size: 15, weight: .semibold))
            Text(usb.deviceName).font(.system(size: 10)).foregroundStyle(.secondary)
            transferFileCard(transferItems)
            HStack {
                Text("\(Int(usb.progress * 100))%")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                Spacer()
                Text("\(TransferModel.formatBytes(Int64(Double(transferSize) * usb.progress))) of \(TransferModel.formatBytes(Int64(clamping: transferSize)))")
                    .font(NearbyTypography.metadata).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: usb.progress)
                .tint(theme.presentationAccent)
                .accessibilityLabel("USB transfer progress")
                .accessibilityValue("\(Int(usb.progress * 100)) percent")
            Spacer(minLength: 0)
            Button("Cancel transfer", role: .cancel, action: usb.cancel)
                .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
        }
    }

    private var transferCompleteView: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 1)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 31)).foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Transfer complete").font(.system(size: 15, weight: .semibold))
            Text("\(usb.message) · \(usb.deviceName)")
                .font(NearbyTypography.metadata).foregroundStyle(.secondary).multilineTextAlignment(.center)
            transferFileCard(transferItems)
            Button("Show in Finder") {
                if let url = usb.lastDownloadedURL, FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else { TransferModel.openDownloads() }
            }
            .buttonStyle(.nearbyFullWidthPrimary).frame(maxWidth: .infinity)
            Button("Back to phone") {
                usb.lastDownloadedURL = nil
                usb.lastTransferredItems = []
            }
            .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
            Spacer(minLength: 1)
        }
    }

    private func transferFailureView(error: String) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 1)
            Image(systemName: "cable.connector.slash").font(.system(size: 28)).foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Transfer failed").font(.system(size: 15, weight: .semibold))
            Text(error).font(NearbyTypography.metadata).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if !transferItems.isEmpty { transferFileCard(transferItems) }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Back to devices") {
                    usb.disconnect()
                    usb.error = nil
                    usb.lastDownloadedURL = nil
                    usb.refresh()
                }
                .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
                Button("Try again") { retryTransfer() }
                    .buttonStyle(.nearbyFullWidthPrimary).frame(maxWidth: .infinity)
                    .disabled(transferItems.isEmpty || usb.deviceName.isEmpty)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func transferFileCard(_ items: [USBItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                HStack(spacing: 7) {
                    Image(systemName: fileIconInfo(for: item.name, isFolder: item.folder).icon)
                        .font(.system(size: 11)).foregroundStyle(theme.presentationAccent).frame(width: 25, height: 27)
                        .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file))
                            .font(NearbyTypography.metadata).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, 7).padding(.vertical, 5)
                if index < min(items.count, 3) - 1 { Divider().padding(.leading, 39) }
            }
        }
        .nearbyControlSurface(cornerRadius: 9)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private func retryTransfer() {
        usb.error = nil
        let retryItems = transferItems
        guard !retryItems.isEmpty else { return }
        usb.selectedItemIds = Set(retryItems.map(\.id))
        usb.downloadSelected()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { usb.upload(urls) }
        }
        return true
    }
}
