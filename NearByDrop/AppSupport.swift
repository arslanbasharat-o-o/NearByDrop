import Cocoa
import Combine
import NearbyShare
import UserNotifications

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

enum NearbyWindowMetrics {
    static let menuPopoverWidth: CGFloat = 390

    static let settingsContentSize = NSSize(width: 820, height: 680)
    static let settingsMinimumContentSize = NSSize(width: 720, height: 560)

    static let onboardingContentSize = NSSize(width: 700, height: 660)
    static let onboardingMinimumContentSize = NSSize(width: 660, height: 600)

    static let diagnosticsPreviewMinimumSize = CGSize(width: 640, height: 480)
    static let diagnosticsPreviewIdealSize = CGSize(width: 680, height: 520)
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

enum TransferNotificationManager {
    static let showDownloadsAction = "NearbyDrop.ShowDownloads"
    static let openAppAction = "NearbyDrop.OpenApp"
    private static let downloadsCategory = "NearbyDrop.TransferDownloads"
    private static let appCategory = "NearbyDrop.TransferApp"

    static func configure() {
        let center = UNUserNotificationCenter.current()
        let showDownloads = UNNotificationAction(
            identifier: showDownloadsAction,
            title: "Show Downloads",
            options: [.foreground]
        )
        let openApp = UNNotificationAction(
            identifier: openAppAction,
            title: "Open Nearby Drop",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: downloadsCategory, actions: [showDownloads], intentIdentifiers: []),
            UNNotificationCategory(identifier: appCategory, actions: [openApp], intentIdentifiers: [])
        ])
    }

    static func post(title: String, body: String, action: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = action == showDownloadsAction ? downloadsCategory : appCategory
            let request = UNNotificationRequest(
                identifier: "NearbyDrop.Transfer.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
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

// Favorites are local selection hints, never authenticated device identities.
struct FavoriteRecipientHint: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let category: String
    init(name: String, category: String) {
        self.id = UUID(); self.name = String(name.prefix(128)); self.category = category
    }
    func matches(name: String, category: String) -> Bool { self.name == name && self.category == category }
}

struct FolderEntry: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let size: UInt64
    let folder: Bool
}

enum FolderSort: String, CaseIterable, Identifiable {
    case name = "Name", nameDescending = "Name, Z–A", size = "Size, largest first"
    var id: String { rawValue }
    func listing(_ items: [FolderEntry], matching query: String) -> [FolderEntry] {
        items.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { a, b in
            if a.folder != b.folder { return a.folder }
            if self == .size, a.size != b.size { return a.size > b.size }
            let order = a.name.localizedStandardCompare(b.name)
            if order == .orderedSame { return a.id < b.id }
            return self == .nameDescending ? order == .orderedDescending : order == .orderedAscending
        }
    }
}

enum ExplicitShareContent {
    static func data(_ text: String, isLink: Bool) throws -> Data {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 65_536 else {
            throw NSError(domain: "Share", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter text up to 64 KB."])
        }
        if isLink {
            guard !text.contains(where: { $0.isNewline }), let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw NSError(domain: "Share", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter an HTTP or HTTPS link without embedded credentials."])
            }
        }
        return Data(text.utf8)
    }

    static func temporaryFile(data: Data, name: String) throws -> URL {
        guard !data.isEmpty, data.count <= 50 * 1024 * 1024,
              ["Shared text.txt", "Shared link.txt", "Screenshot.png"].contains(name) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NearbyDrop-share-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

struct ExperimentalBatchPlan {
    static let executionEnabled = false
    let ranges: [Range<Int>]
    init(fileCount: Int, maximumPerBatch: Int = 128) throws {
        guard (0...4096).contains(fileCount), (1...128).contains(maximumPerBatch) else {
            throw TransferFileRetryError.tooManyFiles
        }
        ranges = stride(from: 0, to: fileCount, by: maximumPerBatch).map { $0..<min(fileCount, $0 + maximumPerBatch) }
    }
}

final class FavoriteRecipients: ObservableObject {
    static let shared = FavoriteRecipients()
    @Published private(set) var items: [FavoriteRecipientHint]
    private let key = "favoriteRecipientHints"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        items = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([FavoriteRecipientHint].self, from: $0) } ?? []).prefix(80).map { $0 }
    }
    static func category(_ device: RemoteDeviceInfo) -> String {
        switch device.type { case .computer: return "Computer"; case .phone: return "Phone"; case .tablet: return "Tablet"; case .unknown: return "Device" }
    }
    func contains(_ device: RemoteDeviceInfo) -> Bool { items.contains { $0.matches(name: device.name, category: Self.category(device)) } }
    func toggle(_ device: RemoteDeviceInfo) {
        if contains(device) { items.removeAll { $0.matches(name: device.name, category: Self.category(device)) } }
        else if items.count < 80 { items.append(FavoriteRecipientHint(name: device.name, category: Self.category(device))) }
        save()
    }
    func remove(_ id: UUID) { items.removeAll { $0.id == id }; save() }
    private func save() { if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) } }
}
