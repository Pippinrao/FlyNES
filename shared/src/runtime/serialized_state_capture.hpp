#pragma once

#include <flynes/flynes_runtime.h>
#include <nes/nes.h>

#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace flynes::runtime_detail {

struct CaptureDiagnostic {
    int core_result = 0;
    unsigned attempts = 0;
    std::size_t capacity = 0, written = 0, needed = 0;
    bool core_call_returned = false;
};
inline thread_local CaptureDiagnostic last_capture;

// A size probe and the following SaveState call each serialize independently.
// Accept a shorter successful write and retry a larger one without publishing
// an incomplete rollback slot.
template <typename Save>
fly_result capture_serialized_state(std::vector<std::uint8_t>& bytes, Save save)
{
    std::size_t written = 0;
    std::size_t needed = 0;
    last_capture = {};
    const int probe = save(nullptr, 0, &written, &needed);
    last_capture = {probe, 0, 0, written, needed, true};
    if (probe != NES_ERR_BUFFER_TOO_SMALL || needed == 0)
        return FLY_RESULT_INTERNAL_ERROR;

    for (unsigned attempt = 0; attempt < 4; ++attempt)
    {
        last_capture.core_call_returned = false;
        bytes.resize(needed);
        written = 0;
        std::size_t next_needed = 0;
        const int result = save(bytes.data(), bytes.size(), &written, &next_needed);
        last_capture = {result, attempt + 1, bytes.size(), written, next_needed, true};
        if (result == NES_OK)
        {
            if (written == 0 || written > bytes.size()) return FLY_RESULT_INTERNAL_ERROR;
            bytes.resize(written);
            return FLY_RESULT_OK;
        }
        if (result != NES_ERR_BUFFER_TOO_SMALL || next_needed <= bytes.size())
            return FLY_RESULT_INTERNAL_ERROR;
        needed = next_needed;
        // Independent serializations may keep growing by a few bytes. Leave
        // headroom rather than chasing each exact size until retries run out.
        if (bytes.size() <= std::numeric_limits<std::size_t>::max() / 2 &&
            needed < bytes.size() * 2)
            needed = bytes.size() * 2;
    }
    return FLY_RESULT_INTERNAL_ERROR;
}

} // namespace flynes::runtime_detail
