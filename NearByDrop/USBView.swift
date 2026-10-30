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
    @Published var selectedItemIds: Set<UInt32> = []
    @Published var isChoosingFiles = false

    private let bridge = NDUSBTransfer()
    private let queue = DispatchQueue(label: "NearByDrop.USB", qos: .userInitiated)
    private var scopedUploadURLs: [URL] = []
    private var visitedFolders: Set<UInt32> = []
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
        guard !busy else { return }
        if !deviceName.isEmpty { load(); return }
        busy = true; error = nil; message = "Looking for USB devices…"
        selectedItemIds.removeAll()
        lastDownloadedURL = nil
        queue.async {
            self.bridge.close()
            do {
                let values = try self.bridge.devices()
                let devices = values.compactMap { value -> (id: String, name: String)? in
                    guard let id = value["id"] as? String, let name = value["name"] as? String else { return nil }; return (id, name)
                }
                DispatchQueue.main.async { self.devices = devices; self.deviceName = ""; self.items = []; self.storages = []; self.storage = 0; self.path = []; self.busy = false; self.message = "" }
            } catch { self.fail(error) }
        }
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

    private func prepareTransfer(_ message: String) {
        busy = true; transferring = true; error = nil; progress = 0; self.message = message
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
        scopedUploadURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
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
                for url in urls {
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
        prepareTransfer("Receiving \(item.name)…")
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
        prepareTransfer("Receiving folder \(item.name)…")
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
        prepareTransfer("Receiving \(currentName)…")
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
        prepareTransfer("Receiving \(selected.count) item\(selected.count == 1 ? "" : "s")…")
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
            self.prepareTransfer("Receiving \(item.name)…")
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
    private func fail(_ error: Error, prefix: String = "") { DispatchQueue.main.async { self.busy = false; self.transferring = false; self.message = ""; self.error = prefix + error.localizedDescription } }
}

struct USBView: View {
    @ObservedObject var usb: USBModel
    let files: [URL]
    let chooseFiles: () -> Void
    var horizontalPadding: CGFloat = 14
    var bottomPadding: CGFloat = 10

    @ObservedObject private var theme = ThemeManager.shared
    @State private var hoveredItemId: UInt32? = nil
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.currentAccent.color)

                Text(usb.deviceName.isEmpty ? "USB Connection" : usb.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if !usb.deviceName.isEmpty {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                }

                Spacer()

                if !usb.deviceName.isEmpty {
                    Button(action: usb.disconnect) {
                        Label("Disconnect", systemImage: "eject")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(usb.busy)
                }

                Button(action: usb.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh USB devices")
                .accessibilityLabel("Refresh USB devices")
                .disabled(usb.busy)
            }

            if usb.deviceName.isEmpty {
                if usb.devices.isEmpty {
                    Spacer(minLength: 12)
                    VStack(spacing: 10) {
                        Image(systemName: "cable.connector")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("No USB Device Detected")
                            .font(.headline)
                        Text("Connect your Android phone via USB, unlock it, and select File Transfer.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(usb.devices, id: \.id) { device in
                                Button {
                                    usb.connect(device.id, name: device.name)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "iphone")
                                            .font(.system(size: 16))
                                            .foregroundStyle(theme.currentAccent.color)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text("Select to browse files")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.borderless)
                                .disabled(usb.busy)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                }
            } else {
                // Breadcrumb & Selection Toolbar
                HStack(spacing: 6) {
                    Button(action: usb.back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(usb.path.isEmpty || usb.busy)
                    .help("Back to parent folder")
                    .accessibilityLabel("Back to parent folder")

                    if usb.path.isEmpty {
                        Picker("Storage", selection: $usb.storage) {
                            ForEach(usb.storages, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .disabled(usb.busy)
                        .onChange(of: usb.storage) { _, _ in usb.load() }
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                Button(action: usb.jumpToRoot) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "internaldrive")
                                            .font(.system(size: 11))
                                        Text(usb.storages.first(where: { $0.id == usb.storage })?.name ?? "Storage")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)

                                ForEach(Array(usb.path.enumerated()), id: \.offset) { index, segment in
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                    Button {
                                        usb.jumpTo(index: index)
                                    } label: {
                                        Text(segment.name)
                                            .font(.caption.weight(index == usb.path.count - 1 ? .semibold : .regular))
                                            .foregroundStyle(index == usb.path.count - 1 ? .primary : .secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Spacer()

                    if !usb.items.isEmpty {
                        Button {
                            if usb.selectedItemIds.count == usb.items.count {
                                usb.deselectAll()
                            } else {
                                usb.selectAll()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: usb.selectedItemIds.count == usb.items.count && !usb.items.isEmpty ? "checkmark.circle.fill" : "checkmark.circle")
                                Text(usb.selectedItemIds.isEmpty ? "Select All" : "\(usb.selectedItemIds.count)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(usb.busy)
                        .help(usb.selectedItemIds.count == usb.items.count ? "Deselect all items" : "Select all items in this folder")
                    }
                }

                // File & Folder Explorer (Native macOS rows)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(usb.items) { item in
                            HStack(spacing: 8) {
                                // Multi-select checkbox
                                Button {
                                    usb.toggleSelection(item.id)
                                } label: {
                                    Image(systemName: usb.selectedItemIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(usb.selectedItemIds.contains(item.id) ? theme.currentAccent.color : Color.secondary.opacity(0.4))
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.borderless)
                                .help(usb.selectedItemIds.contains(item.id) ? "Deselect item" : "Select item")
                                .accessibilityLabel(usb.selectedItemIds.contains(item.id) ? "Deselect \(item.name)" : "Select \(item.name)")
                                .accessibilityValue(usb.selectedItemIds.contains(item.id) ? "Selected" : "Not selected")

                                // Icon
                                let iconInfo = fileIconInfo(for: item.name, isFolder: item.folder)
                                Image(systemName: iconInfo.icon)
                                    .foregroundStyle(iconInfo.color)
                                    .font(.system(size: 15))
                                    .frame(width: 20)

                                // Item Name
                                Text(item.name)
                                    .font(.system(size: 12, weight: item.folder ? .medium : .regular))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if item.folder {
                                    // Folder Download Button
                                    Button {
                                        usb.downloadFolder(item)
                                    } label: {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 12))
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Download this folder to Mac")
                                    .accessibilityLabel("Download folder \(item.name) to Mac")

                                    // Chevron to enter folder
                                    Button {
                                        usb.enter(item)
                                    } label: {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open folder")
                                    .accessibilityLabel("Open folder \(item.name)")
                                } else {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Button {
                                        usb.download(item)
                                    } label: {
                                        Image(systemName: "arrow.down.circle")
                                            .font(.system(size: 12))
                                            .frame(width: 28, height: 28)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Download to Mac")
                                    .accessibilityLabel("Download \(item.name) to Mac")
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(usb.selectedItemIds.contains(item.id) ? theme.currentAccent.color.opacity(0.1) : (hoveredItemId == item.id ? Color.primary.opacity(0.05) : Color.clear))
                            )
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                if isHovered { hoveredItemId = item.id }
                                else if hoveredItemId == item.id { hoveredItemId = nil }
                            }
                            .onTapGesture(count: 2) {
                                if item.folder { usb.enter(item) }
                                else { usb.download(item) }
                            }
                            .onTapGesture(count: 1) {
                                if item.folder { usb.enter(item) }
                                else { usb.toggleSelection(item.id) }
                            }
                            .contextMenu {
                                if item.folder {
                                    Button("Open Folder") { usb.enter(item) }
                                    Button("Download Folder to Mac") { usb.downloadFolder(item) }
                                     Button("Upload Files to this Folder…") { usb.chooseAndUploadFiles(to: item) }
                                } else {
                                    Button("Download to Nearby Drop") { usb.download(item) }
                                    Button("Save As…") { usb.saveItemAs(item) }
                                    if let url = usb.lastDownloadedURL,
                                       url.lastPathComponent == item.name,
                                       FileManager.default.fileExists(atPath: url.path) {
                                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    }
                                }
                            }
                            .disabled(usb.busy)
                        }

                        if usb.items.isEmpty && !usb.busy {
                            VStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.tertiary)
                                Text("This folder is empty")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDropTargeted ? theme.currentAccent.color : Color.clear, lineWidth: 1.5)
                )
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    let group = DispatchGroup()
                    var loadedURLs: [URL] = []
                    let lock = NSLock()
                    for provider in providers {
                        group.enter()
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url = url {
                                lock.lock()
                                loadedURLs.append(url)
                                lock.unlock()
                            }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        if !loadedURLs.isEmpty {
                            usb.upload(loadedURLs)
                        }
                    }
                    return true
                }

                // Two-Way Action Bar (Bottom)
                HStack(spacing: 8) {
                    if !usb.selectedItemIds.isEmpty {
                        Button {
                            usb.downloadSelected()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download \(usb.selectedItemIds.count) Items")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.currentAccent.color)
                        .controlSize(.regular)
                        .disabled(usb.busy)

                        Button("Clear") {
                            usb.deselectAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(usb.busy)

                        Spacer()
                    } else {
                        if !usb.path.isEmpty && !usb.items.isEmpty {
                            Button {
                                usb.downloadCurrentFolder()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.badge.gearshape")
                                    Text("Download Folder")
                                }
                                .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(usb.busy)
                            .help("Download all files and subfolders in this folder")
                        }

                        Spacer()

                        if !files.isEmpty {
                            Button("Send \(files.count == 1 ? "1 File" : "\(files.count) Files")") {
                                usb.upload(files)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.currentAccent.color)
                            .controlSize(.regular)
                            .disabled(usb.busy)
                        } else {
                            Button {
                                usb.chooseAndUploadFiles()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Send Files…")
                                }
                                .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.currentAccent.color)
                            .controlSize(.regular)
                            .disabled(usb.busy)
                            .help("Choose files on your Mac to upload to phone")
                        }
                    }
                }
            }

            // Transfer Status & Progress Card
            if usb.transferring {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: usb.progress)
                    HStack {
                        Text(usb.message)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Cancel", role: .cancel, action: usb.cancel)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } else if usb.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(usb.message.isEmpty ? "Working…" : usb.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !usb.message.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 13))
                    Text(usb.message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let url = usb.lastDownloadedURL, FileManager.default.fileExists(atPath: url.path) {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }

            if let error = usb.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .onAppear { if usb.deviceName.isEmpty { usb.refresh() } }
    }
}
