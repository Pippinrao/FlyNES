import Foundation

@main struct NearbySessionLeasePolicyTests {
    static func main() {
        precondition(NearbySessionLeasePolicy.shouldRelease(state: 0))
        precondition(NearbySessionLeasePolicy.shouldRelease(state: 4))
        for state in [2, 3, 5, 6, 7] {
            precondition(!NearbySessionLeasePolicy.shouldRelease(state: state))
        }
        print("NearbySessionLeasePolicyTests passed")
    }
}
