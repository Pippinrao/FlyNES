#include "lan_mvp/lockstep.hpp"
#include "lan_mvp/wire.hpp"
#include "lan_mvp/pause.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>
#include <deque>

namespace {
int failures = 0;
void check(bool value, const char* message) {
    if (!value) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}
}

int main() {
    using namespace flynes::session::lan_mvp;

    // Two FIFO directions: an earlier guest pause crosses a host Continue.
    PauseState hostPause, guestPause;
    std::deque<std::uint8_t> toHost, toGuest;
    toHost.push_back(guestPause.set_local(true, false));
    check(hostPause.resume(), "host can request continue");
    toGuest.push_back(2);
    auto drain = [&]() {
        for (int step = 0; step < 20 && (!toHost.empty() || !toGuest.empty()); ++step) {
            if (!toHost.empty()) {
                const auto value = toHost.front(); toHost.pop_front();
                if (auto reply = hostPause.receive(value, true)) toGuest.push_back(*reply);
            }
            if (!toGuest.empty()) {
                const auto value = toGuest.front(); toGuest.pop_front();
                if (auto reply = guestPause.receive(value, false)) toHost.push_back(*reply);
            }
        }
        check(toHost.empty() && toGuest.empty(), "pause handshake settles without echo loop");
    };
    drain();
    check(!hostPause.paused() && !guestPause.paused(), "in-flight earlier pause cannot undo Continue");
    for (bool simultaneous : {false, true}) {
        hostPause = {}; guestPause = {};
        check(hostPause.resume(), "request starts a fresh barrier");
        toGuest.push_back(2);
        if (simultaneous) { check(guestPause.resume(), "peer also continues"); toHost.push_back(2); }
        drain();
        check(!hostPause.paused() && !guestPause.paused(), "one or both Continue requests settle unpaused");

        check(hostPause.resume(), "next Continue starts"); toGuest.push_back(2);
        check(!hostPause.resume(), "duplicate Continue is bounded while pending");
        if (simultaneous) { check(guestPause.resume(), "simultaneous peer Continue"); toHost.push_back(2); }
        toGuest.push_back(hostPause.set_local(true, true));
        drain();
        check(hostPause.paused() && guestPause.paused(), "new local pause after Continue survives its acknowledgement");
    }
    hostPause = {}; guestPause = {};
    check(hostPause.resume(), "host Continue before peer later pause");
    if (auto ack = guestPause.receive(2, false)) toHost.push_back(*ack);
    toHost.push_back(guestPause.set_local(true, false));
    drain();
    check(hostPause.paused() && guestPause.paused(), "receiver pause after acknowledgement survives");

    std::vector<std::uint8_t> first;
    std::vector<std::uint8_t> second;
    check(wire::encode(wire::Kind::Config, {1, 2, 3}, &first), "encode config");
    check(wire::encode(wire::Kind::Ready, {4}, &second), "encode ready");

    wire::Decoder split;
    check(split.push(first.data(), 1), "accept split prefix");
    wire::Message message{};
    check(!split.pop(&message), "partial prefix does not emit");
    check(split.push(first.data() + 1, first.size() - 1), "accept split body");
    check(split.pop(&message) && message.kind == wire::Kind::Config &&
          message.payload == std::vector<std::uint8_t>({1, 2, 3}),
          "fragmented message round trips");

    std::vector<std::uint8_t> joined = first;
    joined.insert(joined.end(), second.begin(), second.end());
    wire::Decoder coalesced;
    check(coalesced.push(joined.data(), joined.size()), "accept coalesced messages");
    check(coalesced.pop(&message) && message.kind == wire::Kind::Config,
          "first coalesced message");
    check(coalesced.pop(&message) && message.kind == wire::Kind::Ready,
          "second coalesced message");
    check(!coalesced.pop(&message), "coalesced buffer drained");

    const std::uint8_t invalid[] = {0xff, 0xff, 1};
    wire::Decoder rejected;
    check(!rejected.push(invalid, sizeof(invalid)) && rejected.failed(),
          "oversize length is rejected");

    lockstep::Buffer inputs(2, 8);
    check(inputs.put_local(0, 0) == lockstep::Put::Accepted, "zero frame local");
    check(inputs.put_remote(0, 0) == lockstep::Put::Accepted, "zero frame remote");
    lockstep::Frame frame{};
    check(inputs.pop_ready(&frame) && frame.index == 0 && frame.local_mask == 0 &&
          frame.remote_mask == 0, "complete frame advances once");
    check(!inputs.pop_ready(&frame), "completed frame does not repeat");
    check(inputs.put_local(2, 0x01) == lockstep::Put::Accepted, "buffered local input");
    check(!inputs.pop_ready(&frame), "one side cannot advance");
    check(inputs.put_remote(2, 0x80) == lockstep::Put::Accepted, "buffered remote input");
    check(inputs.put_remote(2, 0x80) == lockstep::Put::Duplicate, "duplicate is idempotent");
    check(inputs.put_remote(2, 0x40) == lockstep::Put::Conflict, "conflicting duplicate rejected");
    check(inputs.put_local(0, 0) == lockstep::Put::Late, "completed input is late");
    check(inputs.put_local(20, 0) == lockstep::Put::OutOfWindow, "far input is bounded");
    check(inputs.put_local(1, 0) == lockstep::Put::Accepted &&
          inputs.put_remote(1, 0) == lockstep::Put::Accepted,
          "missing current frame can arrive after future frame");
    check(inputs.pop_ready(&frame) && frame.index == 1, "current frame advances");
    check(inputs.pop_ready(&frame) && frame.index == 2 && frame.local_mask == 0x01 &&
          frame.remote_mask == 0x80, "future frame advances exactly once");

    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
