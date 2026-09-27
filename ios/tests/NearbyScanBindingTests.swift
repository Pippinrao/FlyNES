import Foundation

/// Guards the screen-to-camera binding in addition to the pure lifecycle tests.
@main struct NearbyScanBindingTests {
    static func main() throws {
        let page = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let scanner = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            if !value { print("FAIL: \(message)"); failures += 1 }
        }
        check(page.contains("NearbyQRScanner("), "pairing screen must instantiate the protected scanner")
        check(!page.contains("AVCaptureSession()"), "pairing screen must not own a second capture implementation")
        check(!page.contains("scanFinished"), "join-start acknowledgement must not mark a scan connected")
        check(page.contains("scanState.leave()"), "page exit must invalidate and cancel a pending join")
        check(page.contains("scanState.retry()"), "manual retry must cancel the prior pending join")
        check(page.contains("nearby_hotspot_guidance"), "host hotspot guidance must have a visible UI binding")
        check(!scanner.contains("NearbyNetworkInvite.parse(code)"), "invalid QR must reach the error presentation")
        precondition(failures == 0, "scanner production binding regressions")
        print("NearbyScanBindingTests passed")
    }
}
