import SwiftUI
import NearbyShare

struct USBItem: Identifiable {
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

    private let bridge = NDUSBTransfer()
    private let queue = DispatchQueue(label: "NearByDrop.USB", qos: .userInitiated)
    var parent: UInt32 { path.last?.id ?? UInt32.max }

    func refresh() {
        guard !busy else { return }
        busy = true; error = nil; message = "Looking for USB devices…"
        queue.async {
            self.bridge.close()
            do {
                let values = try self.bridge.devices()
                let devices = values.compactMap { value -> (id: String, name: String)? in
                    guard let id = value["id"] as? String, let name = value["name"] as? String else { return nil }; return (id, name)
                }
                DispatchQueue.main.async { self.devices = devices; self.deviceName = ""; self.items = []; self.storages = []; self.path = []; self.busy = false; self.message = "" }
            } catch { self.fail(error) }
        }
    }

    func connect(_ id: String, name: String) {
        guard !busy else { return }
        busy = true; error = nil; message = "Opening \(name)…"
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

    func enter(_ item: USBItem) { guard !busy else { return }; path.append((item.id, item.name)); load() }
    func back() { guard !busy else { return }; if !path.isEmpty { path.removeLast() }; load() }

    func jumpToRoot() {
        guard !busy, !path.isEmpty else { return }
        path.removeAll()
        load()
    }

    func jumpTo(index: Int) {
        guard !busy, index >= 0, index < path.count - 1 else { return }
        path = Array(path.prefix(index + 1))
        load()
    }

    func openQuickFolder(named targetName: String) {
        guard !busy, storage != 0 else { return }
        path.removeAll()
        busy = true
        let storage = storage, parent = self.parent
        queue.async {
            do {
                let values = try self.bridge.files(inStorage: storage, parent: parent)
                let items = values.compactMap { value -> USBItem? in
                    guard let id = value["id"] as? NSNumber, let name = value["name"] as? String else { return nil }
                    return USBItem(id: id.uint32Value, name: name, size: (value["size"] as? NSNumber)?.uint64Value ?? 0, folder: (value["folder"] as? NSNumber)?.boolValue ?? false)
                }.sorted { $0.folder != $1.folder ? $0.folder : $0.name.localizedStandardCompare($1.name) == .orderedAscending }

                DispatchQueue.main.async {
                    self.items = items
                    self.busy = false
                    if let folder = items.first(where: { $0.folder && $0.name.localizedCaseInsensitiveContains(targetName) }) {
                        self.enter(folder)
                    }
                }
            } catch {
                self.fail(error)
            }
        }
    }

    private func prepareTransfer(_ message: String) {
        busy = true; transferring = true; error = nil; progress = 0; self.message = message
        bridge.cancelRequested = false
        bridge.progress = { [weak self] progress in DispatchQueue.main.async { self?.progress = progress } }
    }

    func upload(_ urls: [URL]) {
        guard !busy, storage != 0, !urls.isEmpty else { return }
        let storage = storage, parent = parent
        prepareTransfer("Sending \(urls.count) file\(urls.count == 1 ? "" : "s")…")
        queue.async {
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

    func chooseAndUploadFiles() {
        guard !busy, storage != 0 else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Upload"
        panel.message = "Choose files to send to your phone"
        panel.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.begin { [weak self] response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            self?.upload(panel.urls)
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

    func saveItemAs(_ item: USBItem) {
        guard !busy, !item.folder else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.name
        panel.prompt = "Save"
        panel.message = "Choose where to save this file on your Mac"
        panel.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.begin { [weak self] response in
            guard response == .OK, let targetURL = panel.url, let self = self else { return }
            let dir = targetURL.deletingLastPathComponent()
            self.prepareTransfer("Receiving \(item.name)…")
            self.queue.async {
                do {
                    _ = try self.bridge.download(item.id, name: targetURL.lastPathComponent, directory: dir)
                    DispatchQueue.main.async {
                        self.busy = false
                        self.transferring = false
                        self.message = "Saved \(item.name)"
                        self.lastDownloadedURL = targetURL
                    }
                } catch {
                    self.fail(error)
                }
            }
        }
    }

    func downloadAll(_ itemsToDownload: [USBItem]) {
        let files = itemsToDownload.filter { !$0.folder }
        guard !busy, !files.isEmpty else { return }
        let downloads = NearbyConnectionManager.downloadDirectory
        prepareTransfer("Receiving \(files.count) file\(files.count == 1 ? "" : "s")…")
        queue.async {
            var sent = 0
            do {
                for item in files {
                    if self.bridge.cancelRequested { throw NSError(domain: "USB", code: 1, userInfo: [NSLocalizedDescriptionKey: "Canceled"]) }
                    _ = try self.bridge.download(item.id, name: item.name, directory: downloads)
                    sent += 1
                }
                DispatchQueue.main.async {
                    self.busy = false
                    self.transferring = false
                    self.message = "Saved \(sent) file\(sent == 1 ? "" : "s") to \(downloads.lastPathComponent)"
                }
            } catch {
                self.fail(error, prefix: sent > 0 ? "\(sent) files saved. " : "")
            }
        }
    }

    func cancel() { bridge.cancelRequested = true }
    func disconnect() {
        guard !busy else { return }
        queue.async { self.bridge.close() }
        deviceName = ""; storages = []; items = []; path = []; message = ""
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.currentAccent.color)

                Text(usb.deviceName.isEmpty ? "Connected Devices" : usb.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if !usb.deviceName.isEmpty {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                if !usb.deviceName.isEmpty {
                    Button(action: usb.disconnect) {
                        Label("Disconnect", systemImage: "eject")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(usb.busy)
                }

                Button(action: usb.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
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
                                            Text("Connected via USB")
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
                                .buttonStyle(.plain)
                                .disabled(usb.busy)
                            }
                        }
                    }
                    Spacer(minLength: 6)
                }
            } else {
                // Breadcrumb & Navigation Bar
                HStack(spacing: 6) {
                    Button(action: usb.back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(usb.path.isEmpty || usb.busy)
                    .help("Parent folder")

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
                                            .font(.system(size: 10))
                                        Text(usb.storages.first(where: { $0.id == usb.storage })?.name ?? "Storage")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)

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
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Spacer()

                    let downloadableFiles = usb.items.filter { !$0.folder }
                    if !downloadableFiles.isEmpty {
                        Button {
                            usb.downloadAll(downloadableFiles)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                Text("Download All (\(downloadableFiles.count))")
                            }
                            .font(.caption2.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(usb.busy)
                        .help("Download all files in this folder to Mac")
                    }
                }

                // File & Folder Explorer (Native macOS rows)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(usb.items) { item in
                            HStack(spacing: 8) {
                                let iconInfo = fileIconInfo(for: item.name, isFolder: item.folder)
                                Image(systemName: iconInfo.icon)
                                    .foregroundStyle(iconInfo.color)
                                    .font(.system(size: 15))
                                    .frame(width: 20)

                                Text(item.name)
                                    .font(.system(size: 12, weight: item.folder ? .medium : .regular))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                if item.folder {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    Button {
                                        usb.download(item)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "arrow.down.circle.fill")
                                            Text("Save")
                                        }
                                        .font(.caption2.weight(.medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("Save to Downloads on Mac")
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(hoveredItemId == item.id ? Color.primary.opacity(0.06) : Color.primary.opacity(0.02))
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
                            }
                            .contextMenu {
                                if item.folder {
                                    Button("Open Folder") { usb.enter(item) }
                                    Button("Upload Files to this Folder…") { usb.chooseAndUploadFiles() }
                                } else {
                                    Button("Download to Downloads") { usb.download(item) }
                                    Button("Save As…") { usb.saveItemAs(item) }
                                    if let url = usb.lastDownloadedURL, url.lastPathComponent == item.name {
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
                HStack(spacing: 6) {
                    // Quick Folder Jump Shortcuts
                    HStack(spacing: 4) {
                        Button {
                            usb.openQuickFolder(named: "DCIM")
                        } label: {
                            Label("Photos", systemImage: "photo.on.rectangle")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Jump to Camera / Photos")

                        Button {
                            usb.openQuickFolder(named: "Download")
                        } label: {
                            Label("Downloads", systemImage: "arrow.down")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Jump to Downloads")

                        Button {
                            usb.openQuickFolder(named: "Documents")
                        } label: {
                            Label("Docs", systemImage: "doc")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Jump to Documents")
                    }

                    Spacer()

                    // Send / Upload Actions
                    if !files.isEmpty {
                        Button("Send \(files.count == 1 ? "1 File" : "\(files.count) Files") Here") {
                            usb.upload(files)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.currentAccent.color)
                        .controlSize(.small)
                        .disabled(usb.busy)
                    } else {
                        Button {
                            usb.chooseAndUploadFiles()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("Send Files…")
                            }
                            .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.currentAccent.color)
                        .controlSize(.small)
                        .disabled(usb.busy)
                        .help("Choose files on your Mac to upload to phone")
                    }
                }
            }

            // Transfer Status & Progress
            if usb.transferring {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: usb.progress)
                    HStack {
                        Text(usb.message)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Cancel", action: usb.cancel)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
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
                HStack {
                    Text(usb.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let url = usb.lastDownloadedURL {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
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
