import Foundation
import Darwin
import NearbyShare

enum UsageAnalytics {
    private static let enabledKey = "usageAnalyticsEnabled"
    private static let installationIDKey = "diagnosticsInstallationID"
    private static let firstLaunchDateKey = "diagnosticsFirstLaunchDate"
    private static let firstLaunchEventIDKey = "diagnosticsFirstLaunchEventID"
    private static let firstLaunchSentKey = "diagnosticsFirstLaunchSent"
    private static let endpointKey = "DiagnosticEventsEndpoint"

    private static let pendingKey = "diagnosticsPendingEvents"
    private static let queue = DispatchQueue(label: "NearbyDrop.Diagnostics")
    private static var task: URLSessionDataTask?
    private static var retryScheduled = false
    private static var generation = 0

    static var isEnabled: Bool {
        UserDefaults.standard.register(defaults: [enabledKey: true])
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var endpointIsConfigured: Bool {
        endpoint != nil
    }

    static func start() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [enabledKey: true])
        guard isEnabled, defaultsReady else { return }

        let storedFirstLaunch = defaults.object(forKey: firstLaunchDateKey) as? Date
        if storedFirstLaunch == nil || (!defaults.bool(forKey: firstLaunchSentKey)
            && storedFirstLaunch!.timeIntervalSinceNow < -7 * 86400) {
            defaults.set(Date(), forKey: firstLaunchDateKey)
            defaults.set(UUID().uuidString, forKey: firstLaunchEventIDKey)
        }

        if !defaults.bool(forKey: firstLaunchSentKey),
           let firstLaunch = defaults.object(forKey: firstLaunchDateKey) as? Date,
           let eventID = defaults.string(forKey: firstLaunchEventIDKey) {
            send("first_launch", eventID: eventID, occurredAt: firstLaunch)
        }

        send("app_opened")
    }

    static func setEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [enabledKey: true])
        guard defaults.bool(forKey: enabledKey) != enabled else { return }
        defaults.set(enabled, forKey: enabledKey)

        if enabled {
            start()
        } else {
            // Do not send a stored first-launch event retroactively after opt-out.
            defaults.removeObject(forKey: firstLaunchDateKey)
            defaults.removeObject(forKey: firstLaunchEventIDKey)
            defaults.removeObject(forKey: firstLaunchSentKey)
            queue.async {
                generation += 1
                retryScheduled = false
                task?.cancel()
                task = nil
                defaults.removeObject(forKey: pendingKey)
            }
        }
    }

    static func completedTransfer(direction: String, peer: RemoteDeviceInfo) {
        send("transfer_completed", properties: [
            "transfer_direction": direction,
            "peer_name": peer.name,
            "peer_type": peerTypeName(peer.type)
        ])
    }

    private static func peerTypeName(_ type: RemoteDeviceInfo.DeviceType) -> String {
        switch type {
        case .phone: return "phone"
        case .tablet: return "tablet"
        case .computer: return "computer"
        case .unknown: return "unknown"
        }
    }

    private static var macModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }

    private static var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: endpointKey) as? String,
              let components = URLComponents(string: value),
              components.host != nil,
              let url = components.url else { return nil }

        let scheme = components.scheme?.lowercased()
        let isSecure = scheme == "https"
#if DEBUG
        let isLocalDebugEndpoint = scheme == "http" && components.host == "127.0.0.1"
#else
        let isLocalDebugEndpoint = false
#endif
        guard isSecure || isLocalDebugEndpoint else { return nil }
        return url
    }

    private static func send(
        _ event: String,
        eventID: String = UUID().uuidString,
        occurredAt: Date = Date(),
        properties: [String: String] = [:]
    ) {
        guard isEnabled, defaultsReady, endpoint != nil else {
            return
        }

        let defaults = UserDefaults.standard
        let installationID: String
        if let stored = defaults.string(forKey: installationIDKey) {
            installationID = stored
        } else {
            installationID = UUID().uuidString
            defaults.set(installationID, forKey: installationIDKey)
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let roundedTime = floor(occurredAt.timeIntervalSince1970 / 3_600) * 3_600

        var payload: [String: Any] = [
            "event_id": eventID,
            "installation_id": installationID,
            "event": event,
            "occurred_at": formatter.string(from: Date(timeIntervalSince1970: roundedTime)),
            "app_name": "Nearby Drop",
            "app_version": appVersion,
            "macos_version": "\(os.majorVersion).\(os.minorVersion)",
            "mac_name": String(NearbyConnectionManager.currentDeviceName.prefix(60)),
            "mac_model": macModel
        ]
        properties.forEach { payload[$0.key] = String($0.value.prefix(60)) }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        queue.async {
            guard isEnabled else { return }
            var pending = UserDefaults.standard.array(forKey: pendingKey) as? [Data] ?? []
            if !pending.contains(body) { pending.append(body) }
            // Keep at most 200 reports for seven days; reporting must not grow local storage forever.
            UserDefaults.standard.set(Array(pending.suffix(200)), forKey: pendingKey)
            flush()
        }
    }

    private static var defaultsReady: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
            && UserDefaults.standard.bool(forKey: "diagnosticsDisclosureSeen")
    }

    // All queue state is confined to this serial queue; IDs survive retries and relaunches.
    private static func flush() {
        guard task == nil, isEnabled, defaultsReady, let endpoint else { return }
        let defaults = UserDefaults.standard
        let pending = (defaults.array(forKey: pendingKey) as? [Data] ?? []).filter { data in
            guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = event["occurred_at"] as? String else { return false }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: raw) else { return false }
            return date.timeIntervalSinceNow > -7 * 86400
        }
        defaults.set(pending, forKey: pendingKey)
        guard let body = pending.first else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NearbyDrop-Diagnostics/1", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let sendingGeneration = generation
        let sendingTask = URLSession.shared.dataTask(with: request) { data, response, error in
            queue.async {
                guard generation == sendingGeneration else { return }
                task = nil
                guard isEnabled else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let responseBody = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
                let success = error == nil && status == 202 && responseBody?["ok"] as? Bool == true
                // Invalid payloads cannot improve on retry; preserve transient failures.
                if success || [400, 413, 422].contains(status) {
                    var stored = defaults.array(forKey: pendingKey) as? [Data] ?? []
                    stored.removeAll { $0 == body }
                    defaults.set(stored, forKey: pendingKey)
                    if success,
                       let event = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                       event["event"] as? String == "first_launch" {
                        defaults.set(true, forKey: firstLaunchSentKey)
                    }
                    flush()
                } else if !retryScheduled {
                    retryScheduled = true
                    let retryAfter = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                    let delay = min(3600, max(60, Double(retryAfter ?? "") ?? 60))
                    queue.asyncAfter(deadline: .now() + delay) {
                        guard generation == sendingGeneration else { return }
                        retryScheduled = false
                        flush()
                    }
                }
            }
        }
        task = sendingTask
        sendingTask.resume()
    }
}
