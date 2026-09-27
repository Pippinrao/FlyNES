#pragma once

#include <cstdint>

namespace flynes::ios {
enum class NearbyPlaybackAction { Submit, Hold, Exit };

inline NearbyPlaybackAction nearbyPlaybackAction(std::uint32_t state, bool paused) {
    if (state != 6) return NearbyPlaybackAction::Exit;
    return paused ? NearbyPlaybackAction::Hold : NearbyPlaybackAction::Submit;
}
}
