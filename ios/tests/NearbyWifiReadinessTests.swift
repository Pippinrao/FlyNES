import Foundation

@main
struct NearbyWifiReadinessTests {
    static func main() {
        precondition(!NearbyWifiReadiness.ready(expectedSSID: "Host", currentSSID: "Old LAN", hasWifiIPv4: true),
                     "an old LAN address must not complete the requested join")
        precondition(!NearbyWifiReadiness.ready(expectedSSID: "Host", currentSSID: nil, hasWifiIPv4: true))
        precondition(!NearbyWifiReadiness.ready(expectedSSID: "Host", currentSSID: "Host", hasWifiIPv4: false))
        precondition(NearbyWifiReadiness.ready(expectedSSID: "Host", currentSSID: "Host", hasWifiIPv4: true))
        print("NearbyWifiReadinessTests passed")
    }
}
