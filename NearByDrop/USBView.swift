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
    var horizontalPadding: CGFloat = 28
    var bottomPadding: CGFloat = 20
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(usb.deviceName.isEmpty ? "Android USB" : usb.deviceName).font(.headline).lineLimit(1)
                Spacer()
                if !usb.deviceName.isEmpty { Button("Disconnect", action: usb.disconnect).disabled(usb.busy) }
                Button(action: usb.refresh) { Image(systemName: "arrow.clockwise") }.help("Refresh USB devices").accessibilityLabel("Refresh USB devices").disabled(usb.busy)
            }
            if usb.deviceName.isEmpty {
                if usb.devices.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "cable.connector").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("Connect your Android phone").font(.headline)
                        Text("Unlock your phone and select File Transfer for USB.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }.frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(usb.devices, id: \.id) { device in
                        Button { usb.connect(device.id, name: device.name) } label: { HStack { Label(device.name, systemImage: "iphone"); Spacer(); Image(systemName: "chevron.right") }.padding(12) }.buttonStyle(.bordered).disabled(usb.busy)
                    }
                    Spacer()
                }
            } else {
                HStack {
                    Button(action: usb.back) { Image(systemName: "chevron.left") }.disabled(usb.path.isEmpty || usb.busy).accessibilityLabel("Parent folder")
                    if usb.path.isEmpty {
                        Picker("Storage", selection: $usb.storage) { ForEach(usb.storages, id: \.id) { Text($0.name).tag($0.id) } }.labelsHidden().disabled(usb.busy).onChange(of: usb.storage) { _, _ in usb.load() }
                    } else { Text(usb.path.map(\.name).joined(separator: " / ")).lineLimit(1).truncationMode(.head) }
                    Spacer()
                }
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(usb.items) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.folder ? "folder.fill" : "doc").foregroundStyle(item.folder ? Color.blue : Color.secondary).frame(width: 22)
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if item.folder { Button("Open") { usb.enter(item) } }
                                else { Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: item.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary); Button("Save") { usb.download(item) }.help("Save to Downloads") }
                            }.padding(.vertical, 7).disabled(usb.busy)
                        }
                        if usb.items.isEmpty && !usb.busy { Text("This folder is empty").foregroundStyle(.secondary).padding(24) }
                    }
                }
                HStack {
                    Button(files.isEmpty ? "Choose Files…" : "Change Files…", action: chooseFiles).disabled(usb.busy)
                    Spacer()
                    Button("Send \(files.count == 1 ? "File" : "\(files.count) Files") Here") { usb.upload(files) }.modifier(PrimaryAction()).disabled(files.isEmpty || usb.busy)
                }
            }
            if usb.transferring {
                ProgressView(value: usb.progress)
                HStack { Text(usb.message).font(.callout).lineLimit(2); Spacer(); Button("Cancel", action: usb.cancel) }
            } else if usb.busy { ProgressView().controlSize(.small) }
            else if !usb.message.isEmpty { Text(usb.message).font(.callout).foregroundStyle(.secondary) }
            if let error = usb.error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.padding(.horizontal, horizontalPadding).padding(.bottom, bottomPadding).onAppear { if usb.deviceName.isEmpty { usb.refresh() } }
    }
}
