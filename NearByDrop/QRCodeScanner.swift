import SwiftUI
import AVFoundation
import Vision

final class QRScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "NearByDrop.camera")
    @Published var message = "Hold your phone’s Quick Share code in the frame."
    @Published var denied = false
    private var active = false
    private var lastFrame = Date.distantPast
    private var lastCode = ""
    var onCode: ((String) -> String?)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async { if allowed { self?.configure() } else { self?.permissionDenied() } }
            }
        default: permissionDenied()
        }
    }
    private func permissionDenied() { denied = true; message = "Allow camera access in System Settings to scan." }
    private func configure() {
        queue.async {
            self.active = true
            if self.session.inputs.isEmpty {
                guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.message = "No camera is available." }; return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                self.session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.queue)
                guard self.session.canAddOutput(output) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.message = "Could not start the camera." }; return
                }
                self.session.addOutput(output)
                self.session.commitConfiguration()
            }
            self.session.startRunning()
        }
    }
    func stop() { queue.async { self.active = false; self.session.stopRunning() } }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard active, Date().timeIntervalSince(lastFrame) > 0.4, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = Date()
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer).perform([request])
            guard let value = request.results?.first?.payloadStringValue, value != lastCode else { return }
            lastCode = value
            DispatchQueue.main.async {
                if let error = self.onCode?(value) { self.message = error }
                else { self.stop() }
            }
        } catch { DispatchQueue.main.async { self.message = "Could not read the code. Hold it steady and try again." } }
    }
}
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {}
    final class PreviewView: NSView {
        let preview: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() { super.layout(); preview.frame = bounds }
    }
}
struct QRScannerView: View {
    @StateObject private var scanner = QRScanner()
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> String?
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Scan QR Code").font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    if let onCancel = onCancel {
                        onCancel()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)
            }
            CameraPreview(session: scanner.session)
                .frame(height: 240).background(.black).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { Image(systemName: "viewfinder").font(.system(size: 120, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true) }
            Text(scanner.message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(minHeight: 34)
            if scanner.denied {
                Button("Open Camera Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!) }
            }
        }.padding(24).frame(width: 440)
            .onAppear { scanner.onCode = onCode; scanner.start() }
            .onDisappear { scanner.stop() }
    }
}

final class QRScannerWindowController: NSWindowController {
    static let shared = QRScannerWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Scan QR Code"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(onCode: @escaping (String) -> String?) {
        window?.contentView = NSHostingView(rootView: QRScannerView(onCode: { [weak self] code in
            let res = onCode(code)
            if res == nil {
                DispatchQueue.main.async {
                    self?.close()
                }
            }
            return res
        }, onCancel: { [weak self] in
            self?.close()
        }))
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
