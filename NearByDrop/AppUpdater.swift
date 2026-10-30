import AppKit
import Combine
import SwiftUI
import Sparkle

final class AppUpdater: NSObject, ObservableObject, SPUUserDriver {
    static let shared = AppUpdater()
    @Published private(set) var message = ""
    @Published private(set) var version: String?
    @Published private(set) var busy = false
    var canInstall: () -> Bool = { true }
    var onAvailabilityChanged: ((Bool) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryTermination: (() -> Void)?
    private var downloaded: UInt64 = 0
    private var expected: UInt64 = 0
    private lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)

    func start() {
        do {
            try updater.start()
            updater.checkForUpdatesInBackground()
        } catch { message = error.localizedDescription }
    }

    func check() { if updater.canCheckForUpdates { updater.checkForUpdates() } }

    func install() {
        guard canInstall() else { message = "Finish the current transfer before updating."; return }
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
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        version = appcastItem.displayVersionString
        message = "Version \(appcastItem.displayVersionString) is available."
        installReply = reply
        busy = false
        onAvailabilityChanged?(true)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        message = "You’re up to date."
        busy = false
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        message = "Update failed: \(error.localizedDescription)"
        installReply = nil
        retryTermination = nil
        version = nil
        busy = false
        onAvailabilityChanged?(false)
        acknowledgement()
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
            message = "Update ready. Finish your transfer, then update."
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
        message = "Finish your transfer, then update."
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() { busy = false }
}

struct AppUpdateView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var theme = ThemeManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !updater.message.isEmpty { Text(updater.message).font(.caption).accessibilityAddTraits(.updatesFrequently) }
            if updater.version != nil {
                Button(updater.busy ? "Updating…" : "Update & Restart") { updater.install() }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.currentAccent.color)
                    .controlSize(.small)
                    .disabled(updater.busy)
            }
        }
    }
}
