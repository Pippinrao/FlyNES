import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

enum NearbyPairingMode: String {
    case create
    case scan
}

/// The native session survives navigation; this view owns only its camera and polling timer.
struct NearbyPairingView: View {
    let mode: NearbyPairingMode
    @Environment(\.dismiss) private var dismiss
    @State private var scannerMessage: LocalizedStringKey = "nearby.scan.cameraHint"
    @State private var scannerUnavailable = false
    @State private var scanGeneration = 0
    @State private var invite = ""
    @State private var inviteImage: UIImage?
    @State private var hostMessage = "nearby.invite.notReady"
    @State private var lobbyOpened = false
    @State private var scanState = NearbyScanJoinState()
    @State private var needsHotspotGuidance = false

    init(mode: NearbyPairingMode = .create) {
        self.mode = mode
    }

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
                            onCode: joinScannedText,
                            onUnavailable: markScannerUnavailable
                        )
                        .id(scanGeneration)
                        .accessibilityIdentifier("nearby_camera_preview")
                    } else {
                        VStack(spacing: 12) {
                            if let code = inviteImage {
                                Image(uiImage: code).interpolation(.none).resizable()
                                    .scaledToFit().padding(12).background(Color.white)
                                    .accessibilityIdentifier("nearby_invite_qr")
                            } else {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 54, weight: .thin))
                                Text("nearby.invite.notReady")
                                    .nearbyRole(NearbyTypography.muted)
                                    .multilineTextAlignment(.center)
                                    .accessibilityIdentifier("nearby_invite_unavailable")
                            }
                        }
                        .foregroundStyle(muted)
                    }
                }
                .frame(width: square, height: square)
                .background(surface, in: RoundedRectangle(cornerRadius: 16))
                .clipped()

                VStack(alignment: .leading, spacing: geometry.size.height > 400 ? 14 : 8) {
                    Text(mode == .scan ? "nearby.scan.headline" : "nearby.invite.headline")
                        .nearbyRole(NearbyTypography.paneTitle)
                        .foregroundStyle(ink)
                        .accessibilityIdentifier("nearby_invite_headline")
                    if mode == .scan || !needsHotspotGuidance {
                        Text(mode == .scan ? scannerMessage : LocalizedStringKey(hostMessage))
                            .nearbyRole(NearbyTypography.body)
                            .foregroundStyle(ink)
                            .accessibilityIdentifier("nearby_pairing_status")
                    }
                    if mode == .create && needsHotspotGuidance {
                        Text("nearby.invite.hotspotGuidance")
                            .nearbyRole(NearbyTypography.muted)
                            .foregroundStyle(muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("nearby_hotspot_guidance")
                    } else if geometry.size.height > 400 {
                        Text("nearby.network.autoHint")
                            .nearbyRole(NearbyTypography.muted)
                            .foregroundStyle(muted)
                    }
                    if mode == .create {
                        Button("nearby.action.regenerate") {
                            FlyNesNearbyBridge.sharedInstance.cancel()
                            invite = ""
                            inviteImage = nil
                            hostMessage = "nearby.invite.notReady"
                            do { try FlyNesNearbyBridge.sharedInstance.startHost() }
                            catch { hostMessage = "nearby.invite.backendUnavailable" }
                            refreshSession()
                        }
                        .nearbyRole(NearbyTypography.primaryAction)
                        .nearbyMinTap()
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("nearby_invite_regenerate")
                    }
                    if mode == .scan {
                        Button("nearby.scan.retry") {
                            if scanState.retry() { NearbyBackendJoin.shared.cancel() }
                            scannerUnavailable = false
                            scannerMessage = "nearby.scan.cameraHint"
                            scanGeneration += 1
                        }
                        .nearbyRole(NearbyTypography.primaryAction)
                        .nearbyMinTap()
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .accessibilityIdentifier("nearby_scan_retry")
                    }
                    Button("nearby.action.disconnect") {
                        if mode == .scan { NearbyBackendJoin.shared.cancel() }
                        FlyNesNearbyBridge.sharedInstance.cancel()
                        dismiss()
                    }
                    .nearbyRole(NearbyTypography.action)
                    .nearbyMinTap()
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("nearby_invite_disconnect")
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
        .onAppear {
            if mode == .create {
                let state = (FlyNesNearbyBridge.sharedInstance.snapshot()["state"] as? NSNumber)?.intValue ?? 0
                if state != 3 && state != 5 && state != 6 && state != 7 {
                    do { try FlyNesNearbyBridge.sharedInstance.startHost() }
                    catch { hostMessage = "nearby.invite.backendUnavailable" }
                }
            }
            refreshSession()
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            refreshSession()
        }
        .onDisappear {
            if mode == .scan {
                refreshSession()
                if scanState.leave() { NearbyBackendJoin.shared.cancel() }
            }
        }
    }

    private func joinScannedText(_ text: String) {
        guard let generation = scanState.begin() else { return }
        scannerMessage = "nearby.scan.joining"
        guard NearbyBackendJoin.shared.joinScannedText(text, completion: { started in
            let failure = NearbyBackendJoin.shared.failure ?? .general
            DispatchQueue.main.async {
                guard scanState.generation == generation else { return }
                scanState.didStart(started, generation: generation, failure: failure)
                if started { refreshSession() }
                else if let failure = scanState.failure {
                    scannerMessage = LocalizedStringKey(failure.messageKey)
                }
            }
        }) else {
            let failure = NearbyBackendJoin.shared.failure ?? .invalid
            scanState.didStart(false, generation: generation, failure: failure)
            scannerMessage = LocalizedStringKey(failure.messageKey)
            return
        }
    }

    private func markScannerUnavailable() {
        guard !scannerUnavailable else { return }
        scannerUnavailable = true
        scannerMessage = "nearby.scan.cameraUnavailable"
    }

    private func refreshSession() {
        let bridge = FlyNesNearbyBridge.sharedInstance
        let snapshot = bridge.snapshot()
        let state = (snapshot["state"] as? NSNumber)?.intValue ?? 0
        let reason = (snapshot["reason"] as? NSNumber)?.intValue ?? 0
        if mode == .create {
            needsHotspotGuidance = !bridge.hasUsableIPv4()
            let currentInvite = bridge.inviteText() ?? ""
            if currentInvite != invite {
                invite = currentInvite
                inviteImage = qrImage(currentInvite)
            }
            if !currentInvite.isEmpty && hostMessage != "nearby.role.host.hint" {
                hostMessage = "nearby.role.host.hint"
            }
        }
        if mode == .scan {
            scanState.observe(state: state, reason: reason)
            if let failure = scanState.failure {
                scannerMessage = LocalizedStringKey(failure.messageKey)
            }
        }
        if (state == 3 || state == 5 || state == 6 || state == 7) && !lobbyOpened {
            lobbyOpened = true
            NotificationCenter.default.post(name: Notification.Name("flynes.nearby.connected"), object: nil)
        }
    }

    private func qrImage(_ text: String) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
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

private final class NearbyCameraController: UIViewController {
    var onCode: ((String) -> Void)?
    var onUnavailable: (() -> Void)?
    private lazy var scanner = NearbyQRScanner(
        onCode: { [weak self] in self?.onCode?($0) },
        onUnavailable: { [weak self] in self?.onUnavailable?() }
    )
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: scanner.captureSession)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scanner.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    func stop() { scanner.stop() }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }
}
