import Cocoa
import SwiftUI
import UserNotifications
import NearbyShare

@main
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSPopoverDelegate, MainAppDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    let model = TransferModel()
    private lazy var transferWindow = TransferWindowController(model: model)
    private lazy var settingsWindow = SettingsWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onConsent = { [weak self] id, accept in self?.consent(id, accept: accept) }
        ThemeManager.shared.applyDockPolicy()
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = ThemeManager.shared.menuBarImage()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
        statusItem.button?.setAccessibilityLabel("NearByDrop")
        ThemeManager.shared.onMenuBarIconChanged = { [weak self] in
            self?.statusItem.button?.image = ThemeManager.shared.menuBarImage()
        }

        popover.contentViewController = NSHostingController(rootView: MenuView(
            model: model,
            send: { [weak self] in self?.sendFiles(nil) },
            scan: { [weak self] in self?.scanCode(nil) },
            open: { [weak self] in self?.openApp(nil) },
            settings: { [weak self] in self?.openSettings(nil) },
            guide: { [weak self] in self?.openGuide(nil) },
            privacy: { [weak self] in self?.openPrivacy(nil) }
        ))
        popover.contentSize = NSSize(width: 360, height: 505)
        popover.behavior = .transient
        popover.delegate = self

        let nc = UNUserNotificationCenter.current()
        nc.delegate = self
        nc.setNotificationCategories([
            UNNotificationCategory(identifier: "INCOMING_TRANSFERS", actions: [
                UNNotificationAction(identifier: "ACCEPT", title: "Accept", options: .authenticationRequired),
                UNNotificationAction(identifier: "DECLINE", title: "Decline")
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: "TRANSFER_COMPLETED", actions: [
                UNNotificationAction(identifier: "OPEN", title: "Open", options: .foreground),
                UNNotificationAction(identifier: "FINDER", title: "Show in Finder")
            ], intentIdentifiers: [])
        ])
        nc.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        NearbyConnectionManager.shared.mainAppDelegate = self
        NearbyConnectionManager.shared.becomeVisible()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            OnboardingWindowController.showOnboarding(onFinished: { [weak self] in
                if !(self?.model.menuBarOnly ?? false) {
                    self?.openApp(nil)
                } else {
                    self?.showPopover()
                }
            })
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "NearByDrop")
        let aboutItem = NSMenuItem(title: "About NearByDrop", action: #selector(openAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide NearByDrop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit NearByDrop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        for (title, action, key) in [
            ("Open NearByDrop", #selector(openApp(_:)), "0"),
            ("Settings…", #selector(openSettings(_:)), ","),
            ("Send Files…", #selector(sendFiles(_:)), "o"),
            ("Scan QR Code…", #selector(scanCode(_:)), "r"),
            ("Open Downloads", #selector(openDownloads(_:)), "d")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            fileMenu.addItem(item)
        }
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let sendTab = NSMenuItem(title: "Send", action: #selector(showSendTab(_:)), keyEquivalent: "1")
        sendTab.target = self
        viewMenu.addItem(sendTab)
        let receiveTab = NSMenuItem(title: "Receive", action: #selector(showReceiveTab(_:)), keyEquivalent: "2")
        receiveTab.target = self
        viewMenu.addItem(receiveTab)
        let historyTab = NSMenuItem(title: "Transfers", action: #selector(showHistoryTab(_:)), keyEquivalent: "3")
        historyTab.target = self
        viewMenu.addItem(historyTab)
        let usbTab = NSMenuItem(title: "USB Transfer", action: #selector(showUSBTab(_:)), keyEquivalent: "4")
        usbTab.target = self
        viewMenu.addItem(usbTab)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let guideItem = NSMenuItem(title: "NearByDrop Quick Start Guide", action: #selector(openGuide(_:)), keyEquivalent: "?")
        guideItem.target = self
        helpMenu.addItem(guideItem)
        let privacyItem = NSMenuItem(title: "Privacy & Security Policy", action: #selector(openPrivacy(_:)), keyEquivalent: "")
        privacyItem.target = self
        helpMenu.addItem(privacyItem)
        helpMenu.addItem(NSMenuItem.separator())
        let githubItem = NSMenuItem(title: "NearByDrop on GitHub…", action: #selector(openGitHub(_:)), keyEquivalent: "")
        githubItem.target = self
        helpMenu.addItem(githubItem)
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    // MARK: - NSPopoverDelegate
    func popoverWillShow(_ notification: Notification) {
        if let window = popover.contentViewController?.view.window {
            window.level = .popUpMenu
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
    }

    func popoverDidShow(_ notification: Notification) {
        if let window = popover.contentViewController?.view.window {
            window.level = .popUpMenu
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return true
    }

    @objc private func toggleMenu() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentSize = NSSize(width: 360, height: 505)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.level = .popUpMenu
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentSize = NSSize(width: 360, height: 505)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.level = .popUpMenu
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
    @objc func openApp(_ sender: Any?) {
        popover.performClose(nil)
        transferWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        transferWindow.window?.makeKeyAndOrderFront(nil)
    }
    @objc func openSettings(_ sender: Any?) {
        popover.performClose(nil)
        settingsWindow.show(tab: .general)
    }
    @objc func openAppearance(_ sender: Any?) {
        popover.performClose(nil)
        settingsWindow.show(tab: .appearance)
    }
    @objc func openTrustedDevices(_ sender: Any?) {
        popover.performClose(nil)
        settingsWindow.show(tab: .devices)
    }
    @objc func openGuide(_ sender: Any?) {
        popover.performClose(nil)
        OnboardingWindowController.showOnboarding()
    }
    @objc func openPrivacy(_ sender: Any?) {
        popover.performClose(nil)
        if let url = URL(string: "https://github.com/arslanbasharat/NearByDrop#privacy--security") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func openAbout(_ sender: Any?) {
        popover.performClose(nil)
        settingsWindow.show(tab: .about)
    }
    @objc func openGitHub(_ sender: Any?) {
        if let url = URL(string: "https://github.com/arslanbasharat/NearByDrop") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func showSendTab(_ sender: Any?) {
        model.tab = .send
        if model.menuBarOnly { showPopover() } else { openApp(nil) }
    }
    @objc func showReceiveTab(_ sender: Any?) {
        model.tab = .receive
        if model.menuBarOnly { showPopover() } else { openApp(nil) }
    }
    @objc func showHistoryTab(_ sender: Any?) {
        model.tab = .history
        if model.menuBarOnly { showPopover() } else { openApp(nil) }
    }
    @objc func showUSBTab(_ sender: Any?) {
        model.tab = .usb
        if model.menuBarOnly { showPopover() } else { openApp(nil) }
    }
    @objc func sendFiles(_ sender: Any?) {
        model.tab = .send
        model.chooseFiles()
    }
    @objc func scanCode(_ sender: Any?) {
        model.tab = .receive
        QRScannerWindowController.shared.show { [weak self] code in
            self?.model.scan(code)
        }
    }
    @objc func openDownloads(_ sender: Any?) { TransferModel.openDownloads() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.menuBarOnly {
            toggleMenu()
            return true
        }
        openApp(nil)
        return true
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func consent(_ id: String, accept: Bool) {
        guard model.incoming[id] != nil, !model.accepted.contains(id) else { return }
        if accept {
            model.accepted.insert(id)
            FeedbackManager.shared.vibrateClick()
        } else {
            model.incoming.removeValue(forKey: id)
            FeedbackManager.shared.vibrateTap()
        }
        TransferNotificationManager.shared.transferDidConsent(id: id, accept: accept)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["transfer_" + id])
        NearbyConnectionManager.shared.submitUserConsent(transferID: id, accept: accept)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            let userInfo = response.notification.request.content.userInfo
            if let id = userInfo["transferID"] as? String {
                if response.actionIdentifier == "ACCEPT" || response.actionIdentifier == "DECLINE" {
                    self.consent(id, accept: response.actionIdentifier == "ACCEPT")
                } else {
                    self.model.tab = .receive
                    if self.model.menuBarOnly { self.showPopover() } else { self.openApp(nil) }
                }
            } else if let filePath = userInfo["filePath"] as? String {
                let fileURL = URL(fileURLWithPath: filePath)
                if response.actionIdentifier == "FINDER" {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } else {
                        TransferModel.openDownloads()
                    }
                } else {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        NSWorkspace.shared.open(fileURL)
                    } else {
                        TransferModel.openDownloads()
                    }
                }
            }
            completion()
        }
    }

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
        DispatchQueue.main.async {
            self.model.incoming[transfer.id] = TransferInfo(device: device, transfer: transfer)
            self.model.tab = .receive
            self.model.stopQRReceive()

            // When receiving via QR code scanner, the user actively initiated by scanning the sender's code
            if self.model.qrStatus != .idle {
                let desc: String
                if let text = transfer.textDescription {
                    desc = text
                } else if let first = transfer.files.first {
                    desc = transfer.files.count > 1 ? "\(first.name) (+\(transfer.files.count - 1))" : first.name
                } else {
                    desc = "Files"
                }
                self.model.qrStatus = .downloading(sender: device.name, description: desc)
                self.consent(transfer.id, accept: true)
                FeedbackManager.shared.playIncoming()
                FeedbackManager.shared.vibrateTap()
                return
            }

            // Auto-accept transfers from trusted devices
            if self.model.isDeviceTrusted(device) {
                self.consent(transfer.id, accept: true)
                TransferNotificationManager.shared.showAutoAccepted(transfer: transfer, device: device)
                return
            }

            FeedbackManager.shared.playIncoming()
            FeedbackManager.shared.vibrateTap()

            // Automatically open UI so incoming transfer is immediately visible
            if self.model.menuBarOnly {
                self.showPopover()
            } else {
                self.openApp(nil)
            }

            TransferNotificationManager.shared.showIncoming(
                transfer: transfer,
                device: device,
                isTrusted: self.model.isDeviceTrusted(device),
                onConsent: { [weak self] accept in
                    self?.consent(transfer.id, accept: accept)
                },
                onTrust: { [weak self] trusted in
                    self?.model.setDeviceTrusted(device, trusted: trusted)
                }
            )

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
            let info = self.model.incoming[id]
            let fileURL = info?.transfer.files.first.map { self.model.downloadDirectory.appendingPathComponent($0.name) }
            let fileName: String
            if let text = info?.transfer.textDescription {
                fileName = text
            } else if let first = info?.transfer.files.first {
                fileName = (info?.transfer.files.count ?? 1) > 1 ? "\(first.name) (+\((info?.transfer.files.count ?? 1) - 1))" : first.name
            } else {
                fileName = "File"
            }

            if error == nil, let info = info {
                self.model.recordIncoming(info: info)
                FeedbackManager.shared.playSuccess()
                FeedbackManager.shared.vibrateSuccess()
                TransferNotificationManager.shared.transferDidFinish(id: id, error: nil, fileURL: fileURL, fileName: fileName)

                let completeContent = UNMutableNotificationContent()
                completeContent.title = "Transfer Complete"
                completeContent.body = "Received \(fileName) from \(info.device.name)"
                completeContent.categoryIdentifier = "TRANSFER_COMPLETED"
                completeContent.sound = .default
                if let fileURL = fileURL {
                    completeContent.userInfo = ["filePath": fileURL.path]
                }
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "complete_" + id, content: completeContent, trigger: nil))

                if self.model.qrStatus != .idle {
                    self.model.qrStatus = .completed(filename: fileName, count: info.transfer.files.count)
                }
            } else if error != nil {
                FeedbackManager.shared.playError()
                FeedbackManager.shared.vibrateTap()
                TransferNotificationManager.shared.transferDidFinish(id: id, error: error, fileURL: nil, fileName: fileName)
                if self.model.qrStatus != .idle {
                    self.model.qrStatus = .failed(error: error.map(TransferModel.errorMessage) ?? "Transfer failed")
                }
            }
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
    var settings: (() -> Void)? = nil
    var guide: (() -> Void)? = nil
    var privacy: (() -> Void)? = nil
    @ObservedObject private var theme = ThemeManager.shared
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Platter
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(model.advertisement == .failed ? Color.secondary.opacity(0.2) : theme.currentAccent.color)
                        .frame(width: 32, height: 32)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(model.advertisement == .failed ? Color.secondary : Color.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("NearByDrop")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                    }
                    Text(statusText + " • Visible as \"\(model.deviceName)\"")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Segmented Tab Picker
            Picker("Transfer method", selection: $model.tab) {
                ForEach(TransferModel.Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // Tab Content
            Group {
                switch model.tab {
                case .send: sendView
                case .receive: receiveView
                case .history: historyView
                case .usb: USBView(usb: model.usb, files: model.urls, chooseFiles: model.chooseFiles, horizontalPadding: 14, bottomPadding: 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom Bar
            HStack {
                Button(action: open) {
                    Label("Open NearByDrop", systemImage: "macwindow")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Spacer()

                Button(action: TransferModel.openDownloads) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open Downloads: \(model.downloadDirectory.lastPathComponent)")
                .accessibilityLabel("Open Downloads")

                if let settings = settings {
                    Button(action: settings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Settings…")
                    .accessibilityLabel("Settings")
                }

                Menu {
                    Toggle("Run as Menu Bar Only", isOn: $model.menuBarOnly)
                    Divider()
                    if let settings = settings {
                        Button("Settings…", action: settings)
                    }
                    if let guide = guide {
                        Button("Welcome Tour…", action: guide)
                    }
                    if let privacy = privacy {
                        Button("Privacy & Security Policy…", action: privacy)
                    }
                    Divider()
                    Toggle("Launch at Login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.toggleLaunchAtLogin(enabled: $0) }
                    ))
                    Toggle("Show NearByDrop in Dock", isOn: $theme.showInDock)
                    Divider()
                    Button("Change Download Location…") {
                        model.chooseDownloadDirectory()
                    }
                    Divider()
                    Button("Quit NearByDrop") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("More options")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 360, height: 505)
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
                    model.tab = .send
                    FeedbackManager.shared.vibrateClick()
                }
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.currentAccent.color, lineWidth: isDragging ? 2 : 0)
        )
    }

    // MARK: - Send View
    private var sendView: some View {
        VStack(spacing: 10) {
            // Selected files banner or File Picker button
            if !model.urls.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: model.urls.count > 1 ? "doc.on.doc.fill" : "doc.fill")
                        .foregroundStyle(theme.currentAccent.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.urls.count == 1 ? (model.displayNames.first ?? model.urls[0].lastPathComponent) : "\(model.urls.count) files ready")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(TransferModel.formatBytes(model.totalBytes))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change…") { model.chooseFiles() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    Button {
                        model.showQR()
                    } label: {
                        Image(systemName: "qrcode")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Show QR Code for phone")

                    Button {
                        model.setFiles([])
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(theme.currentAccent.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 8) {
                    Button(action: { model.chooseFiles() }) {
                        Label("Choose Files…", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.regular)

                    Button(action: { model.chooseFiles(thenSendTo: nil, thenShowQR: true) }) {
                        Label("QR Share", systemImage: "qrcode")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Generate QR code for phone")
                }
            }

            if model.showingQR {
                // Inline Quick Share QR View
                VStack(spacing: 8) {
                    Text("Quick Share with Phone")
                        .font(.headline)
                    Text("Scan with phone’s Camera or Google Lens to connect directly.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let image = model.qrImage {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 140, height: 140)
                            .padding(8)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.currentAccent.color)
                        Text("Quick Share Pairing Code")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())

                    Text(model.qrTransferStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button("Done", action: model.dismissQR)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            } else if model.sending {
                // In-progress sending
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(model.recipient, systemImage: "iphone")
                            .font(.headline)
                            .foregroundStyle(.primary)
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
            } else {
                // Nearby Devices List
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("NEARBY DEVICES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    if model.devices.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 26))
                                .foregroundStyle(.secondary)
                            Text("Looking for devices")
                                .font(.subheadline.weight(.medium))
                            Text("Open Quick Share in Receive mode on your phone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(model.devices, id: \.id) { device in
                                    Button {
                                        if model.urls.isEmpty {
                                            model.chooseFiles(thenSendTo: device)
                                        } else {
                                            model.send(to: device)
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: device.type == .computer ? "laptopcomputer" : "iphone")
                                                .foregroundStyle(theme.currentAccent.color)
                                                .frame(width: 20)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(device.name)
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(model.urls.isEmpty ? "Click to choose files and send" : "Click to send")
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
            }

            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Receive View
    private var receiveView: some View {
        VStack(spacing: 10) {
            if model.qrStatus != .idle {
                VStack(spacing: 12) {
                    switch model.qrStatus {
                    case .connecting(let sender):
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 32))
                            .foregroundStyle(theme.currentAccent.color)
                        Text(sender ?? "Connecting…")
                            .font(.headline)
                        ProgressView().controlSize(.small)
                        Button("Cancel", action: model.resetQRTransfer)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                    case .downloading(let sender, let description):
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(theme.currentAccent.color)
                        Text(sender)
                            .font(.headline)
                        if let desc = description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView().controlSize(.small)
                        Button("Cancel", action: model.resetQRTransfer)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                    case .completed(let filename, let count):
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                        Text("Transfer Complete")
                            .font(.headline)
                        Text(count > 1 ? "\(count) files saved" : "\(filename) saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Done", action: model.resetQRTransfer)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Open Downloads", action: TransferModel.openDownloads)
                                .buttonStyle(.borderedProminent)
                                .tint(theme.currentAccent.color)
                                .controlSize(.small)
                        }

                    case .failed(let error):
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                        Text("Transfer Failed")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again", action: model.resetQRTransfer)
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                    case .idle:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.incoming.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.incoming.keys.sorted(), id: \.self) { id in
                            if let item = model.incoming[id] {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: item.device.type == .computer ? "laptopcomputer" : "iphone")
                                            .foregroundStyle(theme.currentAccent.color)
                                        Text(item.device.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if let pin = item.transfer.pinCode {
                                            Text(pin)
                                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(theme.currentAccent.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
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
                                                .tint(theme.currentAccent.color)
                                                .controlSize(.small)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer(minLength: 6)
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 38))
                        .foregroundStyle(theme.currentAccent.color)
                    Text("Send to this Mac")
                        .font(.headline)
                    Text("Choose \"\(model.deviceName)\" in Quick Share on your phone, or scan a QR code.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    Button {
                        QRScannerWindowController.shared.show { [weak model] code in
                            model?.scan(code)
                        }
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.regular)
                    Spacer(minLength: 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Download Directory card
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("Folder: \(model.downloadDirectory.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Change…") {
                    model.chooseDownloadDirectory()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
    }

    // MARK: - History View
    private var historyView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recent Transfers")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear") { model.clearHistory() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }

            if model.history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Transfers Yet")
                        .font(.subheadline.weight(.medium))
                    Text("Files you send or receive will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.history) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.direction == .incoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(item.direction == .incoming ? Color.green : Color.blue)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.fileName)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(item.peerName)
                                        Text("•")
                                        Text(TransferModel.formatBytes(item.fileSize))
                                        Text("•")
                                        Text(TransferModel.formatDate(item.timestamp))
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if let url = item.fileURL {
                                    Button {
                                        if FileManager.default.fileExists(atPath: url.path) {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        } else {
                                            TransferModel.openDownloads()
                                        }
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .help("Show in Finder")
                                }
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
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
