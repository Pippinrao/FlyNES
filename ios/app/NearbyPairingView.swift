import AVFoundation
import SwiftUI

enum NearbyPairingMode: String {
    case create
    case scan
}

/// Presents the approved invitation/scanner composition without inventing an iOS session.
struct NearbyPairingView: View {
    let mode: NearbyPairingMode
    @State private var scannerMessage: LocalizedStringKey = "nearby.scan.cameraHint"
    @State private var scanGeneration = 0

    init(mode: NearbyPairingMode = .create) { self.mode = mode }

    private let background = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255)
    private let surface = Color(red: 27 / 255, green: 29 / 255, blue: 34 / 255)
    private let ink = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    private let muted = Color(red: 190 / 255, green: 184 / 255, blue: 174 / 255)
    private let accent = Color(red: 255 / 255, green: 107 / 255, blue: 94 / 255)

    var body: some View {
        GeometryReader { geometry in
            let square = max(120, min(geometry.size.height - 32, geometry.size.width * 0.44))
            HStack(spacing: 18) {
                Group {
                    if mode == .scan {
                        NearbyCameraPreview(
                            onCode: { _ in scannerMessage = "nearby.scan.joinUnavailable" },
                            onUnavailable: { scannerMessage = "nearby.scan.cameraUnavailable" }
                        )
                        .id(scanGeneration)
                        .accessibilityIdentifier("nearby_camera_preview")
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 54, weight: .thin))
                            Text("nearby.invite.notReady")
                                .nearbyRole(NearbyTypography.muted)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(muted)
                        .accessibilityIdentifier("nearby_invite_unavailable")
                    }
                }
                .frame(width: square, height: square)
                .background(surface, in: RoundedRectangle(cornerRadius: 16))
                .clipped()

                VStack(alignment: .leading, spacing: 14) {
                    Text(mode == .scan ? "nearby.scan.headline" : "nearby.invite.headline")
                        .nearbyRole(NearbyTypography.paneTitle)
                        .foregroundStyle(ink)
                        .accessibilityIdentifier("nearby_invite_headline")
                    Text(mode == .scan ? scannerMessage : "nearby.invite.backendUnavailable")
                        .nearbyRole(NearbyTypography.body)
                        .foregroundStyle(ink)
                        .accessibilityIdentifier("nearby_pairing_status")
                    Text("nearby.network.autoHint")
                        .nearbyRole(NearbyTypography.muted)
                        .foregroundStyle(muted)
                    if mode == .scan {
                        Button("nearby.scan.retry") {
                            scannerMessage = "nearby.scan.cameraHint"
                            scanGeneration += 1
                        }
                        .nearbyRole(NearbyTypography.primaryAction)
                        .nearbyMinTap()
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("nearby_scan_retry")
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background.ignoresSafeArea())
        }
        .navigationTitle(mode == .scan ? "nearby.screen.scan" : "nearby.screen.invite")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NearbyCameraPreview: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> NearbyCameraController {
        let controller = NearbyCameraController()
        controller.onCode = onCode
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ controller: NearbyCameraController, context: Context) { }

    static func dismantleUIViewController(_ controller: NearbyCameraController, coordinator: ()) {
        controller.stop()
    }
}

private final class NearbyCameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onUnavailable: (() -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed { self?.start() } else { self?.onUnavailable?() }
                }
            }
        default: onUnavailable?()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func start() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { onUnavailable?(); return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { onUnavailable?(); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished,
              let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
              !value.isEmpty else { return }
        finished = true
        onCode?(value)
        stop()
    }

    func stop() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }
}
