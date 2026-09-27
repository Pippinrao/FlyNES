import Foundation

enum NearbyScanFailure: Equatable {
    case invalid, network, expired, general

    var messageKey: String {
        switch self {
        case .invalid: return "nearby.scan.invalid"
        case .network: return "nearby.scan.networkUnavailable"
        case .expired: return "nearby.scan.expired"
        case .general: return "nearby.scan.joinUnavailable"
        }
    }

    static func sessionReason(_ reason: Int) -> NearbyScanFailure {
        switch reason {
        case 1: return .invalid
        case 2: return .network
        case 4: return .expired
        default: return .general
        }
    }
}

/// The pairing page uses this state for callbacks, retry, exit and navigation.
struct NearbyScanJoinState {
    enum Phase { case scanning, joiningNetwork, connecting, connected, failed }
    private(set) var phase: Phase = .scanning
    private(set) var generation: UInt64 = 0
    private(set) var failure: NearbyScanFailure?

    mutating func begin() -> UInt64? {
        guard phase == .scanning else { return nil }
        generation &+= 1
        phase = .joiningNetwork
        failure = nil
        return generation
    }

    mutating func didStart(_ started: Bool, generation: UInt64,
                          failure: NearbyScanFailure = .general) {
        guard self.generation == generation, phase == .joiningNetwork else { return }
        phase = started ? .connecting : .failed
        self.failure = started ? nil : failure
    }

    mutating func observe(state: Int, reason: Int) {
        guard phase == .joiningNetwork || phase == .connecting || phase == .connected else { return }
        if [3, 5, 6, 7].contains(state) { phase = .connected }
        else if phase != .joiningNetwork && (state == 4 || state == 0) {
            phase = .failed
            failure = NearbyScanFailure.sessionReason(reason)
        }
    }

    @discardableResult mutating func retry() -> Bool {
        let pending = phase == .joiningNetwork || phase == .connecting
        generation &+= 1
        phase = .scanning
        failure = nil
        return pending
    }

    @discardableResult mutating func leave() -> Bool {
        if phase == .connected {
            generation &+= 1
            return false
        }
        return retry()
    }
}

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
    private(set) var failure: NearbyScanFailure?

    init(network: NearbyJoinNetworkPort, session: NearbyJoinSessionPort) {
        self.network = network
        self.session = session
    }

    @discardableResult func joinScannedText(_ text: String,
                                           completion: @escaping (Bool) -> Void) -> Bool {
        guard let payload = NearbyNetworkInvite.parse(text) else {
            failure = .invalid
            return false
        }
        cancel()
        failure = nil
        let current = generation
        network.join(payload) { [weak self] available in
            guard let self, self.generation == current else { return }
            guard available else {
                self.failure = .network
                self.network.cancel()
                completion(false)
                return
            }
            let joined = self.session.join(payload.invite, wifiOnly: payload.ssid != nil)
            if !joined {
                self.failure = .general
                self.network.cancel()
            }
            completion(joined)
        }
        return true
    }

    func cancel() {
        releaseNetwork()
        session.cancel()
    }

    /// Preserve the terminal native reason so the page can display it.
    func releaseNetwork() {
        generation &+= 1
        network.cancel()
    }
}
