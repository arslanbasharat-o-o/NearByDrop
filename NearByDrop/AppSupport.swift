import Cocoa

enum IncomingConsentPresentationState {
    static func applyDecision<Incoming, Progress>(
        transferID: String,
        accepted: Bool,
        incoming: inout [String: Incoming],
        progress: inout [String: Progress],
        acceptedIDs: inout Set<String>
    ) {
        if accepted {
            acceptedIDs.insert(transferID)
        } else {
            incoming.removeValue(forKey: transferID)
            progress.removeValue(forKey: transferID)
            acceptedIDs.remove(transferID)
        }
    }

    static func finish<Incoming, Progress>(
        transferID: String,
        incoming: inout [String: Incoming],
        progress: inout [String: Progress],
        acceptedIDs: inout Set<String>
    ) {
        incoming.removeValue(forKey: transferID)
        progress.removeValue(forKey: transferID)
        acceptedIDs.remove(transferID)
    }
}

extension NSWindow {
    func positionOnInteractionScreen() {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
    }
}

extension NSSavePanel {
    func presentForInteraction(relativeTo window: NSWindow? = nil, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        // A popover is transient; attach sheets only to regular document/settings windows.
        let parent = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        NSApp.activate(ignoringOtherApps: true)
        if let parent, parent.isVisible, parent.styleMask.contains(.titled), parent.attachedSheet == nil {
            beginSheetModal(for: parent, completionHandler: completion)
        } else {
            positionOnInteractionScreen()
            level = .popUpMenu
            begin(completionHandler: completion)
            makeKeyAndOrderFront(nil)
        }
    }
}

extension Notification.Name {
    static let didFinishChoosingFiles = Notification.Name("NearbyDropDidFinishChoosingFiles")
}

enum AppRelease {
    static var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "—") (\(info["CFBundleVersion"] as? String ?? "—"))"
    }


}

// Create a fresh folder so a phone name can never traverse or merge into existing data.
enum ReceivedFolder {
    static func create(in directory: URL, name: String) throws -> URL {
        let component = (name.replacingOccurrences(of: "\\", with: "_") as NSString).lastPathComponent
            .replacingOccurrences(of: ":", with: "_")
        let safe = component.isEmpty || component == "." || component == ".." ? "Received folder" : component
        for suffix in 1...10000 {
            let candidate = directory.appendingPathComponent(suffix == 1 ? safe : "\(safe) (\(suffix))", isDirectory: true)
            if mkdir(candidate.path, 0o700) == 0 { return candidate }
            if errno != EEXIST { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

struct ReceiveProgress {
    var bytes: Int64 = 0
    var total: Int64 = 0
    var started = Date()
    var updated = Date()
    var fraction: Double? { total > 0 ? min(1, Double(bytes) / Double(total)) : nil }
    var bytesPerSecond: Double {
        let elapsed = updated.timeIntervalSince(started)
        return elapsed >= 0.2 ? Double(bytes) / elapsed : 0
    }
}
