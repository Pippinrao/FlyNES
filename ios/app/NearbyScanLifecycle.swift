struct NearbyScanLifecycle {
    private(set) var generation: UInt64 = 0
    private(set) var consumed = false
    private(set) var active = true

    init(generation: UInt64 = 0) { self.generation = generation }

    mutating func consume() -> Bool {
        guard active && !consumed else { return false }
        consumed = true
        return true
    }

    mutating func rearm(to generation: UInt64) -> Bool {
        guard generation != self.generation else { return false }
        self.generation = generation
        consumed = false
        active = true
        return true
    }

    mutating func stop() {
        generation &+= 1
        active = false
    }

    func isCurrent(_ value: UInt64) -> Bool { active && generation == value }
}
