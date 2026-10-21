import SwiftUI
import NearbyShare

struct USBItem: Identifiable {
    let id: UInt32
    let name: String
    let size: UInt64
    let folder: Bool
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
                DispatchQueue.main.async { self.busy = false; self.transferring = false; self.message = "Sent \(sent) file\(sent == 1 ? "" : "s")"; self.load() }
            } catch { self.fail(error, prefix: sent > 0 ? "\(sent) files sent. " : "") }
        }
    }
    func download(_ item: USBItem) {
        guard !busy, !item.folder else { return }
        let downloads = NearbyConnectionManager.downloadDirectory
        prepareTransfer("Receiving \(item.name)…")
        queue.async {
            do {
                _ = try self.bridge.download(item.id, name: item.name, directory: downloads)
                DispatchQueue.main.async { self.busy = false; self.transferring = false; self.message = "Saved \(item.name) to \(downloads.lastPathComponent)" }
            } catch { self.fail(error) }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(usb.deviceName.isEmpty ? "Connected Devices" : usb.deviceName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if !usb.deviceName.isEmpty {
                    Button("Disconnect", action: usb.disconnect)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(usb.busy)
                }
                Button(action: usb.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
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
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                            Text("Click to explore phone storage & send files")
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
                HStack {
                    Button(action: usb.back) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(usb.path.isEmpty || usb.busy)
                    .accessibilityLabel("Parent folder")

                    if usb.path.isEmpty {
                        Picker("Storage", selection: $usb.storage) {
                            ForEach(usb.storages, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .disabled(usb.busy)
                        .onChange(of: usb.storage) { _, _ in usb.load() }
                    } else {
                        Text(usb.path.map(\.name).joined(separator: " / "))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(usb.items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.folder ? "folder.fill" : "doc")
                                    .foregroundStyle(item.folder ? Color.blue : Color.secondary)
                                    .frame(width: 20)
                                Text(item.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if item.folder {
                                    Button("Open") { usb.enter(item) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                } else {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Button("Save") { usb.download(item) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                        .help("Save to Downloads")
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                            .disabled(usb.busy)
                        }
                        if usb.items.isEmpty && !usb.busy {
                            Text("This folder is empty")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(20)
                        }
                    }
                }
                HStack {
                    Button(files.isEmpty ? "Choose Files…" : "Change Files…", action: chooseFiles)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(usb.busy)
                    Spacer()
                    Button("Send \(files.count == 1 ? "File" : "\(files.count) Files") Here") {
                        usb.upload(files)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(files.isEmpty || usb.busy)
                }
            }
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
                Text(usb.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
