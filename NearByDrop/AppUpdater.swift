import AppKit
import Combine
import SwiftUI
import Sparkle

final class AppUpdater: NSObject, ObservableObject, SPUUserDriver {
    static let shared = AppUpdater()
    @Published private(set) var message = ""
    @Published private(set) var updateDetail = ""
    @Published private(set) var version: String?
    @Published private(set) var busy = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var lastCheckedAt: Date?
    var canInstall: () -> Bool = { true }
    var onAvailabilityChanged: ((Bool) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryTermination: (() -> Void)?
    private var downloaded: UInt64 = 0
    private var expected: UInt64 = 0
    private var updaterStarted = false
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)

    func start() {
        do {
            try updater.start()
            updaterStarted = true
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            lastCheckedAt = updater.lastUpdateCheckDate
        } catch {
            message = "Update failed: \(error.localizedDescription)"
            updateDetail = diagnosticDetails(for: error)
        }
    }

    func check() {
        guard updater.canCheckForUpdates else { return }
        message = "Checking for updates…"
        updateDetail = ""
        updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard updaterStarted, updater.automaticallyChecksForUpdates != enabled else { return }
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }

    func install() {
        guard canInstall() else { message = "Finish the current transfer to install the update."; return }
        if let retry = retryTermination {
            retryTermination = nil
            busy = true
            message = "Installing update…"
            retry()
            return
        }
        guard let reply = installReply else { return }
        installReply = nil
        busy = true
        message = "Downloading update…"
        reply(.install)
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        busy = true
        message = "Checking for updates…"
        updateDetail = ""
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        version = appcastItem.displayVersionString
        message = "Version \(appcastItem.displayVersionString) is available."
        updateDetail = ""
        lastCheckedAt = updater.lastUpdateCheckDate ?? Date()
        installReply = reply
        busy = false
        onAvailabilityChanged?(true)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let nsError = error as NSError
        let reason = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        switch reason {
        case SPUNoUpdateFoundReason.onLatestVersion.rawValue:
            message = "You’re up to date."
        case SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue:
            message = "This installed version is newer than the latest release."
        default:
            message = reason == nil ? "Could not confirm update status." : "No compatible update was found."
        }
        updateDetail = diagnosticDetails(for: error)
        lastCheckedAt = updater.lastUpdateCheckDate ?? Date()
        busy = false
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        message = "Update failed: \(error.localizedDescription)"
        updateDetail = diagnosticDetails(for: error)
        installReply = nil
        retryTermination = nil
        version = nil
        busy = false
        onAvailabilityChanged?(false)
        acknowledgement()
    }

    private func diagnosticDetails(for error: Error) -> String {
        let error = error as NSError
        return error.localizedRecoverySuggestion ?? error.localizedDescription
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloaded = 0
        expected = 0
        busy = true
        message = "Downloading update…"
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloaded += length
        if expected > 0 { message = "Downloading update… \(min(100, Int(Double(downloaded) / Double(expected) * 100)))%" }
    }
    func showDownloadDidStartExtractingUpdate() { message = "Verifying update…" }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard canInstall() else {
            installReply = reply
            busy = false
            message = "Update ready. Finish the transfer to install it."
            return
        }
        message = "Installing update…"
        reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        message = "Installing update…"
        if !applicationTerminated {
            retryTermination = retryTerminatingApplication
            if !canInstall() { deferInstallationForTransfer() }
        }
    }
    func deferInstallationForTransfer() {
        busy = false
        message = "Finish the transfer to update."
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() { busy = false }
}

struct AppUpdateView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var theme = ThemeManager.shared

    private var isFailure: Bool {
        updater.message.hasPrefix("Update failed:")
    }

    private var statusSymbol: String {
        if isFailure { return "exclamationmark.triangle.fill" }
        if updater.version != nil { return "arrow.down.circle.fill" }
        if updater.busy { return "arrow.clockwise" }
        if updater.message.hasPrefix("You’re up to date") { return "checkmark.circle.fill" }
        return "info.circle"
    }

    private var statusColor: Color {
        if isFailure { return .red }
        if updater.version != nil { return theme.currentAccent.color }
        if updater.message.hasPrefix("You’re up to date") { return .green }
        return .secondary
    }

    private var displayMessage: String {
        isFailure ? "Couldn’t check for updates." : updater.message
    }

    private var lastCheckedMessage: String? {
        guard !updater.busy, let date = updater.lastCheckedAt else { return nil }
        return "Last checked \(date.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if !updater.message.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: statusSymbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .accessibilityHidden(true)
                        Text(displayMessage)
                            .font(NearbyTypography.supporting)
                            .foregroundStyle(isFailure ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(2)
                            .help(updater.updateDetail.isEmpty ? updater.message : updater.updateDetail)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let lastCheckedMessage {
                    Text(lastCheckedMessage)
                        .font(NearbyTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if updater.version != nil {
                    updater.install()
                } else {
                    updater.check()
                }
            } label: {
                Text(updateButtonTitle)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(updater.version != nil ? .nearbyCompactPrimary : .nearbyCompactSecondary)
            .disabled(updater.busy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updateButtonTitle: String {
        if updater.version != nil { return updater.busy ? "Updating…" : "Update & Restart" }
        if updater.busy { return "Checking…" }
        return isFailure ? "Retry" : "Check for Updates"
    }
}
