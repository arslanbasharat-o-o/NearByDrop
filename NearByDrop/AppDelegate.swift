import Cocoa
import SwiftUI
import UserNotifications
import NearbyShare

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, MainAppDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    let model = TransferModel()
    private lazy var transferWindow = TransferWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onConsent = { [weak self] id, accept in self?.consent(id, accept: accept) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(named: "MenuBarIcon")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
        statusItem.button?.setAccessibilityLabel("NearByDrop")
        popover.contentViewController = NSHostingController(rootView: MenuView(model: model, send: { [weak self] in self?.sendFiles(nil) }, scan: { [weak self] in self?.scanCode(nil) }, open: { [weak self] in self?.openApp(nil) }))
        popover.contentSize = NSSize(width: 320, height: 254)
        popover.behavior = .transient
        let nc = UNUserNotificationCenter.current()
        nc.delegate = self
        nc.setNotificationCategories([UNNotificationCategory(identifier: "INCOMING_TRANSFERS", actions: [
            UNNotificationAction(identifier: "ACCEPT", title: "Accept", options: .authenticationRequired),
            UNNotificationAction(identifier: "DECLINE", title: "Decline")
        ], intentIdentifiers: [])])
        nc.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NearbyConnectionManager.shared.mainAppDelegate = self
        NearbyConnectionManager.shared.becomeVisible()
        let fileMenu = NSMenu(title: "File")
        for (title, action, key) in [("Open NearByDrop", #selector(openApp(_:)), "0"), ("Send Files…", #selector(sendFiles(_:)), "o"), ("Scan QR Code…", #selector(scanCode(_:)), "r"), ("Open Downloads", #selector(openDownloads(_:)), "d")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            fileMenu.addItem(item)
        }
        let item = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        item.submenu = fileMenu
        NSApp.mainMenu?.insertItem(item, at: min(1, NSApp.mainMenu?.items.count ?? 0))
    }

    @objc private func toggleMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            if let controller = popover.contentViewController {
                let size = controller.view.fittingSize
                if size.width > 0 && size.height > 0 { popover.contentSize = size }
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    @objc func openApp(_ sender: Any?) {
        popover.performClose(nil)
        transferWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        transferWindow.window?.makeKeyAndOrderFront(nil)
    }
    @objc func sendFiles(_ sender: Any?) {
        openApp(nil)
        model.tab = .send
        model.chooseFiles()
    }
    @objc func scanCode(_ sender: Any?) {
        openApp(nil)
        model.tab = .receive
        model.scanning = true
    }
    @objc func openDownloads(_ sender: Any?) { TransferModel.openDownloads() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openApp(nil); return true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func consent(_ id: String, accept: Bool) {
        guard model.incoming[id] != nil, !model.accepted.contains(id) else { return }
        if accept { model.accepted.insert(id) } else { model.incoming.removeValue(forKey: id) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + id])
        NearbyConnectionManager.shared.submitUserConsent(transferID: id, accept: accept)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            if let id = response.notification.request.content.userInfo["transferID"] as? String {
                if response.actionIdentifier == "ACCEPT" || response.actionIdentifier == "DECLINE" {
                    self.consent(id, accept: response.actionIdentifier == "ACCEPT")
                } else { self.model.tab = .receive; self.openApp(nil) }
            }
            completion()
        }
    }
    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
        DispatchQueue.main.async {
            self.model.incoming[transfer.id] = TransferInfo(device: device, transfer: transfer)
            self.model.tab = .receive
            self.model.stopQRReceive()

            // Auto-accept transfers from trusted devices
            if self.model.isDeviceTrusted(device) {
                self.consent(transfer.id, accept: true)
                return
            }

            self.openApp(nil)
            let content = UNMutableNotificationContent()
            content.title = device.name
            content.body = "Wants to send \(transfer.files.count == 1 ? transfer.files[0].name : "\(transfer.files.count) items")"
            content.subtitle = "Code: \(transfer.pinCode ?? "—")"
            content.categoryIdentifier = "INCOMING_TRANSFERS"
            content.sound = .default
            content.userInfo = ["transferID": transfer.id]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "transfer_" + transfer.id, content: content, trigger: nil))
        }
    }
    func incomingTransfer(id: String, didFinishWith error: Error?) {
        DispatchQueue.main.async {
            if error == nil, let info = self.model.incoming[id] { self.model.recordIncoming(info: info) }
            self.model.incoming.removeValue(forKey: id)
            self.model.accepted.remove(id)
            self.model.receiveMessage = error.map(TransferModel.errorMessage) ?? "Saved to \(self.model.downloadDirectory.lastPathComponent)"
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + id])
        }
    }
    func advertisementStateDidChange(_ state: NearbyConnectionManager.AdvertisementState) {
        DispatchQueue.main.async { self.model.setAdvertisementState(state) }
    }
}

struct TransferInfo { let device: RemoteDeviceInfo; let transfer: TransferMetadata }

struct MenuView: View {
    @ObservedObject var model: TransferModel
    let send: () -> Void
    let scan: () -> Void
    let open: () -> Void
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Control Center AirDrop module platter
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(model.advertisement == .failed ? Color.secondary.opacity(0.2) : Color.blue)
                        .frame(width: 38, height: 38)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.advertisement == .failed ? Color.secondary : Color.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("NearByDrop")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("Visible as \"\(model.deviceName)\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .padding(12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.06), lineWidth: 1))

            if !model.incoming.isEmpty {
                ForEach(model.incoming.keys.sorted(), id: \.self) { id in
                    if let item = model.incoming[id] {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: item.device.type == .computer ? "laptopcomputer" : "iphone")
                                    .foregroundStyle(.blue)
                                Text(item.device.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let pin = item.transfer.pinCode {
                                    Text(pin)
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            Text(item.transfer.textDescription ?? "\(item.transfer.files.count) \(item.transfer.files.count == 1 ? "item" : "items")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if model.accepted.contains(id) {
                                ProgressView("Receiving…")
                            } else {
                                Toggle("Trust this device", isOn: Binding(
                                    get: { model.isDeviceTrusted(item.device) },
                                    set: { model.setDeviceTrusted(item.device, trusted: $0) }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    Spacer()
                                    Button("Decline") { model.onConsent?(id, false) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    Button("Accept") { model.onConsent?(id, true) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.blue)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                    }
                }
            } else if model.sending {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(model.recipient, systemImage: "iphone").font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Button("Cancel", action: model.cancelSend)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    ProgressView(value: model.progress > 0 ? model.progress : nil)
                    HStack {
                        Text(model.sendMessage.isEmpty ? "Connecting…" : model.sendMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !model.transferSpeed.isEmpty || !model.timeRemaining.isEmpty {
                            HStack(spacing: 4) {
                                if !model.transferSpeed.isEmpty {
                                    Text(model.transferSpeed)
                                }
                                if !model.timeRemaining.isEmpty {
                                    Text("(\(model.timeRemaining))")
                                }
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            } else {
                if !model.urls.isEmpty {
                    HStack {
                        Image(systemName: model.urls.count > 1 ? "doc.on.doc.fill" : "doc.fill")
                            .foregroundStyle(.blue)
                        Text(model.urls.count == 1 ? (model.displayNames.first ?? model.urls[0].lastPathComponent) : "\(model.urls.count) items ready to send")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            model.setFiles([])
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 10) {
                    Button(action: send) {
                        Label(model.urls.isEmpty ? "Send Files…" : "Change Files…", systemImage: "paperplane.fill")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button(action: scan) {
                        Label("Scan QR", systemImage: "qrcode.viewfinder")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .help("Scan QR Code")
                    .accessibilityLabel("Scan QR Code")
                }
                .controlSize(.large)

                if !model.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NEARBY DEVICES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        VStack(spacing: 4) {
                            ForEach(model.devices, id: \.id) { device in
                                Button {
                                    if model.urls.isEmpty { send() }
                                    else { model.send(to: device) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: device.type == .computer ? "laptopcomputer" : "iphone")
                                            .foregroundStyle(.blue)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(device.name)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(model.urls.isEmpty ? "Click to send files" : "Send selected")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(action: open) {
                    Label("Open NearByDrop", systemImage: "macwindow")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Spacer()

                Button(action: TransferModel.openDownloads) {
                    Image(systemName: "folder")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open Downloads: \(model.downloadDirectory.lastPathComponent)")
                .accessibilityLabel("Open Downloads")

                Menu {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.toggleLaunchAtLogin(enabled: $0) }
                    ))
                    Divider()
                    Button("Change Download Location…") {
                        model.chooseDownloadDirectory()
                    }
                    Divider()
                    Button("Quit NearByDrop") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("More options")
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 320)
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            let group = DispatchGroup()
            var loadedURLs: [URL] = []
            let lock = NSLock()
            for provider in providers {
                group.enter()
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            lock.lock(); loadedURLs.append(url); lock.unlock()
                        }
                        group.leave()
                    }
                } else {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            lock.lock(); loadedURLs.append(url); lock.unlock()
                        } else if let url = item as? URL {
                            lock.lock(); loadedURLs.append(url); lock.unlock()
                        }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                if !loadedURLs.isEmpty {
                    model.setFiles(loadedURLs)
                }
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: isDragging ? 2 : 0)
        )
    }

    private var statusText: String {
        if !model.incoming.isEmpty { return "Incoming transfer" }
        if model.sending { return "Sending…" }
        switch model.advertisement {
        case .published: return "Ready to receive"
        case .failed: return "Network unavailable"
        case .starting, .idle: return "Connecting…"
        }
    }

    private var statusColor: Color {
        switch model.advertisement {
        case .published: return .green
        case .failed: return .red
        case .starting, .idle: return .orange
        }
    }
}
