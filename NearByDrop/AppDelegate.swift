import Cocoa
import SwiftUI
import NearbyShare
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, MainAppDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    lazy var model = TransferModel()
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PreviewRuntime.isSwiftUIPreviews else { return }
#if DEBUG
        if let idx = CommandLine.arguments.firstIndex(of: "--generate-screenshots"),
           CommandLine.arguments.count > idx + 1 {
            generateWebsiteScreenshots(to: URL(fileURLWithPath: CommandLine.arguments[idx + 1]))
            exit(0)
        }
#endif
        NearbyConnectionManager.invalidateLegacyTrustedDevices()
        NearbyConnectionManager.cleanupAbandonedPartialFiles()
        TransferNotificationManager.configure()
        UNUserNotificationCenter.current().delegate = self
        model.enableDefaultLaunchAtLoginIfNeeded()
        UsageAnalytics.start()
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
        popover.contentSize = NSSize(width: NearbyWindowMetrics.menuPopoverWidth, height: MenuView.preferredHeight(for: model))
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

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            || !UserDefaults.standard.bool(forKey: "diagnosticsDisclosureSeen") {
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
        let usbTab = NSMenuItem(title: "USB", action: #selector(showUSBTab(_:)), keyEquivalent: "4")
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
            popover.contentSize = NSSize(width: NearbyWindowMetrics.menuPopoverWidth, height: MenuView.preferredHeight(for: model))
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

    func resizePopover(to height: CGFloat) {
        guard popover.isShown else { return }
        popover.contentSize = NSSize(width: NearbyWindowMetrics.menuPopoverWidth, height: height)
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
    @MainActor @objc func sendFiles(_ sender: Any?) {
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            switch response.actionIdentifier {
            case TransferNotificationManager.showDownloadsAction:
                TransferModel.openDownloads()
            case TransferNotificationManager.openAppAction, UNNotificationDefaultActionIdentifier:
                self?.showPopover()
            default:
                break
            }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
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
        IncomingConsentPresentationState.applyDecision(
            transferID: id,
            accepted: accept,
            incoming: &model.incoming,
            progress: &model.incomingProgress,
            acceptedIDs: &model.accepted
        )
        if accept {
            if model.qrTransferID == id, let info = model.incoming[id] {
                let desc: String
                if let first = info.transfer.files.first {
                    desc = info.transfer.files.count > 1 ? "\(first.name) (+\(info.transfer.files.count - 1))" : first.name
                } else {
                    desc = info.transfer.textDescription ?? "Files"
                }
                model.qrStatus = .downloading(sender: info.device.name, description: desc)
            }
            FeedbackManager.shared.vibrateClick()
        } else {
            if model.qrTransferID == id {
                model.qrTransferID = nil
                model.qrStatus = .idle
            }
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
                // QR proof authenticates this session, but is not a reusable
                // trusted identity. Show the same approval card as other peers.
                self.model.qrStatus = .idle
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
                self.model.lastFailedIncoming = nil
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

                TransferNotificationManager.post(
                    title: "Transfer complete",
                    body: "Received \(fileName) from \(info.device.name).",
                    action: TransferNotificationManager.showDownloadsAction
                )

                if self.model.qrTransferID == id {
                    self.model.qrStatus = .completed(filename: fileName, count: info.transfer.files.count)
                }
            } else if let error {
                self.model.lastFailedIncoming = info
                NearbyLogger.log("[Nearby Drop] Inbound transfer failed")
                FeedbackManager.shared.playError()
                FeedbackManager.shared.vibrateTap()

                self.model.lastCompletedTransfer = nil
                self.model.lastTransferError = TransferModel.errorMessage(error)

                TransferNotificationManager.post(
                    title: "Transfer failed",
                    body: TransferModel.errorMessage(error),
                    action: TransferNotificationManager.openAppAction
                )

                if self.model.qrTransferID == id {
                    self.model.qrStatus = .failed(error: TransferModel.errorMessage(error))
                }
            }
            IncomingConsentPresentationState.finish(
                transferID: id,
                incoming: &self.model.incoming,
                progress: &self.model.incomingProgress,
                acceptedIDs: &self.model.accepted
            )
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

#if DEBUG
    func generateWebsiteScreenshots(to outputDirectory: URL) {
        let tabs: [(TransferModel.Tab, TransferModel.PreviewState, String)] = [
            (.send, .sendReady, "send.jpg"),
            (.receive, .receiveReady, "receive.jpg"),
            (.history, .historyEmpty, "transfers.jpg"),
            (.usb, .usbEmpty, "usb.jpg")
        ]
        
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        for (tab, state, filename) in tabs {
            let fixture = TransferModel.makePreviewFixture(tab: tab, state: state)
            let view = MenuView(
                model: fixture,
                send: {},
                scan: {},
                settings: {},
                guide: {},
                privacy: {}
            )
            .preferredColorScheme(.dark)
            
            let width: CGFloat = 386
            let height: CGFloat = 506
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = true
            window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
            window.contentView = hostingView
            window.layoutIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            
            let scale: CGFloat = 2.0
            let pixelWidth = Int(width * scale)
            let pixelHeight = Int(height * scale)
            
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { continue }
            
            rep.size = NSSize(width: width, height: height)
            
            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = context
                context.imageInterpolation = .high
                hostingView.displayIgnoringOpacity(hostingView.bounds, in: context)
            }
            NSGraphicsContext.restoreGraphicsState()
            
            if let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
                let fileURL = outputDirectory.appendingPathComponent(filename)
                try? jpegData.write(to: fileURL)
                print("Generated website screenshot: \(fileURL.path) (\(pixelWidth)x\(pixelHeight))")
            }
        }
    }
#endif
}

struct TransferInfo { let device: RemoteDeviceInfo; let transfer: TransferMetadata }

struct SonarWaveRing: View {
    let delay: Double
    let accent: Color
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(accent.opacity(isAnimating ? 0.0 : 0.32), lineWidth: isAnimating ? 1.0 : 1.5)
            .frame(width: 70, height: 70)
            .scaleEffect(isAnimating ? 1.55 : 0.45)
            .animation(
                reduceMotion ? nil : Animation.easeOut(duration: 2.2)
                    .repeatForever(autoreverses: false)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = !reduceMotion
            }
            .onChange(of: reduceMotion) { _, value in isAnimating = !value }
    }
}

struct RadarScanningView: View {
    @ObservedObject var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.presentationAccent)
                .frame(width: 34, height: 34)
                .background(theme.presentationAccent.opacity(0.10), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Looking for devices")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 4)
            ProgressView()
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .nearbyCardSurface(cornerRadius: 10)
    }
}

private struct MenuBarUtilitySurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false

    static func preferredHeight(for model: TransferModel) -> CGFloat {
        switch model.tab {
        case .send:
            if model.choosingRecipient { return 580 }
            if model.showingQR || model.sending || model.error != nil { return 560 }
            return model.urls.isEmpty ? 500 : 560
        case .receive:
            if !model.incoming.isEmpty { return 580 }
            if model.qrStatus != .idle || model.lastCompletedTransfer != nil || model.lastTransferError != nil { return 560 }
            return 500
        case .history:
            return min(560, 355 + CGFloat(min(model.history.count, 4)) * 48)
        case .usb:
            if model.usb.transferring || model.usb.lastDownloadedURL != nil || model.usb.error != nil { return 560 }
            return model.usb.deviceName.isEmpty ? 500 : 540
        }
    }

    private var preferredHeight: CGFloat {
        Self.preferredHeight(for: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("BrandLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Nearby Drop")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(model.deviceName)
                        .font(NearbyTypography.supporting)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.deviceName)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(NearbyTypography.emphasizedMetadata)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 13)
            .padding(.top, 9)
            .padding(.bottom, 7)

            HStack(spacing: 4) {
                ForEach(TransferModel.Tab.allCases, id: \.self) { tab in
                    let isSelected = model.tab == tab
                    Button {
                        model.tab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected && colorScheme == .dark ? Color(nsColor: .alternateSelectedControlTextColor) : (isSelected ? theme.presentationAccent : Color.secondary))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isSelected ? (colorScheme == .dark ? Color(nsColor: .selectedContentBackgroundColor) : theme.presentationAccent.opacity(0.16)) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isSelected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(tab.rawValue)
                    .accessibilityLabel("\(tab.rawValue) tab")
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            .padding(.horizontal, 13)
            .padding(.bottom, 7)
            Divider()

            // Tab Content
            Group {
                if model.scanning {
#if DEBUG
                    QRScannerView(
                        onCode: model.scan,
                        onCancel: { model.scanning = false },
                        previewState: model.previewScannerState
                    )
#else
                    QRScannerView(
                        onCode: model.scan,
                        onCancel: { model.scanning = false }
                    )
#endif
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
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.tab)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.scanning)
            .transaction { if reduceMotion { $0.animation = nil } }

            Divider()
            HStack(spacing: 8) {
                Button(action: TransferModel.openDownloads) {
                    Label("Downloads", systemImage: "folder")
                }
                .buttonStyle(.nearbyCompactQuiet)
                .help("Open Downloads: \(model.downloadDirectoryDisplayPath)")

                if let settings = settings {
                    Button(action: settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.nearbyCompactQuiet)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Change Download Location…") { model.chooseDownloadDirectory() }
                    Divider()
                    if let guide = guide {
                        Button("Quick Start Guide…", action: guide)
                    }
                    if let privacy = privacy {
                        Button("Privacy & Security Policy…", action: privacy)
                    }
                    Button("Check for Updates…") {
                        (NSApp.delegate as? AppDelegate)?.openUpdates(nil)
                    }
                    Divider()
                    Button("About Nearby Drop") { (NSApp.delegate as? AppDelegate)?.openAbout(nil) }
                    Divider()
                    Button("Quit Nearby Drop") { NSApp.terminate(nil) }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.nearbyCompactQuiet)
                .background(
                    Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.045),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.07), lineWidth: 1)
                )
                .accessibilityLabel("More Nearby Drop options")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: NearbyWindowMetrics.menuPopoverWidth, height: preferredHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .stroke(theme.presentationAccent, lineWidth: isDragging ? 2 : 0)
        )
        .onChange(of: preferredHeight) { _, height in
            (NSApp.delegate as? AppDelegate)?.resizePopover(to: height)
        }
        .animation(.easeInOut(duration: 0.18), value: preferredHeight)
    }

    // MARK: - Send View
    private var stagedFilesCard: some View {
        let files = Array(zip(model.urls, model.displayNames).enumerated()).prefix(4)
        return VStack(spacing: 0) {
            ForEach(Array(files), id: \.offset) { indexed in
                let index = indexed.offset
                let url = indexed.element.0
                let name = indexed.element.1
                HStack(spacing: 9) {
                    Image(systemName: "doc")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.presentationAccent)
                        .frame(width: 32, height: 34)
                        .background(theme.presentationAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(fileSubtitle(for: index, url: url))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.setFiles(model.urls.enumerated().filter { $0.offset != index }.map(\.element))
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.nearbyCompactDestructive)
                    .help("Remove \(name)")
                    .accessibilityLabel("Remove \(name)")
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                if index < files.count - 1 { Divider().padding(.leading, 50) }
            }
            if model.urls.count > 4 {
                Text("and \(model.urls.count - 4) more files")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
            }
        }
        .nearbyControlSurface(cornerRadius: 11)
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private func fileSubtitle(for index: Int, url: URL) -> String {
        let type: String
        switch url.pathExtension.lowercased() {
        case "zip": type = "ZIP archive"
        case "pdf": type = "PDF document"
        case "jpg", "jpeg": type = "JPEG image"
        case "png": type = "PNG image"
        case "mp4", "mov": type = "Video"
        default: type = url.pathExtension.uppercased().isEmpty ? "File" : "\(url.pathExtension.uppercased()) file"
        }
        let size = model.selectedFileSizes.indices.contains(index)
            ? TransferModel.formatBytes(model.selectedFileSizes[index])
            : nil
        return [size, type].compactMap { $0 }.joined(separator: " · ")
    }

    private var sendView: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if model.sending {
                    outgoingProgressView
                } else if model.outgoingPhase == .failed || model.error != nil {
                    outgoingFailureView
                } else if model.showingQR {
                    pairingQRView
                } else if model.urls.isEmpty {
                    sendLandingView
                } else if model.choosingRecipient {
                    recipientPickerView
                } else {
                    readyToSendView
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.urls.isEmpty)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.sending)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.showingQR)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.choosingRecipient)
    }

    private var sendLandingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Send files")
                .font(NearbyTypography.screenTitle)

            VStack(spacing: 9) {
                Image(systemName: "doc")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.presentationAccent)
                    .accessibilityHidden(true)
                Button(action: model.chooseFiles) {
                    Label("Choose files…", systemImage: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(minWidth: 120)
                }
                .buttonStyle(.nearbyPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 140)
            .nearbyControlSurface(cornerRadius: 11)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.presentationAccent.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if let notice = model.selectionNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var readyToSendView: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ready to send")
                    .font(NearbyTypography.screenTitle)
                Text("\(model.urls.count) files · \(TransferModel.formatBytes(model.totalBytes)) total")
                    .font(NearbyTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            stagedFilesCard
            HStack {
                Button(action: model.addFiles) { Label("Add files", systemImage: "plus") }
                    .buttonStyle(.nearbyCompactSecondary)
                Spacer()
                Button("Change files…", action: model.chooseFiles)
                    .buttonStyle(.nearbyCompactSecondary)
            }
            Button {
                model.choosingRecipient = true
                model.startSendingDiscovery()
            } label: {
                Text("Choose receiver").frame(maxWidth: .infinity)
            }
            .buttonStyle(.nearbyPrimary)
        }
    }

    private var recipientPickerView: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose a receiver")
                    .font(NearbyTypography.screenTitle)
                Text("\(model.urls.count) files · \(TransferModel.formatBytes(model.totalBytes)) ready to send")
                    .font(NearbyTypography.supporting)
                    .foregroundStyle(.secondary)
            }

            if model.devices.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 52, height: 52)
                        .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Looking nearby…").font(NearbyTypography.prominentBody)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("Cancel search", role: .cancel) {
                        model.stopSendingDiscovery()
                        model.choosingRecipient = false
                    }
                    .buttonStyle(.nearbyFullWidthSecondary)

                    Button(action: model.showQR) {
                        Label("Create pairing QR", systemImage: "qrcode")
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.nearbyFullWidthSecondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(model.devices, id: \.id) { device in
                    Button { model.send(to: device) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: device.type == .computer ? "laptopcomputer" : "iphone")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.presentationAccent)
                                .frame(width: 38, height: 38)
                                .background(theme.presentationAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(NearbyTypography.emphasizedMetadata).foregroundStyle(.primary)
                                Text(device.type == .computer ? "Windows" : "Android")
                                    .font(NearbyTypography.metadata).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .nearbyCardSurface(cornerRadius: 11)
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Text("\(model.devices.count) devices nearby").font(NearbyTypography.metadata).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") {
                        model.stopSendingDiscovery()
                        model.startSendingDiscovery()
                    }
                    .buttonStyle(.nearbyCompactQuiet)
                }
                Button(action: model.showQR) {
                    Label("Create pairing QR", systemImage: "qrcode").frame(maxWidth: .infinity)
                }
                .buttonStyle(.nearbySecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var pairingQRView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pair with a QR code").font(NearbyTypography.screenTitle)
            Spacer(minLength: 0)
            if let image = model.qrImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 138, height: 138)
                    .frame(maxWidth: .infinity)
            } else {
                Image(systemName: "qrcode").font(.system(size: 100, weight: .light)).frame(maxWidth: .infinity)
            }
            Text(model.qrTransferStatus)
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            Button("Cancel pairing", role: .cancel, action: model.dismissQR)
                .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
        }
    }

    private var outgoingProgressView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sending to \(model.recipient)").font(NearbyTypography.screenTitle)
            stagedFilesCard
            HStack {
                Text("\(Int(model.progress * 100))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                Spacer()
                Text("\(TransferModel.formatBytes(Int64(Double(model.totalBytes) * model.progress))) of \(TransferModel.formatBytes(model.totalBytes))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ProgressView(value: model.progress).tint(theme.presentationAccent)
            Text([model.transferSpeed, model.timeRemaining].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if !model.sendMessage.isEmpty { Text(model.sendMessage).font(.system(size: 10)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            Button("Cancel transfer", role: .cancel, action: model.cancelSend)
                .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
        }
    }

    private var outgoingFailureView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 18)).foregroundStyle(.red)
                    .frame(width: 48, height: 48)
                    .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connection lost").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(model.error ?? "The transfer stopped before all files were sent.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            stagedFilesCard
            HStack(spacing: 8) {
                Button("Choose another device") {
                    model.error = nil
                    model.choosingRecipient = true
                    model.startSendingDiscovery()
                }
                .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
                Button("Retry", action: model.retryFailedOutgoing)
                    .buttonStyle(.nearbyFullWidthPrimary)
                    .frame(maxWidth: .infinity)
                    .disabled(!model.canRetryFailedOutgoing || !model.retryPeerIsNearby)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Receive View
    private var receiveView: some View {
        VStack(spacing: 9) {
            let hasTransfer = !model.incoming.isEmpty || model.lastCompletedTransfer != nil || model.lastTransferError != nil
            if !hasTransfer && model.qrStatus == .idle && !model.receivingPaused {
                HStack(spacing: 8) {
                    Label("Receiving is on", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.presentationAccent)
                    Spacer()
                    Button("Pause receiving") { model.setReceivingPaused(true) }
                        .buttonStyle(.nearbyCompactSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .nearbyCardSurface(cornerRadius: 10)
            }

            Group {
                if model.qrStatus != .idle {
                    qrReceiveStatusView
                } else if !model.incoming.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 8) {
                            ForEach(model.incoming.keys.sorted(), id: \.self) { id in
                                if let item = model.incoming[id] {
                                    if model.accepted.contains(id) {
                                        IncomingTransferReceivingCard(id: id, item: item, model: model)
                                    } else {
                                        incomingApprovalCard(id: id, item: item)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else if let completed = model.lastCompletedTransfer {
                    TransferCompletionCard(completed: completed, model: model)
                } else if let error = model.lastTransferError {
                    TransferErrorCard(error: error, model: model)
                } else if model.receivingPaused {
                    pausedReceiveView
                } else {
                    readyReceiveView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.receivingPaused)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.lastCompletedTransfer == nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.incoming.isEmpty)
    }

    private var readyReceiveView: some View {
            VStack(spacing: 10) {
            Spacer(minLength: 2)
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(theme.presentationAccent)
                .accessibilityHidden(true)
            Text("Ready to receive")
                .font(.system(size: 17, weight: .semibold))
            Button(action: scan) {
                Label("Scan a pairing QR", systemImage: "qrcode.viewfinder")
                    .frame(minWidth: 155)
            }
            .buttonStyle(.nearbyPrimary)
            .disabled(model.receivingPaused)
            Spacer(minLength: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pausedReceiveView: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 2)
            Image(systemName: "moon.zzz")
                .font(.system(size: 31, weight: .regular))
                .foregroundStyle(theme.presentationAccent)
                .frame(width: 58, height: 58)
                .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Receiving is paused")
                .font(.system(size: 17, weight: .semibold))
            Button("Resume receiving") { model.setReceivingPaused(false) }
                .buttonStyle(.nearbyFullWidthPrimary)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 2)
        }
        .padding(.horizontal, 3)
    }

    private func incomingApprovalCard(id: String, item: TransferInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(item.device.name) wants to share")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(item.device.type == .computer ? "Windows" : "Android")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if !item.transfer.files.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(item.transfer.files.prefix(3).enumerated()), id: \.offset) { index, file in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.presentationAccent)
                                .frame(width: 28, height: 30)
                                .background(theme.presentationAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text(TransferModel.formatBytes(file.size)).font(NearbyTypography.metadata).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        if index < min(item.transfer.files.count, 3) - 1 { Divider().padding(.leading, 44) }
                    }
                    if item.transfer.files.count > 3 {
                        Text("and \(item.transfer.files.count - 3) more files")
                            .font(NearbyTypography.metadata).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                .nearbyControlSurface(cornerRadius: 9)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.10), lineWidth: 1))
            } else if let description = item.transfer.textDescription {
                Text(description).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }

            if let pin = item.transfer.pinCode {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Optional PIN")
                        .font(NearbyTypography.metadata.weight(.medium)).foregroundStyle(.secondary)
                    HStack {
                        Text(pin).font(.system(size: 14, weight: .semibold, design: .monospaced))
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.presentationAccent)
                    }
                }
                .padding(8)
                .background(theme.presentationAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Label("Save to \(model.downloadDirectoryDisplayPath)", systemImage: "folder")
                .font(NearbyTypography.metadata).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Decline", role: .cancel) { model.onConsent?(id, false) }
                    .buttonStyle(.nearbyFullWidthSecondary)
                    .frame(maxWidth: .infinity)
                Button(item.transfer.files.count == 1 ? "Accept file" : "Accept files") { model.onConsent?(id, true) }
                    .buttonStyle(.nearbyFullWidthPrimary)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10)
        .nearbyCardSurface(cornerRadius: 11)
    }

    @ViewBuilder
    private var qrReceiveStatusView: some View {
        VStack(spacing: 10) {
            switch model.qrStatus {
            case .connecting(let sender):
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 28)).foregroundStyle(theme.presentationAccent)
                Text("Connecting to \(sender ?? "nearby device")").font(.system(size: 15, weight: .semibold))
                ProgressView().controlSize(.small)
                Button("Cancel", role: .cancel, action: model.resetQRTransfer)
                    .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
            case .downloading(let sender, let description):
                Text("Receiving from \(sender)").font(.system(size: 15, weight: .semibold))
                if let description { Text(description).font(.system(size: 10)).foregroundStyle(.secondary) }
                if let id = model.qrTransferID, let progress = model.incomingProgress[id], progress.total > 0 {
                    ProgressView(value: Double(progress.bytes) / Double(progress.total))
                    Text("\(TransferModel.formatBytes(progress.bytes)) of \(TransferModel.formatBytes(progress.total))")
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                } else { ProgressView().controlSize(.small) }
                Button("Cancel transfer", role: .cancel, action: model.resetQRTransfer)
                    .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
            case .completed(let filename, let count):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(.green)
                Text("Transfer complete").font(.system(size: 16, weight: .semibold))
                Text(count == 1 ? "Received \(filename)" : "Received \(count) files")
                    .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Show in Finder", action: TransferModel.openDownloads)
                    .buttonStyle(.nearbyFullWidthPrimary).frame(maxWidth: .infinity)
                Button("Done", action: model.resetQRTransfer)
                    .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
            case .failed(let error):
                Image(systemName: "exclamationmark.circle").font(.system(size: 30)).foregroundStyle(.red)
                Text("Couldn’t save the file").font(.system(size: 16, weight: .semibold))
                Text(error).font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Downloads", action: TransferModel.openDownloads)
                    .buttonStyle(.nearbyFullWidthSecondary).frame(maxWidth: .infinity)
                Button("Done", action: model.resetQRTransfer)
                    .buttonStyle(.nearbyFullWidthPrimary).frame(maxWidth: .infinity)
            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent transfers").font(.system(size: 14, weight: .medium))
                Spacer()
                if !model.history.isEmpty {
                    Button("Clear", role: .destructive) { model.clearHistory() }
                        .buttonStyle(.nearbyCompactDestructive)
                }
            }

            if model.history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(theme.presentationAccent)
                    Text("No transfers yet").font(.system(size: 14, weight: .semibold))
                    Button("Send files", action: send)
                        .buttonStyle(.nearbyPrimary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 6) {
#if DEBUG
                        if model.previewState == .historyRecent {
                            historyDesignPreviewRows
                        } else {
                            historyCards
                        }
#else
                        historyCards
#endif
                    }
                }

            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var historyCards: some View {
        ForEach(model.history) { item in
            historyCard(for: item)
        }
    }

    private func historyCard(for item: TransferHistoryItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.direction == .incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.presentationAccent)
                .frame(width: 18, alignment: .leading)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.peerName) · \(item.direction.rawValue)")
                    .font(NearbyTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(TransferModel.formatBytes(item.fileSize)) · \(TransferModel.formatDate(item.timestamp))")
                    .font(NearbyTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        HStack(spacing: 3) {
                            Text("Show in Finder")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7, weight: .semibold))
                        }
                        .font(NearbyTypography.metadata)
                    }
                    .buttonStyle(.nearbyCompactQuiet)
                    .help("Show in Finder")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nearbyControlSurface(cornerRadius: 10)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

#if DEBUG
    @ViewBuilder
    private var historyDesignPreviewRows: some View {
        historyDesignPreviewRow(
            icon: "arrow.down.left", title: "Trail photos.zip",
            subtitle: "Alex’s Pixel 8 · Received", detail: "84 MB · Today, 10:42 AM", showFinder: true
        )
        historyDesignPreviewRow(
            icon: "arrow.up.right", title: "Coast weekend.zip + 1 file",
            subtitle: "Alex’s Pixel 8 · Sent", detail: "130.4 MB · Today, 10:38 AM", showFinder: true
        )
        historyDesignPreviewRow(
            icon: "arrow.up.left.and.arrow.down.right", title: "IMG_2048.jpg + 1 file",
            subtitle: "Alex’s Pixel 8 · USB · Downloaded", detail: "9.6 MB · Today, 10:24 AM", showFinder: true
        )
        historyDesignPreviewRow(
            icon: "exclamationmark.circle", title: "Coast weekend.zip + 1 file",
            subtitle: "Alex’s Pixel 8 · Failed", detail: "130.4 MB · Yesterday, 4:12 PM", showFinder: false, isError: true
        )
    }

    private func historyDesignPreviewRow(
        icon: String,
        title: String,
        subtitle: String,
        detail: String,
        showFinder: Bool,
        isError: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isError ? Color.red : theme.presentationAccent)
                    .frame(width: 18, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(subtitle)
                .font(NearbyTypography.metadata)
                .foregroundStyle(.secondary)
                .padding(.leading, 26)
                .lineLimit(1)
            Text(detail)
                .font(NearbyTypography.metadata)
                .foregroundStyle(.secondary)
                .padding(.leading, 26)
                .lineLimit(1)
            if showFinder {
                HStack(spacing: 3) {
                    Text("Show in Finder")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 7, weight: .semibold))
                }
                .font(NearbyTypography.metadata)
                .foregroundStyle(theme.presentationAccent)
                .padding(.leading, 26)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nearbyControlSurface(cornerRadius: 10)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
#endif

    private var statusLabel: String {
        switch model.advertisement {
        case .published: return "Available"
        case .failed: return "Unavailable"
        case .starting, .idle: return "Connecting"
        case .paused: return "Paused"
        }
    }

    private var statusColor: Color {
        switch model.advertisement {
        case .published: return .green
        case .failed: return .red
        case .starting, .idle: return .orange
        case .paused: return .secondary
        }
    }
}

#if DEBUG
#Preview("Send · Choose files") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .send, state: .empty), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Send · File preparation") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .send, state: .sendReady), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Send · Discovery in progress") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .send, state: .sendSearching), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Send · Nearby receivers") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .send, state: .sendRecipients), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Send · Pairing QR") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .send, state: .sendQR), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Send · Transfer in progress") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .send, state: .sendProgress), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Send · Transfer failed") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .send, state: .sendFailure), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Receive · Ready") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .receiveReady), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Receive · Paused") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .receivePaused), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Receive · Incoming approval") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .receiveConsent), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Receive · Transfer in progress") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .receiveProgress), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Receive · Saved to Downloads") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .receiveComplete), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Receive · Transfer error") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .receiveFailure), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("QR · Camera scanner") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .camera), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("QR · Camera permission denied") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .receive, state: .cameraDenied), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Transfers · Recent activity") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .history, state: .historyRecent), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("Transfers · Empty history") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .history, state: .historyEmpty), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("USB · Discovering devices") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .usb, state: .usbSearching), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("USB · No device connected") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .usb, state: .usbEmpty), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("USB · Browse and select files") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .usb, state: .usbBrowse), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("USB · Download in progress") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .usb, state: .usbProgress), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("USB · Download complete") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .usb, state: .usbComplete), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#Preview("USB · Connection error") {
    FigmaCanvasPreview { MenuView(model: TransferModel.makePreviewFixture(tab: .usb, state: .usbFailure), send: {}, scan: {}, settings: {}, guide: {}, privacy: {}) }
}
#endif
