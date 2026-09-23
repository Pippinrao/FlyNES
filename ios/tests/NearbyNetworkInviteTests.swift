import Foundation

@main
struct NearbyNetworkInviteTests {
    static func main() {
        let plain = "flynes-lan-v1:192.168.4.21:4242:\(String(repeating: "a", count: 64)):\(String(repeating: "b", count: 32))"
        precondition(NearbyNetworkInvite.parse(plain)?.invite == plain)
        precondition(NearbyNetworkInvite.parse(plain)?.ssid == nil)

        let wrapped = "flynes-wifi-v1:Fly%20NES%3A1:p%25ssword:\(NearbyNetworkInvite.encodeField(plain))"
        let decoded = NearbyNetworkInvite.parse(wrapped)
        precondition(decoded?.ssid == "Fly NES:1")
        precondition(decoded?.passphrase == "p%ssword")
        precondition(decoded?.invite == plain)
        precondition(NearbyNetworkInvite.parse("flynes-wifi-v1:bad%ZZ:password:flynes-lan-v1%3Aa") == nil)
        precondition(NearbyNetworkInvite.parse("flynes-wifi-v1:Network:short:flynes-lan-v1%3Aa") == nil)
        precondition(NearbyNetworkInvite.parse("flynes-lan-v1:127.0.0.1:4242:\(String(repeating: "a", count: 64)):\(String(repeating: "b", count: 32))") == nil)
        precondition(NearbyNetworkInvite.parse("flynes-lan-v1:192.168.04.21:4242:\(String(repeating: "a", count: 64)):\(String(repeating: "b", count: 32))") == nil)
        precondition(NearbyNetworkInvite.parse("flynes-lan-v1:192.168.4.21:04242:\(String(repeating: "a", count: 64)):\(String(repeating: "b", count: 32))") == nil)

        print("NearbyNetworkInviteTests passed")
    }
}
