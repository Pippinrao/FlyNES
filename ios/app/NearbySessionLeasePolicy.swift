enum NearbySessionLeasePolicy {
    static func shouldRelease(state: Int) -> Bool { state == 0 || state == 4 }
}
