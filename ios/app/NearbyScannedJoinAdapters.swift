import Foundation

extension NearbyGuestNetwork: NearbyJoinNetworkPort {}

final class NearbyBridgeJoinPort: NearbyJoinSessionPort {
    private let bridge = FlyNesNearbyBridge.sharedInstance

    func join(_ invite: String, wifiOnly: Bool) -> Bool {
        do {
            if wifiOnly { try bridge.joinInvite(onWifi: invite) }
            else { try bridge.joinInvite(invite) }
            return true
        }
        catch { return false }
    }

    func cancel() { bridge.cancel() }
}

/// Process-scoped owner: the Wi-Fi joinOnce lease survives scanner navigation
/// and is released after the shared session ends, even if no page polls it.
final class NearbyBackendJoin {
    static let shared = NearbyBackendJoin()

    private let network = NearbyGuestNetwork()
    private let session = NearbyBridgeJoinPort()
    private lazy var flow = NearbyScannedJoinFlow(network: network, session: session)
    private var monitor: Timer?

    private init() {}

    @discardableResult func joinScannedText(_ text: String,
                                           completion: @escaping (Bool) -> Void) -> Bool {
        guard NearbyNetworkInvite.parse(text) != nil else { return false }
        monitor?.invalidate()
        monitor = nil
        return flow.joinScannedText(text) { [weak self] joined in
            if joined { self?.monitorSession() }
            else { self?.cancel() }
            completion(joined)
        }
    }

    func cancel() {
        monitor?.invalidate()
        monitor = nil
        flow.cancel()
    }

    private func monitorSession() {
        monitor?.invalidate()
        monitor = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let state = (FlyNesNearbyBridge.sharedInstance.snapshot()["state"] as? NSNumber)?.intValue ?? 0
            if NearbySessionLeasePolicy.shouldRelease(state: state) { self.cancel() }
        }
    }
}
