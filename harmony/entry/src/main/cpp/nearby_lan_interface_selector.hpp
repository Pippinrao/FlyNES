#pragma once

#include <array>
#include <string>
#include <vector>

namespace flynes::harmony {

struct NearbyLanInterface {
    std::string name;
    std::string address;
};

inline bool valid_private_ipv4(const std::string& text)
{
    std::array<unsigned, 4> octets{};
    std::size_t start = 0;
    for (std::size_t i = 0; i < octets.size(); ++i) {
        const std::size_t end = text.find('.', start);
        if ((i < 3 && end == std::string::npos) ||
            (i == 3 && end != std::string::npos)) return false;
        const std::size_t size = (end == std::string::npos ? text.size() : end) - start;
        if (size == 0 || size > 3 || (size > 1 && text[start] == '0')) return false;
        unsigned value = 0;
        for (std::size_t j = 0; j < size; ++j) {
            const char digit = text[start + j];
            if (digit < '0' || digit > '9') return false;
            value = value * 10u + static_cast<unsigned>(digit - '0');
        }
        if (value > 255) return false;
        octets[i] = value;
        start = end + 1;
    }
    return (octets[0] == 10 ||
            (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
            (octets[0] == 192 && octets[1] == 168)) &&
           octets[3] != 0 && octets[3] != 255;
}

inline std::string select_guest_ipv4(const std::vector<NearbyLanInterface>& candidates)
{
    int best_rank = 3;
    std::string best_name;
    std::string selected;
    for (const auto& candidate : candidates) {
        int rank = 3;
        if (candidate.name.rfind("wlan", 0) == 0) rank = 0;
        else if (candidate.name.rfind("ap", 0) == 0) rank = 1;
        else if (candidate.name.rfind("eth", 0) == 0) rank = 2;
        if (rank == 3 || !valid_private_ipv4(candidate.address)) continue;
        if (rank < best_rank || (rank == best_rank && candidate.name < best_name)) {
            best_rank = rank;
            best_name = candidate.name;
            selected = candidate.address;
        }
    }
    return selected;
}

} // namespace flynes::harmony
