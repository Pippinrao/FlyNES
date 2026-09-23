import AVFoundation

/// Camera QR source with no UI ownership. A future Nearby screen may display
/// `captureSession` in its scan area and pass results to the join flow.
final class NearbyQRScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    let captureSession = AVCaptureSession()
    private let queue = DispatchQueue(label: "FlyNES.Nearby.QR")
    private let onCode: (String) -> Void
    private let onUnavailable: () -> Void
    private var lifecycle = NearbyScanLifecycle()
    private var configured = false

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
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart(generation: generation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.lifecycle.isCurrent(generation) else { return }
                    if granted { self.configureAndStart(generation: generation) }
                    else { self.onUnavailable() }
                }
            }
        default: onUnavailable()
        }
    }

    func retry() { start() }

    func stop() {
        if Thread.isMainThread { lifecycle.stop() }
        else { DispatchQueue.main.sync { lifecycle.stop() } }
        queue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    private func configureAndStart(generation: UInt64) {
        queue.async { [weak self] in
            guard let self else { return }
            guard DispatchQueue.main.sync(execute: { self.lifecycle.isCurrent(generation) }) else { return }
            if !self.configured {
                guard let camera = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.captureSession.canAddInput(input) else {
                    DispatchQueue.main.async {
                        if self.lifecycle.isCurrent(generation) { self.onUnavailable() }
                    }
                    return
                }
                self.captureSession.beginConfiguration()
                self.captureSession.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.captureSession.canAddOutput(output) else {
                    self.captureSession.commitConfiguration()
                    DispatchQueue.main.async {
                        if self.lifecycle.isCurrent(generation) { self.onUnavailable() }
                    }
                    return
                }
                self.captureSession.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                self.captureSession.commitConfiguration()
                self.configured = true
            }
            guard DispatchQueue.main.sync(execute: { self.lifecycle.isCurrent(generation) }) else { return }
            if !self.captureSession.isRunning { self.captureSession.startRunning() }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
              NearbyNetworkInvite.parse(code) != nil,
              lifecycle.consume() else { return }
        stop()
        onCode(code)
    }
}
