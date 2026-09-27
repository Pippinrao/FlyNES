#pragma once

#include <flynes/flynes_runtime.h>
#include <nes/nes.h>

#include <cstddef>
#include <cstdint>
#include <vector>

namespace flynes::runtime_detail {

// A size probe and the following SaveState call each serialize independently.
// Accept a shorter successful write and retry a larger one without publishing
// an incomplete rollback slot.
template <typename Save>
fly_result capture_serialized_state(std::vector<std::uint8_t>& bytes, Save save)
{
    std::size_t written = 0;
    std::size_t needed = 0;
    if (save(nullptr, 0, &written, &needed) != NES_ERR_BUFFER_TOO_SMALL || needed == 0)
        return FLY_RESULT_INTERNAL_ERROR;

    for (unsigned attempt = 0; attempt < 4; ++attempt)
    {
        bytes.resize(needed);
        written = 0;
        std::size_t next_needed = 0;
        const int result = save(bytes.data(), bytes.size(), &written, &next_needed);
        if (result == NES_OK)
        {
            if (written == 0 || written > bytes.size()) return FLY_RESULT_INTERNAL_ERROR;
            bytes.resize(written);
            return FLY_RESULT_OK;
        }
        if (result != NES_ERR_BUFFER_TOO_SMALL || next_needed <= bytes.size())
            return FLY_RESULT_INTERNAL_ERROR;
        needed = next_needed;
    }
    return FLY_RESULT_INTERNAL_ERROR;
}

} // namespace flynes::runtime_detail
