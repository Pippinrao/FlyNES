import Foundation

private let invite = "flynes-lan-v1:192.168.43.1:4242:\(String(repeating: "a", count: 64)):\(String(repeating: "b", count: 32))"

private final class FakeNetwork: NearbyJoinNetworkPort {
    var requestedSSID: String?
    var pending: ((Bool) -> Void)?
    var cancelCalls = 0
    func join(_ payload: NearbyNetworkInvite, completion: @escaping (Bool) -> Void) {
        requestedSSID = payload.ssid
        pending = completion
    }
    func cancel() { cancelCalls += 1; pending = nil }
}

private final class FakeSession: NearbyJoinSessionPort {
    var joined: String?
    var wifiOnly: Bool?
    var joinCalls = 0
    var joinResult = true
    func join(_ invite: String, wifiOnly: Bool) -> Bool {
        joinCalls += 1
        joined = invite
        self.wifiOnly = wifiOnly
        return joinResult
    }
    func cancel() {}
}

@main struct NearbyScannedJoinFlowTests {
    static func main() {
        let network = FakeNetwork()
        let session = FakeSession()
        let flow = NearbyScannedJoinFlow(network: network, session: session)
        var result: Bool?
        let wifi = "flynes-wifi-v1:Host%20NES:password8:\(NearbyNetworkInvite.encodeField(invite))"
        precondition(flow.joinScannedText(wifi) { result = $0 })
        precondition(network.requestedSSID == "Host NES")
        precondition(session.joined == nil, "LAN join must wait for hotspot association")
        network.pending?(true)
        precondition(session.joined == invite && result == true)
        precondition(session.wifiOnly == true, "hotspot guest must bind the Wi-Fi interface")

        let beforeInvalid = network.cancelCalls
        precondition(!flow.joinScannedText("invalid") { _ in })
        precondition(network.cancelCalls == beforeInvalid && session.joinCalls == 1,
                     "invalid QR must preserve the active session and network")
        precondition(flow.joinScannedText(invite) { result = $0 })
        let late = network.pending
        flow.cancel()
        late?(true)
        precondition(session.joinCalls == 1, "cancelled result must not join again")

        session.joinResult = false
        precondition(flow.joinScannedText(wifi) { result = $0 })
        let beforeFailure = network.cancelCalls
        network.pending?(true)
        precondition(result == false && network.cancelCalls == beforeFailure + 1,
                     "failed session join must release the requested hotspot")
        precondition(flow.failure == .general)
        precondition(flow.joinScannedText(invite) { result = $0 })
        let beforeNetworkFailure = session.joinCalls
        network.pending?(false)
        precondition(flow.failure == .network && session.joinCalls == beforeNetworkFailure,
                     "network failure must be distinguished and must not start a native join")
        precondition(!flow.joinScannedText("not a room QR") { _ in })
        precondition(flow.failure == .invalid, "invalid QR must have actionable feedback")

        var state = NearbyScanJoinState()
        let attempt = state.begin()!
        state.didStart(true, generation: attempt)
        precondition(state.phase == .connecting, "accepted join is still connecting")
        precondition(state.leave(), "leaving during CONNECTING must cancel the pending session")
        state.didStart(true, generation: attempt)
        precondition(state.phase == .scanning, "late completion cannot revive an exited page")
        let retryAttempt = state.begin()!
        state.didStart(true, generation: retryAttempt)
        precondition(state.retry(), "retry during CONNECTING must cancel before scanning again")
        state.didStart(false, generation: retryAttempt)
        precondition(state.phase == .scanning, "late failure cannot replace the retried page")
        let connectedAttempt = state.begin()!
        state.didStart(true, generation: connectedAttempt)
        state.observe(state: 3, reason: 0)
        precondition(state.phase == .connected)
        precondition(!state.leave(), "navigation to the lobby must retain a connected session")
        var fastConnection = NearbyScanJoinState()
        _ = fastConnection.begin()
        fastConnection.observe(state: 3, reason: 0)
        precondition(!fastConnection.leave(),
                     "native connection before the queued start callback must survive navigation")
        var expired = NearbyScanJoinState()
        expired.didStart(true, generation: expired.begin()!)
        expired.observe(state: 4, reason: 4)
        precondition(expired.failure == .expired)
        precondition(expired.begin() == nil, "failure must wait for explicit retry")
        precondition(NearbyScanFailure.sessionReason(1) == .invalid)
        precondition(NearbyScanFailure.sessionReason(2) == .network)
        precondition(NearbyScanFailure.sessionReason(3) == .general)
        print("NearbyScannedJoinFlowTests passed")
    }
}
