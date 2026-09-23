#include "../app/bridge/NearbyLanAddressSelector.hpp"

#include <cassert>
#include <iostream>
#include <vector>

int main() {
    using flynes::ios::NearbyLanCandidate;
    using flynes::ios::select_lan_ipv4;
    const std::vector<NearbyLanCandidate> mixed = {
        {"pdp_ip0", "10.0.0.2", true, false},
        {"en0", "192.168.1.4", true, false},
        {"bridge101", "172.20.11.1", true, false},
        {"utun0", "10.8.0.1", true, false},
        {"bridge100", "172.20.10.1", true, false},
    };
    assert(select_lan_ipv4(mixed) == "172.20.10.1");
    assert(select_lan_ipv4(mixed, true) == "192.168.1.4");
    const std::vector<NearbyLanCandidate> unavailable = {
        {"pdp_ip0", "10.0.0.2", true, false},
        {"utun0", "10.8.0.1", true, false},
        {"bridge100", "169.254.1.1", true, false},
        {"en0", "192.168.1.4", false, false},
    };
    assert(!select_lan_ipv4(unavailable).has_value());
    assert(!select_lan_ipv4(unavailable, true).has_value());
    std::cout << "NearbyLanAddressSelectorTests passed\n";
}
