#pragma once

#include <cstdint>
#include <optional>

namespace flynes::session::lan_mvp {
// Pause ownership is independent of the renderer/page consuming the session.
struct PauseState {
    bool local = false;
    bool peer = false;
    bool resume_pending = false;
    bool paused() const { return local || peer || resume_pending; }
    std::uint8_t set_local(bool value, bool host) {
        local = value;
        return static_cast<std::uint8_t>(host ? local || peer : local);
    }
    bool resume() {
        if (resume_pending) return false;
        local = peer = false;
        resume_pending = true;
        return true;
    }
    std::optional<std::uint8_t> receive(std::uint8_t value, bool host) {
        // 0/1: ordinary pause; 2: Continue; 3/4: acknowledgement with local ownership.
        // FIFO makes the acknowledgement a barrier for older messages in the opposite direction.
        if (value == 2) {
            if (!resume_pending) local = false;
            peer = false;
            return static_cast<std::uint8_t>(local ? 4 : 3);
        }
        if (value == 3 || value == 4) {
            if (resume_pending) {
                resume_pending = false;
                peer = value == 4;
            }
            return {};
        }
        if (value > 1 || resume_pending) return {};
        peer = value != 0;
        if (host) return static_cast<std::uint8_t>(local || peer);
        return {};
    }
};
}
