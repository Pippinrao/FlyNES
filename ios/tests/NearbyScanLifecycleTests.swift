import Foundation

@main
struct NearbyScanLifecycleTests {
    static func main() {
        var lifecycle = NearbyScanLifecycle()
        precondition(!lifecycle.consume(), "camera metadata before start must be ignored")
        precondition(lifecycle.rearm(to: 1))
        precondition(lifecycle.consume(), "first QR must be accepted")
        precondition(!lifecycle.consume(), "duplicate metadata must be ignored")
        precondition(!lifecycle.rearm(to: 1), "same retry generation must not restart capture")
        precondition(lifecycle.rearm(to: 2), "failure must rearm capture")
        precondition(lifecycle.consume(), "a later QR must be accepted after retry")
        precondition(!lifecycle.rearm(to: 2), "duplicate retry must not restart capture")
        precondition(lifecycle.rearm(to: 3), "return from Settings must rearm capture")
        precondition(lifecycle.consume())
        let stoppedGeneration = lifecycle.generation
        lifecycle.stop()
        precondition(!lifecycle.consume(), "late camera metadata after stop must be ignored")
        precondition(!lifecycle.isCurrent(stoppedGeneration), "stopped capture invalidates permission callbacks")
        precondition(lifecycle.rearm(to: lifecycle.generation &+ 1))
        precondition(lifecycle.consume(), "a new scan may start after stop")
        print("NearbyScanLifecycleTests passed")
    }
}
