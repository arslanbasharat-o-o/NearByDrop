import Cocoa
import NearbyShare

enum OutgoingAttemptPhase: String, Equatable {
    case idle
    case retrying
    case connecting
    case waitingForReceiver
    case transferring
    case failed
    case completed
    case cancelled

    var isActive: Bool {
        switch self {
        case .retrying, .connecting, .waitingForReceiver, .transferring: true
        case .idle, .failed, .completed, .cancelled: false
        }
    }
}

struct OutgoingAttemptLifecycle {
    private(set) var attemptID: UUID?
    private(set) var phase: OutgoingAttemptPhase = .idle
    private(set) var retryAvailable = false

    mutating func begin(retry: Bool) -> UUID? {
        guard !phase.isActive else { return nil }
        if retry && !(phase == .failed && retryAvailable) { return nil }

        let id = UUID()
        attemptID = id
        phase = retry ? .retrying : .connecting
        retryAvailable = false
        return id
    }

    @discardableResult
    mutating func transition(to next: OutgoingAttemptPhase, for id: UUID) -> Bool {
        guard attemptID == id, phase.isActive else { return false }
        phase = next
        retryAvailable = false
        return true
    }

    @discardableResult
    mutating func fail(for id: UUID, retryAllowed: Bool) -> Bool {
        guard attemptID == id, phase.isActive else { return false }
        phase = .failed
        retryAvailable = retryAllowed
        return true
    }

    @discardableResult
    mutating func complete(for id: UUID) -> Bool {
        guard attemptID == id, phase.isActive else { return false }
        phase = .completed
        retryAvailable = false
        return true
    }

    @discardableResult
    mutating func cancel(for id: UUID) -> Bool {
        guard attemptID == id, phase.isActive else { return false }
        phase = .cancelled
        retryAvailable = false
        return true
    }
}

enum OutgoingHistoryPolicy {
    static func sourceURL(for url: URL?, isRetry: Bool) -> URL? {
        isRetry ? nil : url
    }
}

enum DiagnosticsNetworkState: String, Codable {
    case ready
    case starting
    case unavailable
    case paused
}

enum DiagnosticsErrorCategory: String, Codable {
    case network
    case fileAccess
    case sourceChanged
    case connection
    case cancelled
    case other
}

struct DiagnosticsReportSnapshot: Equatable {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let architecture: String
    let networkState: DiagnosticsNetworkState
    let outgoingState: OutgoingAttemptPhase
    let incomingTransferCount: Int
    let outgoingTransferCount: Int
    let lastErrorCategory: DiagnosticsErrorCategory?
}

enum DiagnosticsReportBuilder {
    static func makeJSON(from snapshot: DiagnosticsReportSnapshot) throws -> String {
        let report: [String: Any] = [
            "format": "nearby-drop-diagnostics",
            "format_version": 1,
            "application": [
                "version": snapshot.appVersion,
                "build": snapshot.buildNumber
            ],
            "system": [
                "macos_version": snapshot.macOSVersion,
                "architecture": snapshot.architecture
            ],
            "status": [
                "receiving": snapshot.networkState.rawValue,
                "outgoing_transfer": snapshot.outgoingState.rawValue,
                "active_incoming_transfers": max(0, snapshot.incomingTransferCount),
                "active_outgoing_transfers": max(0, snapshot.outgoingTransferCount),
                "last_error_category": snapshot.lastErrorCategory?.rawValue ?? "none"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return text + "\n"
    }

    static func category(for error: Error?) -> DiagnosticsErrorCategory? {
        guard let error else { return nil }
        if let retryError = error as? TransferFileRetryError {
            switch retryError {
            case .sourceUnavailable, .accessExpired: return .fileAccess
            case .sourceChanged: return .sourceChanged
            case .tooManyFiles: return .other
            }
        }
        if let nearbyError = error as? NearbyError {
            switch nearbyError {
            case .inputOutput:
                return .fileAccess
            case .ukey2, .protocolError, .requiredFieldMissing:
                let message = nearbyError.localizedDescription.lowercased()
                if message.contains("changed") { return .sourceChanged }
                if message.contains("reachable") || message.contains("connection") || message.contains("network") {
                    return .network
                }
                return .connection
            case .canceled:
                return .cancelled
            case .receivingPaused:
                return .cancelled
            }
        }
        if (error as NSError).domain == NSURLErrorDomain { return .network }
        return .other
    }

    @discardableResult
    static func write(_ report: String, to destination: URL?) throws -> Bool {
        guard let destination else { return false }
        try Data(report.utf8).write(to: destination, options: .atomic)
        return true
    }
}

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
