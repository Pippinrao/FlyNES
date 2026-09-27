import AVFoundation

/// The sole camera owner for the pairing screen. Capture operations are serialized;
/// UI callbacks are accepted only for the current scan generation on the main queue.
final class NearbyQRScanner: NSObject {
    let captureSession = AVCaptureSession()
    private let queue = DispatchQueue(label: "FlyNES.Nearby.QR")
    private let onCode: (String) -> Void
    private let onUnavailable: () -> Void
    private var lifecycle = NearbyScanLifecycle()
    private var configured = false
    private var output: AVCaptureMetadataOutput?
    private var metadataDelegate: MetadataDelegate?

    init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
        self.onCode = onCode
        self.onUnavailable = onUnavailable
    }

    func start() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }
        guard lifecycle.rearm(to: lifecycle.generation &+ 1) else { return }
        let generation = lifecycle.generation
        #if targetEnvironment(simulator)
        DispatchQueue.main.async { [weak self] in self?.unavailable(generation: generation) }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart(generation: generation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.lifecycle.isCurrent(generation) else { return }
                    if granted { self.configureAndStart(generation: generation) }
                    else { self.unavailable(generation: generation) }
                }
            }
        default: unavailable(generation: generation)
        }
        #endif
    }

    func retry() { start() }

    func stop() {
        if Thread.isMainThread { lifecycle.stop() }
        else { DispatchQueue.main.sync { lifecycle.stop() } }
        queue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    private func unavailable(generation: UInt64) {
        guard lifecycle.isCurrent(generation) else { return }
        stop()
        onUnavailable()
    }

    private func configureAndStart(generation: UInt64) {
        queue.async { [weak self] in
            guard let self else { return }
            guard DispatchQueue.main.sync(execute: { self.lifecycle.isCurrent(generation) }) else { return }
            if !self.configured {
                guard let camera = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.captureSession.canAddInput(input) else {
                    DispatchQueue.main.async { self.unavailable(generation: generation) }
                    return
                }
                self.captureSession.beginConfiguration()
                self.captureSession.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.captureSession.canAddOutput(output) else {
                    self.captureSession.removeInput(input)
                    self.captureSession.commitConfiguration()
                    DispatchQueue.main.async { self.unavailable(generation: generation) }
                    return
                }
                self.captureSession.addOutput(output)
                output.metadataObjectTypes = [.qr]
                self.captureSession.commitConfiguration()
                self.output = output
                self.configured = true
            }
            let delegate = MetadataDelegate { [weak self] code in
                guard let self, self.lifecycle.isCurrent(generation), self.lifecycle.consume() else { return }
                self.stop()
                self.onCode(code)
            }
            self.metadataDelegate = delegate
            self.output?.setMetadataObjectsDelegate(delegate, queue: .main)
            guard DispatchQueue.main.sync(execute: { self.lifecycle.isCurrent(generation) }) else { return }
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
        }
    }

    private final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let code = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
                .first(where: { !$0.isEmpty }) else { return }
            onCode(code)
        }
    }
}
