import Foundation

@main struct NearbyHotspotLeaseTests {
    static func main() {
        var lease = NearbyHotspotLease()
        let first = lease.begin(ssid: "Host NES")
        precondition(lease.cancel() == "Host NES", "cancel pending request removes its configuration")
        let stale = lease.complete(generation: first, ssid: "Host NES", owned: true)
        precondition(!stale.accepted && stale.removeSSID == "Host NES",
                     "late successful apply must be removed")

        let second = lease.begin(ssid: "Host NES")
        let success = lease.complete(generation: second, ssid: "Host NES", owned: true)
        precondition(success.accepted && success.removeSSID == nil)
        precondition(lease.cancel() == "Host NES", "active guest link is released at teardown")

        let existing = lease.begin(ssid: "Existing")
        precondition(lease.complete(generation: existing, ssid: "Existing", owned: false).accepted)
        precondition(lease.cancel() == nil, "already-associated user Wi-Fi is not removed")

        let old = lease.begin(ssid: "Retried")
        precondition(lease.cancel() == "Retried")
        let retry = lease.begin(ssid: "Retried")
        let lateSuccess = lease.complete(generation: old, ssid: "Retried", owned: true)
        precondition(!lateSuccess.accepted && lateSuccess.removeSSID == nil)
        precondition(lease.complete(generation: retry, ssid: "Retried", owned: false).accepted)
        precondition(lease.cancel() == "Retried",
                     "late owned join must transfer ownership to same-SSID retry")

        let earlier = lease.begin(ssid: "Reordered")
        precondition(lease.cancel() == "Reordered")
        let later = lease.begin(ssid: "Reordered")
        precondition(lease.complete(generation: later, ssid: "Reordered", owned: false).accepted)
        let lateApply = lease.complete(generation: earlier, ssid: "Reordered", owned: true)
        precondition(!lateApply.accepted && lateApply.removeSSID == nil)
        precondition(lease.cancel() == "Reordered",
                     "old apply may finish after current already-associated response")
        print("NearbyHotspotLeaseTests passed")
    }
}
