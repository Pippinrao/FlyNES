import Foundation

/// Tracks which app-applied joinOnce configuration may be removed on teardown.
struct NearbyHotspotLease {
    struct Completion {
        let accepted: Bool
        let removeSSID: String?
    }

    private var generation: UInt64 = 0
    private var requestedSSID: String?
    private var activeSSID: String?
    private var ownedSSID: String?

    mutating func begin(ssid: String) -> UInt64 {
        generation &+= 1
        requestedSSID = ssid
        activeSSID = ssid
        ownedSSID = nil
        return generation
    }

    mutating func cancel() -> String? {
        generation &+= 1
        let remove = ownedSSID ?? requestedSSID
        ownedSSID = nil
        requestedSSID = nil
        activeSSID = nil
        return remove
    }

    mutating func complete(generation completed: UInt64, ssid: String,
                           owned: Bool) -> Completion {
        guard completed == generation, requestedSSID == ssid else {
            if owned && activeSSID == ssid {
                ownedSSID = ssid
            }
            return Completion(accepted: false,
                              removeSSID: owned && activeSSID != ssid ? ssid : nil)
        }
        requestedSSID = nil
        ownedSSID = owned || ownedSSID == ssid ? ssid : nil
        return Completion(accepted: true, removeSSID: nil)
    }

    func isCurrent(_ value: UInt64) -> Bool { value == generation }
}
