import Cocoa
import SwiftUI
import NearbyShare
import Network
import AVFoundation
import ScreenCaptureKit
import UniformTypeIdentifiers

final class ConnectionPathEvidence: ObservableObject {
    @Published private(set) var summary = "Checking the Mac’s network path…"
    @Published private(set) var available: Bool?
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.available = path.status == .satisfied
                self?.summary = path.status == .satisfied ? "macOS reports an available network path." : "macOS does not currently report an available network path."
            }
        }
        monitor.start(queue: DispatchQueue(label: "NearbyDrop.ConnectionDoctor"))
    }
    deinit { monitor.cancel() }
}

struct ConnectionDoctorView: View {
    @ObservedObject var model: TransferModel
    @ObservedObject private var theme = ThemeManager.shared
    @StateObject private var path = ConnectionPathEvidence()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Connection Doctor", systemImage: "stethoscope").font(NearbyTypography.pageTitle)
            Text("Find the next useful step, using what this Mac can actually observe.").foregroundStyle(theme.secondaryText)
            VStack(alignment: .leading, spacing: 12) {
                Label(path.summary, systemImage: path.available == true ? "checkmark.circle" : "network")
                Label(model.receivingPaused ? "Receiving is paused on this Mac." : "Receiving is enabled on this Mac.", systemImage: model.receivingPaused ? "pause.circle" : "antenna.radiowaves.left.and.right")
                Label("\(model.devices.count) recipients discovered in the current session.", systemImage: "laptopcomputer.and.iphone")
                Text("On the other device, open Quick Share, make it visible, and check its connection to a reachable local network.").foregroundStyle(theme.secondaryText)
            }.padding(14).nearbyCardSurface()
            DisclosureGroup("Technical details and limits") {
                Text("Receiving state: \(model.diagnosticsReportSnapshot.networkState.rawValue). Outgoing stage: \(model.outgoingPhase.rawValue). Last error category: \(model.diagnosticsReportSnapshot.lastErrorCategory?.rawValue ?? "none").\n\nA usable network path does not prove that both devices share a reachable network. macOS does not expose a reliable public permission-granted query for local-network access here. This tool cannot inspect the phone’s Quick Share settings, verify its client compatibility, or diagnose the router from this snapshot. Wi-Fi and Ethernet paths may both be valid.")
                    .font(NearbyTypography.supporting).foregroundStyle(theme.secondaryText).textSelection(.enabled).padding(.top, 6)
            }
            HStack {
                if model.receivingPaused {
                    Button("Resume Receiving") { model.setReceivingPaused(false) }.buttonStyle(.nearbySecondary)
                }
                Button("Search Again") { model.stopSendingDiscovery(); model.startSendingDiscovery() }.buttonStyle(.nearbySecondary)
            }
            HStack {
                Button("Use QR") { dismiss(); model.tab = .receive; model.scanning = true }.buttonStyle(.nearbySecondary)
                Button("Use USB") { dismiss(); model.tab = .usb }.buttonStyle(.nearbySecondary)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.nearbyPrimary).keyboardShortcut(.defaultAction)
            }
            Text("QR pairing still needs its supported network connection. USB needs an unlocked phone in File transfer mode.")
                .font(NearbyTypography.supporting).foregroundStyle(theme.secondaryText)
        }.padding(22).frame(width: 540).nearbyThemedWindow()
        .onAppear { model.startSendingDiscovery() }
        .onDisappear { if model.tab != .send && !model.showingQR { model.stopSendingDiscovery() } }
    }
}

struct TextSharingView: View {
    let onShare: (String, Bool) throws -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isLink = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send Text or a Link").font(NearbyTypography.pageTitle)
            Text("The receiver gets a UTF-8 .txt file. Native text/link payload interoperability has not been verified.")
                .foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            Toggle("This is a web link", isOn: $isLink)
            TextEditor(text: $text).font(.body).frame(height: 150).nearbyControlSurface()
                .accessibilityLabel(isLink ? "Web link to share" : "Text to share")
            HStack {
                Button("Paste") { text = NSPasteboard.general.string(forType: .string) ?? "" }.buttonStyle(.nearbySecondary)
                Text("\(text.utf8.count) / 65,536 bytes").font(NearbyTypography.supporting).foregroundStyle(theme.secondaryText)
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(theme.errorColor) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.nearbySecondary).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Receiver") {
                    do { try onShare(text, isLink); dismiss() } catch { self.error = error.localizedDescription }
                }.buttonStyle(.nearbyPrimary).disabled(text.isEmpty || text.utf8.count > 65_536)
            }
        }.padding(22).frame(width: 490).nearbyThemedWindow()
    }
}

struct ScreenshotSharingView: View {
    let onShare: (Data) throws -> Void
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var displays: [SCDisplay] = []
    @State private var selectedDisplay: CGDirectDisplayID = 0
    @State private var image: NSImage?
    @State private var png: Data?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screenshot to Device").font(NearbyTypography.pageTitle)
            Text("Capture one display after granting macOS permission, or choose an existing image. Review it before sharing.")
                .foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Choose a Screen…") { loadDisplays() }.buttonStyle(.nearbySecondary).disabled(busy)
                Button("Choose Image…") { chooseImage() }.buttonStyle(.nearbySecondary).disabled(busy)
            }
            if !displays.isEmpty {
                Picker("Display", selection: $selectedDisplay) {
                    ForEach(Array(displays.enumerated()), id: \.element.displayID) { index, display in
                        Text("Display \(index + 1) · \(display.width) × \(display.height)").tag(display.displayID)
                    }
                }
                Button("Capture Selected Display") { capture() }.buttonStyle(.nearbySecondary).disabled(busy)
            }
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 220)
                    .accessibilityLabel("Screenshot preview; review for private information")
                Text("Check for private information. Nothing is sent until you choose a receiver and start the transfer.")
                    .font(NearbyTypography.supporting).foregroundStyle(theme.secondaryText)
            }
            if busy { ProgressView("Preparing screenshot…") }
            if let error { Text(error).foregroundStyle(theme.errorColor).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.nearbySecondary).disabled(busy)
                Spacer()
                Button("Choose Receiver") {
                    guard let png else { return }
                    do { try onShare(png); dismiss() } catch { self.error = error.localizedDescription }
                }.buttonStyle(.nearbyPrimary).disabled(png == nil || busy)
            }
        }.padding(22).frame(width: 540).nearbyThemedWindow()
    }

    private func loadDisplays() {
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                displays = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
                selectedDisplay = displays.first?.displayID ?? 0
                if displays.isEmpty { error = "No capturable displays were returned. You can choose an existing screenshot instead." }
            } catch { self.error = "Screen capture access is unavailable. Review Screen & System Audio Recording in System Settings, or choose an existing image." }
        }
    }
    private func capture() {
        guard let display = displays.first(where: { $0.displayID == selectedDisplay }) else { return }
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let excluded = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = display.width; configuration.height = display.height; configuration.showsCursor = false
                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                let rep = NSBitmapImageRep(cgImage: cgImage)
                guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
                guard data.count <= 50 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                image = NSImage(cgImage: cgImage, size: .zero); png = data
            } catch { self.error = "Could not capture this display. Try choosing an existing screenshot." }
        }
    }
    private func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard (values.fileSize ?? Int.max) <= 50 * 1024 * 1024,
                      let input = NSImage(contentsOf: url), let tiff = input.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]),
                      data.count <= 50 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                image = input; png = data; error = nil
            } catch { self.error = "Choose a readable image smaller than 50 MB." }
        }
    }
}
