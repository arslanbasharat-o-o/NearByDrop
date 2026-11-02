import SwiftUI
import AVFoundation
import Vision

final class QRScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "NearByDrop.camera")
    @Published var message = ""
    @Published var denied = false
    private var active = false
    private var wantsRunning = false
    private var lastFrame = Date.distantPast
    var onCode: ((String) -> String?)?

    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.wantsRunning else { return }
                    if allowed { self.configure() } else { self.permissionDenied() }
                }
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
    func stop() {
        wantsRunning = false
        queue.async {
            self.active = false
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }
            self.session.commitConfiguration()
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard active, Date().timeIntervalSince(lastFrame) > 0.4, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = Date()
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer).perform([request])
            guard let value = request.results?.first?.payloadStringValue else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wantsRunning else { return }
                self.handleCode(value)
            }
        } catch { DispatchQueue.main.async { self.message = "Could not read the QR code." } }
    }
    func handleCode(_ value: String) {
        guard let onCode else { return }
        if let error = onCode(value) { message = error }
        else { stop() }
    }
    deinit {
        // Never enqueue a closure retaining self while self is being deallocated.
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
}
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewView { PreviewView(session: session) }
    func updateNSView(_ nsView: PreviewView, context: Context) {
        if nsView.preview.session !== session { nsView.preview.session = session }
    }
    final class PreviewView: NSView {
        let preview: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            preview.videoGravity = .resizeAspectFill
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { return nil }
        override func layout() { super.layout(); preview.frame = bounds }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                preview.session = nil
            }
        }
    }
}
enum QRScannerPreviewState: Equatable {
    case scanning
    case permissionDenied
}

struct QRScannerView: View {
    @StateObject private var scanner = QRScanner()
    @ObservedObject private var theme = ThemeManager.shared
    let onCode: (String) -> String?
    let onCancel: () -> Void
    var previewState: QRScannerPreviewState? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scan a pairing QR")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            if previewState == .permissionDenied || (previewState == nil && scanner.denied) {
                cameraDeniedView
            } else {
                Group {
                    if previewState == .scanning {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.86))
                            .overlay {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 58, weight: .ultraLight))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                    } else {
                        CameraPreview(session: scanner.session)
                            .background(.black)
                            .overlay {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 58, weight: .ultraLight))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                    }
                }
                .frame(height: 176)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if previewState == .scanning {
                    Text("Looking for a QR code…")
                        .font(NearbyTypography.supporting)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else if !scanner.message.isEmpty {
                    Text(scanner.message)
                        .font(NearbyTypography.supporting)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            Button("Cancel", role: .cancel) {
                scanner.stop()
                onCancel()
            }
            .buttonStyle(.nearbySecondary)
            .frame(maxWidth: .infinity)
            .keyboardShortcut(.cancelAction)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            scanner.onCode = onCode
            if previewState == nil { scanner.start() }
        }
            .onDisappear {
                scanner.onCode = nil
                scanner.stop()
            }
    }

    private var cameraDeniedView: some View {
        VStack(spacing: 9) {
            Spacer(minLength: 0)
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 58, height: 58)
                .nearbyControlSurface(cornerRadius: 16)
            Text("Camera access is off")
                .font(NearbyTypography.prominentBody)
            Text("Enable camera access in System Settings to scan pairing QR codes.")
                .font(NearbyTypography.supporting)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Camera Settings") {
                guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
                NSWorkspace.shared.open(settingsURL)
            }
            .buttonStyle(.nearbyPrimary)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
