import Cocoa
import SwiftUI
import NearbyShare

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, MainAppDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    let model = TransferModel()
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppUpdater.shared.canInstall = { [weak self] in
            guard let model=self?.model else { return false }
            return !model.sending && model.incoming.isEmpty && !model.usb.transferring
        }
        AppUpdater.shared.onAvailabilityChanged = { [weak self] available in
            self?.statusItem?.button?.title = available ? " •" : ""
            self?.statusItem?.button?.setAccessibilityLabel(available ? "Nearby Drop, update available" : "Nearby Drop")
        }
        model.onConsent = { [weak self] id, accept in self?.consent(id, accept: accept) }
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = ThemeManager.shared.menuBarImage()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
        statusItem.button?.setAccessibilityLabel("Nearby Drop")
        ThemeManager.shared.onMenuBarIconChanged = { [weak self] in
            self?.statusItem.button?.image = ThemeManager.shared.menuBarImage()
        }

        popover.contentViewController = NSHostingController(rootView: MenuView(
            model: model,
            send: { [weak self] in self?.sendFiles(nil) },
            scan: { [weak self] in self?.scanCode(nil) },
            settings: { [weak self] in self?.openSettings(nil) },
            guide: { [weak self] in self?.openGuide(nil) },
            privacy: { [weak self] in self?.openPrivacy(nil) }
        ))
        popover.contentSize = NSSize(width: 360, height: 480)
        popover.behavior = .applicationDefined
        popover.delegate = self

        AppUpdater.shared.start()
        NearbyConnectionManager.shared.mainAppDelegate = self
        NearbyConnectionManager.shared.becomeVisible()

        NotificationCenter.default.addObserver(forName: .didFinishChoosingFiles, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if !self.popover.isShown {
                self.showPopover()
            } else if let window = self.popover.contentViewController?.view.window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            OnboardingWindowController.showOnboarding(onFinished: { [weak self] in
                self?.showPopover()
            })
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Nearby Drop")
        let aboutItem = NSMenuItem(title: "About Nearby Drop", action: #selector(openAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(openUpdates(_:)), keyEquivalent: "")
        updates.target = self
        appMenu.addItem(updates)
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
        appMenu.addItem(withTitle: "Hide Nearby Drop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Nearby Drop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        for (title, action, key) in [
            ("Show Nearby Drop", #selector(showMenu(_:)), "0"),
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
        let guideItem = NSMenuItem(title: "Nearby Drop Quick Start Guide", action: #selector(openGuide(_:)), keyEquivalent: "?")
        guideItem.target = self
        helpMenu.addItem(guideItem)
        let privacyItem = NSMenuItem(title: "Privacy & Security Policy", action: #selector(openPrivacy(_:)), keyEquivalent: "")
        privacyItem.target = self
        helpMenu.addItem(privacyItem)
        helpMenu.addItem(NSMenuItem.separator())
        let githubItem = NSMenuItem(title: "Nearby Drop on GitHub…", action: #selector(openGitHub(_:)), keyEquivalent: "")
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
        startMonitoringOutsideClicks()
    }

    func popoverDidShow(_ notification: Notification) {
        if let window = popover.contentViewController?.view.window {
            window.level = .popUpMenu
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoringOutsideClicks()
        model.scanning = false
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        return !shouldPreventPopoverDismissal()
    }

    private func shouldPreventPopoverDismissal() -> Bool {
        if model.scanning || model.isChoosingDirectory || model.isChoosingFiles || model.usb.isChoosingFiles {
            return true
        }
        if NSApp.windows.contains(where: { ($0 is NSOpenPanel || $0 is NSSavePanel) && $0.isVisible }) {
            return true
        }
        return false
    }

    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleOutsideClick()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleLocalClick(event)
            return event
        }
    }

    private func stopMonitoringOutsideClicks() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    private func handleOutsideClick() {
        guard popover.isShown, !shouldPreventPopoverDismissal() else { return }
        let mouseLocation = NSEvent.mouseLocation
        if let buttonWindow = statusItem.button?.window, buttonWindow.frame.contains(mouseLocation) {
            return
        }
        if let popoverWindow = popover.contentViewController?.view.window, popoverWindow.frame.contains(mouseLocation) {
            return
        }
        popover.performClose(nil)
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard popover.isShown, !shouldPreventPopoverDismissal() else { return }
        guard let popoverWindow = popover.contentViewController?.view.window else { return }
        if event.window === popoverWindow || event.window === statusItem.button?.window {
            return
        }
        popover.performClose(nil)
    }

    @objc private func toggleMenu() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            popover.contentSize = NSSize(width: 360, height: 480)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.level = .popUpMenu
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            startMonitoringOutsideClicks()
        }
    }
    @objc func showMenu(_ sender: Any?) { showPopover() }
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
        if let url = URL(string: "https://github.com/arslanbasharat-o-o/NearByDrop#privacy--security") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func openAbout(_ sender: Any?) {
        popover.performClose(nil)
        settingsWindow.show(tab: .about)
    }
    @objc func openUpdates(_ sender: Any?) { openAbout(sender); AppUpdater.shared.check() }
    @objc func openGitHub(_ sender: Any?) {
        if let url = URL(string: "https://github.com/arslanbasharat-o-o/NearByDrop") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func showSendTab(_ sender: Any?) {
        model.tab = .send
        showPopover()
    }
    @objc func showReceiveTab(_ sender: Any?) {
        model.tab = .receive
        showPopover()
    }
    @objc func showHistoryTab(_ sender: Any?) {
        model.tab = .history
        showPopover()
    }
    @objc func showUSBTab(_ sender: Any?) {
        model.tab = .usb
        showPopover()
    }
    @objc func sendFiles(_ sender: Any?) {
        model.tab = .send
        model.chooseFiles()
    }
    @objc func scanCode(_ sender: Any?) {
        model.tab = .receive
        model.scanning = true
        showPopover()
    }
    @objc func openDownloads(_ sender: Any?) { TransferModel.openDownloads() }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppUpdater.shared.busy && !AppUpdater.shared.canInstall() {
            AppUpdater.shared.deferInstallationForTransfer()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func consent(_ id: String, accept: Bool) {
        guard model.incoming[id] != nil, !model.accepted.contains(id) else { return }
        let device = model.incoming[id]?.device
        if accept {
            if let device { model.commitPendingDeviceTrust(id, device: device) }
            model.accepted.insert(id)
            FeedbackManager.shared.vibrateClick()
        } else {
            model.discardPendingDeviceTrust(id)
            model.incoming.removeValue(forKey: id)
            FeedbackManager.shared.vibrateTap()
        }
        NearbyConnectionManager.shared.submitUserConsent(transferID: id, accept: accept)
    }

    func obtainUserConsent(for transfer: TransferMetadata, from device: RemoteDeviceInfo) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.model.incoming.isEmpty { self.model.clearCompletedTransfer() }
            if !self.model.waitingForQR { self.model.qrStatus = .idle }
            self.model.incoming[transfer.id] = TransferInfo(device: device, transfer: transfer)
            self.model.tab = .receive
            let scannedTransfer = self.model.waitingForQR && device.id?.hasPrefix("qr:") == true
            if scannedTransfer {
                self.model.qrTransferID = transfer.id
                self.model.stopQRReceive()
            }

            // When receiving via QR code scanner, the user actively initiated by scanning the sender's code
            if scannedTransfer {
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
                return
            }

            FeedbackManager.shared.playIncoming()
            FeedbackManager.shared.vibrateTap()

            // Automatically open UI so incoming transfer is immediately visible
            self.showPopover()
        }
    }

    func incomingTransfer(id: String, didFinishWith error: Error?) {
        DispatchQueue.main.async {
            // Discovery probes and canceled requests are not user transfers.
            guard let info = self.model.incoming[id] else { return }
            let fileURL = info.transfer.files.first?.destinationURL
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let fileName: String
            if let text = info.transfer.textDescription {
                fileName = text
            } else if let first = info.transfer.files.first {
                fileName = info.transfer.files.count > 1 ? "\(first.name) (+\(info.transfer.files.count - 1))" : first.name
            } else {
                fileName = "File"
            }

            if error == nil {
                self.model.commitPendingDeviceTrust(id, device: info.device)
                let receivedURLs = info.transfer.files.compactMap(\.destinationURL)
                self.model.recordIncoming(info: info, fileURLs: receivedURLs)
                FeedbackManager.shared.playSuccess()
                FeedbackManager.shared.vibrateSuccess()

                self.model.lastCompletedTransfer = CompletedTransferInfo(
                    id: id,
                    fileName: fileName,
                    fileCount: info.transfer.files.count,
                    fileURL: fileURL,
                    destinationPath: self.model.downloadDirectoryDisplayPath
                )
                self.model.lastTransferError = nil

                if self.model.qrTransferID == id {
                    self.model.qrStatus = .completed(filename: fileName, count: info.transfer.files.count)
                }
            } else if let error {
                self.model.discardPendingDeviceTrust(id)
                NearbyLogger.log("[Nearby Drop] Inbound transfer \(id) finished with error: \(error)")
                FeedbackManager.shared.playError()
                FeedbackManager.shared.vibrateTap()

                self.model.lastCompletedTransfer = nil
                self.model.lastTransferError = TransferModel.errorMessage(error)

                if self.model.qrTransferID == id {
                    self.model.qrStatus = .failed(error: TransferModel.errorMessage(error))
                }
            }
            self.model.incoming.removeValue(forKey: id)
            self.model.incomingProgress.removeValue(forKey: id)
            self.model.accepted.remove(id)
            self.model.receiveMessage = error.map(TransferModel.errorMessage) ?? "Saved to \(self.model.downloadDirectoryDisplayPath)"
        }
    }

    func incomingTransferProgress(id: String, bytesTransferred: Int64, totalBytes: Int64) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.model.updateIncomingProgress(id: id, bytesTransferred: bytesTransferred, totalBytes: totalBytes)
        }
    }

    func advertisementStateDidChange(_ state: NearbyConnectionManager.AdvertisementState) {
        DispatchQueue.main.async { self.model.setAdvertisementState(state) }
    }
}

struct TransferInfo { let device: RemoteDeviceInfo; let transfer: TransferMetadata }

struct SonarWaveRing: View {
    let delay: Double
    let accent: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .stroke(accent.opacity(isAnimating ? 0.0 : 0.42), lineWidth: isAnimating ? 1.0 : 2.0)
            .scaleEffect(isAnimating ? 2.3 : 0.35)
            .animation(
                Animation.easeOut(duration: 2.2)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

struct RadarScanningView: View {
    @ObservedObject var theme = ThemeManager.shared
    @State private var floating = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 10)
            ZStack {
                SonarWaveRing(delay: 0.0, accent: theme.currentAccent.color)
                SonarWaveRing(delay: 0.7, accent: theme.currentAccent.color)
                SonarWaveRing(delay: 1.4, accent: theme.currentAccent.color)

                Circle()
                    .fill(theme.currentAccent.color.opacity(0.08))
                    .frame(width: 64, height: 64)

                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 48, height: 48)
                    .shadow(color: theme.currentAccent.color.opacity(0.18), radius: 6, y: 2)
                    .overlay(
                        Circle()
                            .stroke(theme.currentAccent.color.opacity(0.25), lineWidth: 1)
                    )

                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(theme.currentAccent.color)
                    .offset(y: floating ? -2 : 2)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: floating)
            }
            .frame(width: 120, height: 100)
            .onAppear { floating = true }

            VStack(spacing: 4) {
                Text("Looking for Devices")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Turn on Quick Share on your nearby device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MenuView: View {
    @ObservedObject var model: TransferModel
    let send: () -> Void
    let scan: () -> Void
    var settings: (() -> Void)? = nil
    var guide: (() -> Void)? = nil
    var privacy: (() -> Void)? = nil
    @ObservedObject private var theme = ThemeManager.shared
    @State private var isDragging = false
    @State private var lastStagedTitle: String = ""
    @State private var lastStagedBytes: Int64 = 0
    @State private var lastStagedIconPath: String? = nil
    @State private var lastStagedCount: Int = 1

    private func updateStagedSnapshot() {
        if !model.urls.isEmpty {
            lastStagedTitle = model.urls.count == 1 ? (model.displayNames.first ?? model.urls[0].lastPathComponent) : "\(model.urls.count) files ready"
            lastStagedBytes = model.totalBytes
            lastStagedIconPath = model.urls.count == 1 ? model.urls[0].path : nil
            lastStagedCount = model.urls.count
        }
    }

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
                        Text("Nearby Drop")
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

            AppUpdateView().padding(.horizontal, 14)

            // Tab Content
            Group {
                if model.scanning {
                    QRScannerView(onCode: model.scan, onCancel: { model.scanning = false })
                } else {
                    switch model.tab {
                    case .send: sendView
                    case .receive: receiveView
                    case .history: historyView
                    case .usb: USBView(usb: model.usb, files: model.urls, chooseFiles: model.chooseFiles, horizontalPadding: 14, bottomPadding: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: model.tab)

            Divider()

            // Bottom Bar
            HStack {
                Spacer()

                Button(action: TransferModel.openDownloads) {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open Downloads: \(model.downloadDirectoryDisplayPath)")
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
                    Button("Change Download Location…") { model.chooseDownloadDirectory() }
                    Button("Open Downloads Folder") { TransferModel.openDownloads() }
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
                    Button("About Nearby Drop") { (NSApp.delegate as? AppDelegate)?.openAbout(nil) }
                    Divider()
                    Button("Quit Nearby Drop") { NSApp.terminate(nil) }
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
        .frame(width: 360, height: 480)
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
        .onAppear { updateStagedSnapshot() }
        .onChange(of: model.urls) { updateStagedSnapshot() }
    }

    // MARK: - Send View
    private var stagedFilesCard: some View {
        let title = !model.urls.isEmpty ? (model.urls.count == 1 ? (model.displayNames.first ?? model.urls[0].lastPathComponent) : "\(model.urls.count) files ready") : lastStagedTitle
        let bytes = !model.urls.isEmpty ? model.totalBytes : lastStagedBytes
        let iconPath = !model.urls.isEmpty ? (model.urls.count == 1 ? model.urls[0].path : nil) : lastStagedIconPath
        let count = !model.urls.isEmpty ? model.urls.count : lastStagedCount

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let path = iconPath, count == 1 {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.currentAccent.color.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.currentAccent.color)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? "File ready" : title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(TransferModel.formatBytes(bytes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.setFiles([])
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Clear selection")
            }

            HStack(spacing: 8) {
                Button(action: { model.chooseFiles() }) {
                    Label("Change…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { model.showQR() }) {
                    Label("QR Code", systemImage: "qrcode")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Show QR Code for phone")
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var sendView: some View {
        VStack(spacing: 10) {
            // Selected files banner or File Picker button
            if !model.urls.isEmpty {
                stagedFilesCard
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
                    Text("Pair with QR Code")
                        .font(.headline)
                    Text("Scan with phone camera or Google Lens to connect directly.")
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
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 6)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [theme.currentAccent.color.opacity(0.85), theme.currentAccent.color],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(6, geo.size.width * CGFloat(max(0.0, min(1.0, model.progress)))), height: 6)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.progress)
                        }
                    }
                    .frame(height: 6)
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
                        RadarScanningView()
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
                                                Text(model.urls.isEmpty ? "Ready to send" : "Send files")
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
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.urls.isEmpty)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.sending)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.showingQR)
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
                        if let id = model.qrTransferID, let progress = model.incomingProgress[id], progress.total > 0 {
                            ProgressView(value: Double(progress.bytes) / Double(progress.total))
                        } else {
                            ProgressView().controlSize(.small)
                        }
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
                        if let id = model.qrTransferID, let progress = model.incomingProgress[id], progress.total > 0 {
                            ProgressView(value: Double(progress.bytes) / Double(progress.total))
                        } else {
                            ProgressView().controlSize(.small)
                        }
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
                                if model.accepted.contains(id) {
                                    IncomingTransferReceivingCard(id: id, item: item, model: model)
                                } else {
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

                                        Button {
                                            let current = model.isDeviceTrusted(for: id, device: item.device)
                                            model.setPendingDeviceTrusted(id, device: item.device, trusted: !current)
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: model.isDeviceTrusted(for: id, device: item.device) ? "checkmark.square.fill" : "square")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(model.isDeviceTrusted(for: id, device: item.device) ? theme.currentAccent.color : .secondary)
                                                Text("Trust this device")
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                            }
                                        }
                                        .buttonStyle(.plain)

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
                                    .padding(10)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
            } else if let completed = model.lastCompletedTransfer {
                TransferCompletionCard(completed: completed, model: model)
            } else if let error = model.lastTransferError {
                TransferErrorCard(error: error, model: model)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 38))
                            .foregroundStyle(theme.currentAccent.color)
                        Text("Ready to Receive")
                            .font(.headline)
                        Text("Select \(model.deviceName) on your device to share files.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)

                        Button(action: scan) {
                            Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.currentAccent.color)
                        .controlSize(.regular)

                        QuickShareGuideCard(deviceName: model.deviceName)
                            .padding(.top, 4)

                        Spacer(minLength: 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.lastCompletedTransfer == nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.incoming.isEmpty)
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

                                if let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) {
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
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
