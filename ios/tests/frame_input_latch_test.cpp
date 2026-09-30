#include "run/FrameInputLatch.hpp"
#include <iostream>
int main() {
    flynes::ios::FrameInputLatch input;
    input.update(1); input.update(0); input.release(1, 1.0, 1.002);
    if (input.sample(1.005) != 1 || input.sample(1.016) != 1 || input.sample(1.018) != 0) {
        std::cerr << "FAIL: short A tap must last at least 17ms\n"; return 1;
    }
    input.update(1); input.update(0); input.release(1, 2.0, 2.002);
    input.update(128); input.update(0); // unrelated direction cancellation, no normal release
    if (input.sample(2.010) != 1) { std::cerr << "FAIL: unrelated cancellation erased A pulse\n"; return 1; }
    input.clear(); input.update(2); input.update(0); // canceled B must not create a pulse
    if (input.sample(3.001) != 0) { std::cerr << "FAIL: cancellation synthesized B tap\n"; return 1; }
    input.update(1); input.update(0); input.release(1, 4.0, 4.002);
    if (input.sample(4.100) != 1 || input.sample(4.101) != 0) {
        std::cerr << "FAIL: delayed frame must still consume a completed short tap once\n"; return 1;
    }
    input.release(2, 5.0, 5.050);
    if (input.sample(5.051) != 0) { std::cerr << "FAIL: long hold must not be extended\n"; return 1; }
    input.update(128); input.update(0);
    if (input.sample() != 0) { std::cerr << "FAIL: directions are not sticky\n"; return 1; }
    input.update(3); input.clear();
    if (input.sample() != 0) { std::cerr << "FAIL: cancel clears pending input\n"; return 1; }
    input.update(8);
    if (input.sample() != 8 || input.sample() != 8) { std::cerr << "FAIL: held START persists\n"; return 1; }
    input.clear(); input.release(1, 6.0, 6.002);
    if (input.peek(6.100) != 1 || input.peek(6.101) != 1 ||
        input.sample(6.102) != 1 || input.sample(6.103) != 0) {
        std::cerr << "FAIL: rejected frame must not consume a pending short tap\n"; return 1;
    }
    int failures = 0;
    input.clear();
    input.update(8); // Actual START goes down; no accepted frame samples it.
    input.update(0); input.release(8, 7.0, 7.150);
    const auto delayedPress = input.sample(7.151);
    const auto delayedRelease = input.sample(7.152);
    if (delayedPress != 8 || delayedRelease != 0) {
        std::cerr << "FAIL: unsampled 150ms START must reach the next frame once, then release; observed="
                  << delayedPress << ',' << delayedRelease << " expected=8,0\n";
        ++failures;
    }
    input.clear();
    input.update(8);
    const auto heldFirst = input.sample(8.050);
    const auto heldSecond = input.sample(8.100);
    input.update(0); input.release(8, 8.0, 8.150);
    const auto afterRelease = input.sample(8.151);
    const auto nextFrame = input.sample(8.152);
    if (heldFirst != 8 || heldSecond != 8 || afterRelease != 0 || nextFrame != 0) {
        std::cerr << "FAIL: sampled 150ms START hold must not repeat after release; observed="
                  << heldFirst << ',' << heldSecond << ',' << afterRelease << ',' << nextFrame
                  << " expected=8,8,0,0\n";
        ++failures;
    } else {
        std::cout << "sampled 150ms START release: PASS\n";
    }
    input.clear(); input.update(8);
    const auto rejectedPeek = input.peek(9.050); // Submit rejected; no commit.
    input.update(0); input.release(8, 9.0, 9.150);
    if (rejectedPeek != 8 || input.sample(9.151) != 8 || input.sample(9.152) != 0) {
        std::cerr << "FAIL: rejected held peek must not consume a later 150ms release\n";
        ++failures;
    }
    input.clear(); input.update(8); input.update(0); // Canceled, no release callback.
    const auto cancelled = input.peek(10.200);
    input.update(8);
    const auto newHeld = input.sample(10.300);
    input.update(0); input.release(8, 10.250, 10.450);
    if (cancelled != 0 || newHeld != 8 || input.sample(10.451) != 0) {
        std::cerr << "FAIL: canceled START must not leak into a later sampled long hold\n";
        ++failures;
    }
    input.clear(); input.update(1); input.update(2); // A rolls/cancels into B.
    input.update(0); input.release(2, 11.0, 11.150);
    if (input.sample(11.151) != 2 || input.sample(11.152) != 0) {
        std::cerr << "FAIL: canceled A must not leak into normal unsampled B release\n";
        ++failures;
    }
    input.clear(); input.update(8); input.clear(); input.release(8, 12.0, 12.150);
    if (input.sample(12.151) != 0) {
        std::cerr << "FAIL: pause/cancel clear must discard an unobserved long press\n";
        ++failures;
    }
    if (failures != 0) return 1;
    std::cout << "ios_frame_input_latch: PASS\n";
}
