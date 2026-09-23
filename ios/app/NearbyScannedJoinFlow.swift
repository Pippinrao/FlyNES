import Foundation

protocol NearbyJoinNetworkPort: AnyObject {
    func join(_ payload: NearbyNetworkInvite, completion: @escaping (Bool) -> Void)
    func cancel()
}

protocol NearbyJoinSessionPort: AnyObject {
    func join(_ invite: String, wifiOnly: Bool) -> Bool
    func cancel()
}

/// Consumes a scanned LAN/Wi-Fi QR payload without owning a screen or navigation.
final class NearbyScannedJoinFlow {
    private let network: NearbyJoinNetworkPort
    private let session: NearbyJoinSessionPort
    private var generation: UInt64 = 0

    init(network: NearbyJoinNetworkPort, session: NearbyJoinSessionPort) {
        self.network = network
        self.session = session
    }

    @discardableResult func joinScannedText(_ text: String,
                                           completion: @escaping (Bool) -> Void) -> Bool {
        guard let payload = NearbyNetworkInvite.parse(text) else { return false }
        cancel()
        let current = generation
        network.join(payload) { [weak self] available in
            guard let self, self.generation == current else { return }
            guard available else {
                self.network.cancel()
                completion(false)
                return
            }
            let joined = self.session.join(payload.invite, wifiOnly: payload.ssid != nil)
            if !joined { self.network.cancel() }
            completion(joined)
        }
        return true
    }

    func cancel() {
        generation &+= 1
        network.cancel()
        session.cancel()
    }
}
