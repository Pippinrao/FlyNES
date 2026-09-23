import Foundation

struct NearbyNetworkInvite {
    let ssid: String?
    let passphrase: String?
    let invite: String
    let port: Int

    static func parse(_ payload: String) -> NearbyNetworkInvite? {
        guard payload.utf8.count <= 1024 else { return nil }
        if payload.hasPrefix("flynes-lan-v1:") {
            guard let port = validPort(payload) else { return nil }
            return NearbyNetworkInvite(ssid: nil, passphrase: nil, invite: payload, port: port)
        }
        let fields = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == "flynes-wifi-v1",
              let ssid = decodeField(String(fields[1])), !ssid.isEmpty, ssid.utf8.count <= 32,
              let passphrase = decodeField(String(fields[2])),
              (8...63).contains(passphrase.utf8.count),
              let invite = decodeField(String(fields[3])),
              let port = validPort(invite) else { return nil }
        return NearbyNetworkInvite(ssid: ssid, passphrase: passphrase, invite: invite, port: port)
    }

    static func encodeField(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func decodeField(_ value: String) -> String? {
        let bytes = Array(value.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == 37 {
                guard index + 2 < bytes.count,
                      isHex(bytes[index + 1]), isHex(bytes[index + 2]) else { return nil }
                index += 3
            } else {
                guard bytes[index] < 128, bytes[index] != 43 else { return nil }
                index += 1
            }
        }
        return value.removingPercentEncoding
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
    }

    private static func validPort(_ invite: String) -> Int? {
        guard invite.utf8.count <= 256 else { return nil }
        let fields = invite.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 5, fields[0] == "flynes-lan-v1" else { return nil }
        let octets = fields[1].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        let parts = octets.compactMap { canonicalDecimal($0, maximum: 255) }
        guard parts.count == 4, parts[0] != 0, parts[0] != 127, parts[0] < 224,
              !(parts[0] == 169 && parts[1] == 254), parts[3] != 0, parts[3] != 255,
              let port = canonicalDecimal(fields[2], maximum: 65535), port != 0,
              fields[3].utf8.count == 64, fields[4].utf8.count == 32,
              fields[3].utf8.allSatisfy(isHex), fields[4].utf8.allSatisfy(isHex) else { return nil }
        return port
    }

    private static func canonicalDecimal(_ text: Substring, maximum: Int) -> Int? {
        guard !text.isEmpty, !(text.count > 1 && text.first == "0"),
              text.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(text), value <= maximum else { return nil }
        return value
    }
}
