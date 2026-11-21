import Foundation

enum OperationalEventKind: String, Codable {
    case transferStarted = "transfer_started", transferCompleted = "transfer_completed"
    case transferFailed = "transfer_failed", transferCancelled = "transfer_cancelled", transferDeclined = "transfer_declined"
    case usbStarted = "usb_operation_started", usbFinished = "usb_operation_finished"
    case troubleshootingUsed = "troubleshooting_used", onboardingCompleted = "onboarding_completed", clientHealth = "client_health"
}
enum OperationalOutcome: String, Codable { case pending, completed, failed, cancelled, declined, none }
enum OperationalError: String, Codable { case none, network, fileAccess = "file_access", sourceChanged = "source_changed", connection, cancelled, declined, other }
enum OperationStage: String, Codable { case preparing, connecting, approval, transferring, none }

enum TransferMethod: String, Codable { case wifi, qr, usb, none }
enum TransferDirection: String, Codable { case incoming, outgoing, none }

struct OperationContext: Equatable {
    let jobID: UUID
    private(set) var attemptID: UUID
    private(set) var attemptNumber: Int
    let jobStartedAt: Date
    private(set) var attemptStartedAt: Date
    let method: TransferMethod
    let direction: TransferDirection
    let fileCount: Int
    let bytes: Int64
    private(set) var outcome: OperationalOutcome = .pending
    private(set) var stage: OperationStage = .preparing
    private var stageStartedAt: Date
    private var stageDurations: [OperationStage: TimeInterval] = [:]

    init(method: TransferMethod, direction: TransferDirection, fileCount: Int, bytes: Int64, now: Date = Date()) {
        jobID = UUID(); attemptID = UUID(); attemptNumber = 1
        jobStartedAt = now; attemptStartedAt = now; stageStartedAt = now; self.method = method; self.direction = direction
        self.fileCount = fileCount; self.bytes = bytes
    }
    mutating func retry(now: Date = Date()) -> Bool {
        guard outcome == .failed, attemptNumber < 100 else { return false }
        attemptID = UUID(); attemptNumber += 1; attemptStartedAt = now; outcome = .pending; stage = .preparing; stageStartedAt = now; stageDurations = [:]
        return true
    }
    mutating func advance(to next: OperationStage, now: Date = Date()) {
        guard outcome == .pending, next != stage else { return }
        stageDurations[stage, default: 0] += max(0, now.timeIntervalSince(stageStartedAt))
        stage = next; stageStartedAt = now
    }
    func stageBucket(_ target: OperationStage, now: Date) -> String {
        guard stageDurations[target] != nil || stage == target else { return "unknown" }
        return Self.durationBucket(seconds: (stageDurations[target] ?? 0) + (stage == target ? max(0, now.timeIntervalSince(stageStartedAt)) : 0))
    }
    @discardableResult mutating func finish(_ result: OperationalOutcome) -> Bool {
        guard outcome == .pending, ![.pending, .none].contains(result) else { return false }
        outcome = result; return true
    }
    var sizeBucket: String {
        switch bytes { case ..<0: return "unknown"; case 0: return "zero"; case ..<1_048_576: return "lt1mb"; case ..<10_485_760: return "1to10mb"; case ..<104_857_600: return "10to100mb"; case ..<1_073_741_824: return "100mbto1gb"; default: return "1gbplus" }
    }
    var countBucket: String {
        switch fileCount { case ..<0: return "unknown"; case 0: return "zero"; case 1: return "one"; case 2...10: return "2to10"; case 11...50: return "11to50"; case 51...128: return "51to128"; default: return "129plus" }
    }
    func durationBucket(now: Date) -> String {
        Self.durationBucket(seconds: max(0, now.timeIntervalSince(attemptStartedAt)))
    }
    private static func durationBucket(seconds: TimeInterval) -> String {
        switch seconds {
        case ..<1: return "lt1s"; case ..<5: return "1to5s"; case ..<30: return "5to30s"
        case ..<120: return "30to120s"; case ..<600: return "120to600s"; default: return "600plus"
        }
    }
}

/// Only typed, coarse operational fields can enter schema 2. Names/content are absent.
struct OperationalEvent: Encodable {
    let schemaVersion = 2
    let eventID: UUID
    let installationID: UUID
    let event: OperationalEventKind
    let occurredAt: String
    let appVersion: String
    let macOSVersion: String
    let deviceCategory = "computer"
    let jobID: UUID?
    let attemptID: UUID?
    let attemptNumber: Int
    let jobStartedAt: String?
    let method: TransferMethod
    let direction: TransferDirection
    let outcome: OperationalOutcome
    let sizeBucket: String
    let countBucket: String
    let durationBucket: String
    let errorCategory: OperationalError
    let queueBucket: String
    let stage: OperationStage
    let connectionDurationBucket: String
    let approvalDurationBucket: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", eventID = "event_id", installationID = "installation_id", event
        case occurredAt = "occurred_at", appVersion = "app_version", macOSVersion = "macos_version", deviceCategory = "device_category"
        case jobID = "job_id", attemptID = "attempt_id", attemptNumber = "attempt_number", jobStartedAt = "job_started_at"
        case method, direction, outcome, sizeBucket = "size_bucket", countBucket = "count_bucket", durationBucket = "duration_bucket"
        case errorCategory = "error_category", queueBucket = "queue_bucket", stage
        case connectionDurationBucket = "connection_duration_bucket", approvalDurationBucket = "approval_duration_bucket"
    }
    init(kind: OperationalEventKind, installationID: UUID, appVersion: String, macOSVersion: String,
         context: OperationContext? = nil, error: OperationalError = .none, queueCount: Int = 0, now: Date = Date()) {
        eventID = UUID(); self.installationID = installationID; event = kind
        occurredAt = Self.timestamp(now); self.appVersion = appVersion; self.macOSVersion = macOSVersion
        jobID = context?.jobID; attemptID = context?.attemptID; attemptNumber = context?.attemptNumber ?? 0
        jobStartedAt = context.map { Self.timestamp($0.jobStartedAt) }
        method = context?.method ?? .none; direction = context?.direction ?? .none; outcome = context?.outcome ?? .none
        sizeBucket = context?.sizeBucket ?? "unknown"; countBucket = context?.countBucket ?? "unknown"
        durationBucket = context?.durationBucket(now: now) ?? "unknown"; errorCategory = error
        stage = context?.stage ?? .none
        connectionDurationBucket = context?.stageBucket(.connecting, now: now) ?? "unknown"
        approvalDurationBucket = context?.stageBucket(.approval, now: now) ?? "unknown"
        switch queueCount { case ...0: queueBucket = "zero"; case 1...10: queueBucket = "1to10"; case 11...50: queueBucket = "11to50"; default: queueBucket = "51plus" }
    }
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60))
    }
}
