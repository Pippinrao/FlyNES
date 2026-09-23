#include "../entry/src/main/cpp/nearby_lan_interface_selector.hpp"

#include <cassert>
#include <vector>

int main()
{
    using flynes::harmony::NearbyLanInterface;
    const std::vector<NearbyLanInterface> mixed = {
        {"eth0", "192.168.2.2"},
        {"ap0", "192.168.43.1"},
        {"wlan0", "192.168.43.2"},
    };
    assert(flynes::harmony::select_guest_ipv4(mixed) == "192.168.43.2");
    assert(flynes::harmony::select_guest_ipv4({{"eth0", "192.168.2.2"}}) == "192.168.2.2");
    assert(flynes::harmony::select_guest_ipv4({{"wlan0", "127.0.0.1"}}).empty());
}
