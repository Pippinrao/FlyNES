import Foundation

enum NearbyWifiReadiness {
    static func ready(expectedSSID: String, currentSSID: String?, hasWifiIPv4: Bool) -> Bool {
        currentSSID == expectedSSID && hasWifiIPv4
    }
}
