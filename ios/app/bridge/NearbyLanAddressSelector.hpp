#pragma once

#include <optional>
#include <array>
#include <cstdint>
#include <string>
#include <tuple>
#include <vector>

namespace flynes::ios {

struct NearbyLanCandidate {
    std::string name;
    std::string address;
    bool up;
    bool loopback;
};

namespace detail {
inline int interface_rank(const std::string& name, bool wifi_only) {
    if (name == "en0") return wifi_only ? 0 : 2;
    if (wifi_only || name.size() <= 6 || name.compare(0, 6, "bridge") != 0) return -1;
    for (std::size_t i = 6; i < name.size(); ++i) {
        if (name[i] < '0' || name[i] > '9') return -1;
    }
    return name == "bridge100" ? 0 : 1;
}

inline bool parse_ipv4(const std::string& text, std::array<std::uint8_t, 4>* out) {
    std::array<std::uint8_t, 4> octets{};
    std::size_t start = 0;
    for (std::size_t i = 0; i < octets.size(); ++i) {
        const auto end = text.find('.', start);
        if ((i < 3 && end == std::string::npos) ||
            (i == 3 && end != std::string::npos)) return false;
        const auto size = (end == std::string::npos ? text.size() : end) - start;
        if (size == 0 || size > 3 || (size > 1 && text[start] == '0')) return false;
        unsigned value = 0;
        for (std::size_t j = 0; j < size; ++j) {
            const char digit = text[start + j];
            if (digit < '0' || digit > '9') return false;
            value = value * 10u + static_cast<unsigned>(digit - '0');
        }
        if (value > 255) return false;
        octets[i] = static_cast<std::uint8_t>(value);
        start = end + 1;
    }
    if (octets[0] == 0 || octets[0] == 127 || octets[0] >= 224 ||
        (octets[0] == 169 && octets[1] == 254) ||
        octets[3] == 0 || octets[3] == 255) return false;
    *out = octets;
    return true;
}
} // namespace detail

inline std::optional<std::string> select_lan_ipv4(
    const std::vector<NearbyLanCandidate>& candidates, bool wifi_only = false) {
    std::optional<std::tuple<int, std::string, std::array<std::uint8_t, 4>>> best;
    std::optional<std::string> selected;
    for (const auto& candidate : candidates) {
        if (!candidate.up || candidate.loopback) continue;
        const int rank = detail::interface_rank(candidate.name, wifi_only);
        std::array<std::uint8_t, 4> address{};
        if (rank < 0 || !detail::parse_ipv4(candidate.address, &address)) continue;
        const auto key = std::make_tuple(rank, candidate.name, address);
        if (!best || key < *best) {
            best = key;
            selected = candidate.address;
        }
    }
    return selected;
}

} // namespace flynes::ios
