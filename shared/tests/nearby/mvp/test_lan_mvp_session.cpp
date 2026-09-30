#include "flynes/flynes_nearby_mvp.h"
#include "flynes/flynes_runtime.h"

#include <array>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <fstream>
#include <filesystem>
#include <iterator>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#endif

namespace {
int failures = 0;
void check(bool good, const char* label) {
    if (!good) { std::cerr << "FAIL: " << label << '\n'; ++failures; }
}

// The diagnostic callback runs on the real session worker. Never call a session
// API from it, and detach it before this collector leaves scope.
struct AppliedInputTrace {
    std::mutex mutex;
    std::vector<std::string> lines;
    std::vector<std::string> rejections;

    static void capture(void* context, const char* line) {
        auto& self = *static_cast<AppliedInputTrace*>(context);
        std::lock_guard<std::mutex> lock(self.mutex);
        if (std::strstr(line, "event=input_apply") != nullptr) self.lines.emplace_back(line);
        if (std::strstr(line, "event=input_rejected") != nullptr) self.rejections.emplace_back(line);
    }

    bool pressed_then_released(bool p2) {
        std::lock_guard<std::mutex> lock(mutex);
        const std::string key = p2 ? " p2=" : " p1=";
        bool pressed = false;
        for (const auto& line : lines) {
            const auto at = line.find(key);
            if (at == std::string::npos) continue;
            const auto buttons = std::stoul(line.substr(at + key.size()));
            if (buttons == 8) pressed = true;
            if (pressed && buttons == 0) return true;
        }
        return false;
    }

    bool contains_press(bool p2) {
        std::lock_guard<std::mutex> lock(mutex);
        const std::string key = p2 ? " p2=" : " p1=";
        for (const auto& line : lines) {
            const auto at = line.find(key);
            if (at != std::string::npos &&
                std::stoul(line.substr(at + key.size())) == 8) return true;
        }
        return false;
    }

    std::vector<std::uint32_t> states(bool p2) {
        std::lock_guard<std::mutex> lock(mutex);
        std::vector<std::uint32_t> result;
        const std::string key = p2 ? " p2=" : " p1=";
        for (const auto& line : lines) {
            const auto at = line.find(key);
            if (at != std::string::npos)
                result.push_back(static_cast<std::uint32_t>(std::stoul(line.substr(at + key.size()))));
        }
        return result;
    }

    void print(const char* label) {
        std::lock_guard<std::mutex> lock(mutex);
        std::cout << label << " input_apply events=" << lines.size() << '\n';
        for (const auto& line : lines) std::cout << line << '\n';
        for (const auto& line : rejections) std::cout << line << '\n';
    }

    bool rejected_at_capacity() {
        std::lock_guard<std::mutex> lock(mutex);
        return rejections.size() == 2 &&
            rejections[0].find("reason=state_queue_full buttons=16 queued=15") != std::string::npos &&
            rejections[1].find("reason=state_queue_full buttons=17 queued=16") != std::string::npos;
    }
};

std::string local_ipv4() {
    const char* specified = std::getenv("FLYNES_TEST_LAN_IPV4");
    if (specified != nullptr && *specified != '\0') return specified;
#ifdef _WIN32
    WSADATA winsock{};
    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0) return {};
#endif
    char hostname[256]{};
    if (gethostname(hostname, sizeof(hostname)) != 0) return {};
    addrinfo hints{};
    hints.ai_family = AF_INET;
    addrinfo* addresses = nullptr;
    if (getaddrinfo(hostname, nullptr, &hints, &addresses) != 0) return {};
    std::string chosen;
    for (auto* item = addresses; item != nullptr; item = item->ai_next) {
        const auto* address = reinterpret_cast<const sockaddr_in*>(item->ai_addr);
        const auto* bytes = reinterpret_cast<const uint8_t*>(&address->sin_addr);
        if (bytes[0] != 10 && bytes[0] != 192 &&
            !(bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31)) continue;
        char text[INET_ADDRSTRLEN]{};
        if (inet_ntop(AF_INET, &address->sin_addr, text, sizeof(text)) != nullptr) {
            chosen = text;
            break;
        }
    }
    freeaddrinfo(addresses);
    return chosen;
}

bool wait_state(fly_lan_mvp_session* session, uint32_t target, int milliseconds) {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(milliseconds);
    fly_lan_mvp_snapshot last{};
    do {
        fly_lan_mvp_snapshot snapshot{};
        if (!fly_lan_mvp_snapshot_read(session, &snapshot)) return false;
        last = snapshot;
        if (snapshot.state == target) return true;
        if (snapshot.state == FLY_LAN_MVP_ENDED) {
            if (target != FLY_LAN_MVP_ENDED)
                std::cerr << "ended before target=" << target
                          << " reason=" << snapshot.reason << '\n';
            return target == FLY_LAN_MVP_ENDED;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now() < deadline);
    std::cerr << "wait_state target=" << target << " actual=" << last.state
              << " reason=" << last.reason << '\n';
    return false;
}

bool wait_pair(fly_lan_mvp_session* host, fly_lan_mvp_session* guest,
               int milliseconds) {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(milliseconds);
    fly_lan_mvp_snapshot a{}, b{};
    do {
        (void)fly_lan_mvp_snapshot_read(host, &a);
        (void)fly_lan_mvp_snapshot_read(guest, &b);
        if (a.state == FLY_LAN_MVP_LOBBY && b.state == FLY_LAN_MVP_LOBBY)
            return true;
        if (a.state == FLY_LAN_MVP_ENDED || b.state == FLY_LAN_MVP_ENDED) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now() < deadline);
    std::cerr << "pair states host=" << a.state << '/' << a.reason
              << " guest=" << b.state << '/' << b.reason << '\n';
    return false;
}

bool wait_running(fly_lan_mvp_session* host, fly_lan_mvp_session* guest,
                  int milliseconds) {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(milliseconds);
    do {
        fly_lan_mvp_snapshot a{}, b{};
        (void)fly_lan_mvp_snapshot_read(host, &a);
        (void)fly_lan_mvp_snapshot_read(guest, &b);
        if (a.state == FLY_LAN_MVP_RUNNING && b.state == FLY_LAN_MVP_RUNNING) return true;
        if (a.state == FLY_LAN_MVP_ENDED || b.state == FLY_LAN_MVP_ENDED) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now() < deadline);
    return false;
}

bool wait_completed(fly_lan_mvp_session* host, fly_lan_mvp_session* guest,
                    std::uint64_t count, int milliseconds) {
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(milliseconds);
    do {
        fly_lan_mvp_snapshot a{}, b{};
        (void)fly_lan_mvp_snapshot_read(host, &a);
        (void)fly_lan_mvp_snapshot_read(guest, &b);
        if (a.completed_frames >= count && b.completed_frames >= count) return true;
        if (a.state == FLY_LAN_MVP_ENDED || b.state == FLY_LAN_MVP_ENDED) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    } while (std::chrono::steady_clock::now() < deadline);
    return false;
}

std::vector<std::uint8_t> read_rom(const char* path) {
    std::ifstream input(path, std::ios::binary);
    return std::vector<std::uint8_t>(std::istreambuf_iterator<char>(input),
                                     std::istreambuf_iterator<char>());
}

std::vector<std::vector<std::uint8_t>> read_distinct_roms() {
    std::vector<std::vector<std::uint8_t>> result;
    for (const auto& item : std::filesystem::directory_iterator(FLYNES_CONTENT_ROM_DIR)) {
        if (!item.is_regular_file() || item.path().extension() != ".nes") continue;
        auto bytes = read_rom(item.path().string().c_str());
        if (!bytes.empty()) result.push_back(std::move(bytes));
        if (result.size() == 2) break;
    }
    return result;
}

std::string wait_invite(fly_lan_mvp_session* host) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    do {
        fly_lan_mvp_snapshot snapshot{};
        (void)fly_lan_mvp_snapshot_read(host, &snapshot);
        const auto needed = fly_lan_mvp_copy_invite(host, nullptr, 0);
        if (needed != 0) {
            std::string qr(needed, '\0');
            check(fly_lan_mvp_copy_invite(host, qr.data(), qr.size()) == needed,
                  "QR copied as one exact value");
            qr.resize(needed - 1);
            return qr;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now() < deadline);
    return {};
}

bool wait_host_rejected(fly_lan_mvp_session* host, fly_lan_mvp_session* guest) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    do {
        fly_lan_mvp_snapshot a{}, b{};
        (void)fly_lan_mvp_snapshot_read(host, &a);
        (void)fly_lan_mvp_snapshot_read(guest, &b);
        if (a.state == FLY_LAN_MVP_ENDED) return a.reason == FLY_LAN_MVP_REASON_REJECTED;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while (std::chrono::steady_clock::now() < deadline);
    return false;
}
}

int main(int argc, char** argv) {
    if (argc == 3) {
        std::ifstream input(argv[2], std::ios::binary);
        const std::string qr((std::istreambuf_iterator<char>(input)),
                             std::istreambuf_iterator<char>());
        auto* guest = fly_lan_mvp_create();
        if (!guest || qr.empty() ||
            fly_lan_mvp_join(guest, argv[1], qr.data(), qr.size()) != 1) {
            if (guest) fly_lan_mvp_destroy(guest);
            std::cerr << "PROBE start failed\n";
            return 2;
        }
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(12);
        fly_lan_mvp_snapshot snapshot{};
        do {
            (void)fly_lan_mvp_snapshot_read(guest, &snapshot);
            if (snapshot.state == FLY_LAN_MVP_LOBBY ||
                snapshot.state == FLY_LAN_MVP_ENDED) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        } while (std::chrono::steady_clock::now() < deadline);
        std::cout << "PROBE state=" << snapshot.state << " reason=" << snapshot.reason
                  << " transportResult=" << snapshot.transport_result
                  << " transportOperation=" << snapshot.transport_operation << '\n';
        const bool connected = snapshot.state == FLY_LAN_MVP_LOBBY;
        fly_lan_mvp_destroy(guest);
        return connected ? 0 : 3;
    }
    const std::string mode = argc == 2 ? argv[1] : "";
    const std::string ip = local_ipv4();
    if (ip.empty()) {
        std::cerr << "SKIP: no private IPv4 interface for real-network P1 test\n";
        return 77;
    }
    const std::array<uint8_t, 16> token{{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16}};
    auto* host = fly_lan_mvp_create();
    auto* guest = fly_lan_mvp_create();
    check(host != nullptr && guest != nullptr, "session owners created");
    if (!host || !guest) return 1;
    std::string diagnostics;
    const auto capture = [](void* context, const char* line) {
        *static_cast<std::string*>(context) += std::string(line) + '\n';
    };
    fly_lan_mvp_set_diagnostic_sink(host, capture, &diagnostics);
    check(fly_lan_mvp_host(host, ip.c_str(), token.data()) == 1, "host begins listening");
    std::string qr = wait_invite(host);
    // Detachment takes the session mutex: the writer has completed before the
    // assertions read this setup-only string, and it cannot outlive the string.
    fly_lan_mvp_set_diagnostic_sink(host, nullptr, nullptr);
    check(!qr.empty(), "reachable host publishes QR after real bind");
    check(diagnostics.find("event=listen_ready") != std::string::npos,
          "diagnostics identify real bound listener");
    check(diagnostics.find("event=submit") != std::string::npos,
          "diagnostics identify submitted transport operation");
    check(diagnostics.find("0102030405060708090a0b0c0d0e0f10") == std::string::npos &&
          diagnostics.find("flynes-lan-v1:") == std::string::npos,
          "diagnostics do not expose token or full invitation");
    if (!qr.empty()) {
        if (mode == "--expires") {
            check(wait_state(host, FLY_LAN_MVP_ENDED, 125000),
                  "invitation reaches its advertised expiry");
            fly_lan_mvp_snapshot expired{};
            (void)fly_lan_mvp_snapshot_read(host, &expired);
            check(expired.reason == FLY_LAN_MVP_REASON_EXPIRED,
                  "expired invitation reports EXPIRED");
            check(fly_lan_mvp_copy_invite(host, nullptr, 0) == 0,
                  "expired invitation is no longer published");
            check(fly_lan_mvp_join(guest, ip.c_str(), qr.data(), qr.size()) == 1,
                  "old invitation can be submitted for fail-closed verification");
            check(wait_state(guest, FLY_LAN_MVP_ENDED, 12000),
                  "old invitation cannot establish a lobby after expiry");
            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            if (failures) return 1;
            std::cout << "PASS lan MVP invitation expiry\n";
            return 0;
        }
        if (mode == "--delayed-join") {
            const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(32);
            while (std::chrono::steady_clock::now() < until) {
                fly_lan_mvp_snapshot waiting{};
                (void)fly_lan_mvp_snapshot_read(host, &waiting);
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
            fly_lan_mvp_snapshot waiting{};
            (void)fly_lan_mvp_snapshot_read(host, &waiting);
            check(waiting.state == FLY_LAN_MVP_INVITING,
                  "120-second invitation still accepts a guest after 32 seconds");
            check(wait_invite(host) == qr, "waiting does not replace or discard the invitation");
        }
        check(fly_lan_mvp_join(guest, ip.c_str(), qr.data(), qr.size()) == 1,
              "guest starts QUIC with QR pin");
        check(wait_pair(host, guest, 10000), "encrypted JOIN and ACCEPT reach one lobby");
        fly_lan_mvp_snapshot a{}, b{};
        (void)fly_lan_mvp_snapshot_read(host, &a);
        (void)fly_lan_mvp_snapshot_read(guest, &b);
        check(std::memcmp(a.session_id, b.session_id, 16) == 0,
              "both peers share one session id");
        if (mode == "--short-tap-p1" || mode == "--short-tap-p2" ||
            mode == "--short-tap-pause-p1" || mode == "--short-tap-pause-p2" ||
            mode == "--short-tap-pause-remote-p1" || mode == "--short-tap-pause-remote-p2" ||
            mode == "--short-tap-switch-p1" || mode == "--short-tap-switch-p2" ||
            mode == "--input-capacity-p1" || mode == "--input-capacity-p2") {
            const bool p2 = mode.find("p2") != std::string::npos;
            const bool pause_boundary = mode.find("pause") != std::string::npos;
            const bool switch_boundary = mode.find("switch") != std::string::npos;
            const bool capacity = mode.find("capacity") != std::string::npos;
            auto* sender = p2 ? guest : host;
            auto* peer = p2 ? host : guest;
            AppliedInputTrace sender_trace, peer_trace;
            fly_lan_mvp_set_diagnostic_sink(sender, AppliedInputTrace::capture, &sender_trace);
            fly_lan_mvp_set_diagnostic_sink(peer, AppliedInputTrace::capture, &peer_trace);
            const auto roms = read_distinct_roms();
            check(roms.size() == 2, "short tap uses two readable real ROMs");
            const auto start_round = [&](const std::vector<std::uint8_t>& rom) {
                check(fly_lan_mvp_select_rom(host, rom.data(), rom.size()) == 1,
                      "short tap host loads real ROM");
                check(fly_lan_mvp_select_rom(guest, rom.data(), rom.size()) == 1,
                      "short tap guest loads matching real ROM");
                check(fly_lan_mvp_confirm(host) == 1 && fly_lan_mvp_confirm(guest) == 1,
                      "short tap round confirmed by both owners");
                check(wait_running(host, guest, 5000), "short tap round runs");
            };
            if (roms.size() == 2) {
                start_round(roms[0]);
                check(fly_lan_mvp_submit_input(sender, 0) == 1,
                      "only sender supplies initial idle state");
                const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(1);
                do {
                    (void)fly_lan_mvp_snapshot_read(sender, &a);
                    if (a.completed_frames >= 10) break;
                    std::this_thread::sleep_for(std::chrono::milliseconds(2));
                } while (std::chrono::steady_clock::now() < deadline);
                (void)fly_lan_mvp_snapshot_read(peer, &b);
                check(a.completed_frames == 10 && b.completed_frames == 0,
                      "real prediction window blocks sender at ten frames before peer submits");
                const auto blocked_frame = a.completed_frames;
                if (capacity) {
                    fly_lan_mvp_input_v1 input{};
                    input.struct_size = FLY_LAN_MVP_INPUT_V1_SIZE;
                    input.version = FLY_LAN_MVP_INPUT_VERSION_1;
                    input.capture_time_ns = 543210;
                    for (std::uint32_t buttons = 1; buttons <= 15; ++buttons) {
                        input.buttons = buttons;
                        input.sequence = buttons * 100;
                        check(fly_lan_mvp_submit_input_v1(sender, &input) == 1,
                              "fifteen distinct full states fit before the reserved all-up slot");
                        for (unsigned repeat = 0; repeat < 32; ++repeat) {
                            ++input.sequence;
                            check(fly_lan_mvp_submit_input_v1(sender, &input) == 1,
                                  "duplicate held samples do not occupy transition capacity");
                        }
                    }
                    input.buttons = 16;
                    input.sequence = 9999;
                    check(fly_lan_mvp_submit_input_v1(sender, &input) == 0,
                          "full nonzero transition capacity rejects without consuming all-up slot");
                    input.buttons = 0;
                    input.sequence = 10000;
                    check(fly_lan_mvp_submit_input_v1(sender, &input) == 1,
                          "final all-up is accepted in reserved sixteenth slot");
                    input.buttons = 17;
                    input.sequence = 10001;
                    input.capture_time_ns = 999999;
                    check(fly_lan_mvp_submit_input_v1(sender, &input) == 0,
                          "full queue rejects a new press without changing accepted release metadata");
                } else {
                    check(fly_lan_mvp_submit_input(sender, 8) == 1,
                          "START press is accepted while sampling is blocked");
                    std::this_thread::sleep_for(std::chrono::milliseconds(150));
                    check(fly_lan_mvp_submit_input(sender, 0) == 1,
                          "START release is accepted before next sample");
                }
                (void)fly_lan_mvp_snapshot_read(sender, &a);
                check(a.completed_frames == blocked_frame,
                      "press and release both precede the next sampled core frame");
                std::cout << mode << " queued states while blocked; frames="
                          << blocked_frame << " -> " << a.completed_frames << '\n';
                if (pause_boundary) {
                    auto* pauser = mode.find("remote") == std::string::npos ? sender : peer;
                    check(fly_lan_mvp_set_paused(pauser, 1) == 1,
                          "pause accepted with an unconsumed short tap");
                    const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(1);
                    do {
                        (void)fly_lan_mvp_snapshot_read(sender, &a);
                        (void)fly_lan_mvp_snapshot_read(peer, &b);
                        if (a.paused && b.paused) break;
                        std::this_thread::sleep_for(std::chrono::milliseconds(2));
                    } while (std::chrono::steady_clock::now() < until);
                    check(a.paused && b.paused, "both owners observe the pause boundary");
                    check(fly_lan_mvp_submit_input(sender, 8) == 0,
                          "input while paused is rejected");
                    check(fly_lan_mvp_resume_game(sender) == 1,
                          "explicit continue resumes the original room");
                    const auto resumed = std::chrono::steady_clock::now() + std::chrono::seconds(1);
                    do {
                        (void)fly_lan_mvp_snapshot_read(sender, &a);
                        (void)fly_lan_mvp_snapshot_read(peer, &b);
                        if (!a.paused && !b.paused) break;
                        std::this_thread::sleep_for(std::chrono::milliseconds(2));
                    } while (std::chrono::steady_clock::now() < resumed);
                    check(!a.paused && !b.paused, "both owners acknowledge continue");
                }
                if (switch_boundary) {
                    const auto session_id = std::vector<std::uint8_t>(a.session_id, a.session_id + 16);
                    check(fly_lan_mvp_return_lobby(sender) == 1 && wait_pair(host, guest, 5000),
                          "pending-input game returns to original connected lobby");
                    start_round(roms[1]);
                    (void)fly_lan_mvp_snapshot_read(sender, &a);
                    check(std::equal(session_id.begin(), session_id.end(), a.session_id),
                          "replacement ROM uses the same real connection");
                }
                if (pause_boundary || switch_boundary)
                    check(fly_lan_mvp_submit_input(sender, 0) == 1,
                          "resumed or replacement game receives fresh idle input");
                check(fly_lan_mvp_submit_input(peer, 0) == 1,
                      "peer idle input releases the real prediction barrier");
                check(wait_completed(host, guest, 26, 1800),
                      "both real cores advance beyond the blocked frame");
                if (capacity) {
                    check(sender_trace.rejected_at_capacity(),
                          "capacity rejection reports both reserved and full queue boundaries");
                    std::vector<std::uint32_t> expected;
                    for (std::uint32_t buttons = 1; buttons <= 15; ++buttons) expected.push_back(buttons);
                    expected.push_back(0);
                    check(sender_trace.states(p2) == expected,
                          "sender core applies all accepted full states once in order, then final release");
                    const auto peer_states = peer_trace.states(p2);
                    std::size_t next = 0;
                    for (const auto buttons : peer_states)
                        if (next < expected.size() && buttons == expected[next]) ++next;
                    check(next == expected.size(),
                          "peer core receives every accepted full state in order through real transport");
                    std::vector<std::uint8_t> pixels(FLY_RUNTIME_RGB565_BYTES);
                    fly_latest_frame_v1 frame{};
                    frame.struct_size = FLY_LATEST_FRAME_V1_SIZE;
                    frame.version = FLY_LATEST_FRAME_VERSION_1;
                    check(fly_lan_mvp_copy_latest_frame(sender, pixels.data(), pixels.size(), &frame) == 1 &&
                          frame.applied_input_sequence[p2 ? 1 : 0] == 10000 && frame.source_time_ns == 543210,
                          "rejected input cannot replace the accepted final release sequence or capture time");
                } else if (pause_boundary || switch_boundary) {
                    check(!sender_trace.contains_press(p2) && !peer_trace.contains_press(p2),
                          "pause or replacement game never applies the prior pending START");
                } else {
                    check(sender_trace.pressed_then_released(p2),
                          "sender core applies accepted short START then a later zero release");
                    check(peer_trace.pressed_then_released(p2),
                          "peer core receives short START then a later zero release over real transport");
                }
            }
            fly_lan_mvp_set_diagnostic_sink(sender, nullptr, nullptr);
            fly_lan_mvp_set_diagnostic_sink(peer, nullptr, nullptr);
            sender_trace.print("sender");
            peer_trace.print("peer");
            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            return failures == 0 ? 0 : 1;
        }
        if (mode == "--invalid-rom") {
            const std::array<std::uint8_t, 8> invalid{{0, 1, 2, 3, 4, 5, 6, 7}};
            check(fly_lan_mvp_select_rom(guest, invalid.data(), invalid.size()) == 0,
                  "corrupt ROM is rejected");
            (void)fly_lan_mvp_snapshot_read(guest, &b);
            check(b.state != FLY_LAN_MVP_RUNNING &&
                  b.reason == FLY_LAN_MVP_REASON_ROM_INVALID,
                  "corrupt ROM reports ROM_INVALID without starting");
            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            return failures == 0 ? 0 : 1;
        }
        if (mode == "--rom-mismatch") {
            const auto roms = read_distinct_roms();
            check(roms.size() == 2, "two manifest content ROMs are readable");
            if (roms.size() == 2) {
                check(fly_lan_mvp_select_rom(host, roms[0].data(), roms[0].size()) == 1,
                      "host selects first valid ROM");
                const auto config_until = std::chrono::steady_clock::now() +
                                          std::chrono::seconds(2);
                do {
                    (void)fly_lan_mvp_snapshot_read(host, &a);
                    (void)fly_lan_mvp_snapshot_read(guest, &b);
                    if (b.peer_configured != 0) break;
                    std::this_thread::sleep_for(std::chrono::milliseconds(5));
                } while (std::chrono::steady_clock::now() < config_until);
                check(b.peer_configured != 0, "guest receives host configuration");
                check(fly_lan_mvp_select_rom(guest, roms[1].data(), roms[1].size()) == 0,
                      "different valid ROM cannot be confirmed");
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                check(b.state == FLY_LAN_MVP_CONFIGURING &&
                      b.reason == FLY_LAN_MVP_REASON_ROM_MISMATCH,
                      "different content reports ROM_MISMATCH without disconnecting");
                check(fly_lan_mvp_select_rom(guest, roms[0].data(), roms[0].size()) == 1,
                      "same connection can correct a mismatched local selection");
            }
            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            return failures == 0 ? 0 : 1;
        }
        if (mode == "--early-ready") {
            const auto rom = read_rom(FLYNES_RUNTIME_ROM_FIXTURE);
            check(!rom.empty(), "real ROM fixture is readable");
            check(fly_lan_mvp_select_rom(host, rom.data(), rom.size()) == 1,
                  "host publishes configuration before guest loads ROM");
            check(fly_lan_mvp_confirm(host) == 1,
                  "host may confirm before guest selects ROM");
            const auto ready_deadline = std::chrono::steady_clock::now() +
                std::chrono::seconds(5);
            do {
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                if (b.peer_ready) break;
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
            } while (std::chrono::steady_clock::now() < ready_deadline);
            check(b.peer_ready == 1, "guest observes host READY before local ROM selection");
            check(fly_lan_mvp_select_rom(guest, rom.data(), rom.size()) == 1,
                  "guest selects the matching ROM after host READY");
            (void)fly_lan_mvp_snapshot_read(guest, &b);
            check(b.peer_ready == 1,
                  "matching local selection preserves the already received host READY");
            check(fly_lan_mvp_confirm(guest) == 1, "guest confirms matching ROM");
            check(wait_running(host, guest, 5000),
                  "early host READY still starts both runtimes");
            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            return failures == 0 ? 0 : 1;
        }
        if (mode == "--input-timestamp") {
            const auto rom = read_rom(FLYNES_RUNTIME_ROM_FIXTURE);
            check(fly_lan_mvp_select_rom(host, rom.data(), rom.size()) == 1,
                  "host loads ROM for timestamped input");
            check(fly_lan_mvp_select_rom(guest, rom.data(), rom.size()) == 1,
                  "guest loads matching ROM for timestamped input");
            check(fly_lan_mvp_confirm(host) == 1 && fly_lan_mvp_confirm(guest) == 1,
                  "both devices confirm timestamped round");
            check(wait_running(host, guest, 5000), "timestamped round starts");
            fly_lan_mvp_input_v1 input{};
            input.struct_size = FLY_LAN_MVP_INPUT_V1_SIZE;
            input.version = FLY_LAN_MVP_INPUT_VERSION_1;
            input.buttons = 1;
            input.sequence = 42;
            input.capture_time_ns = 123456789;
            check(fly_lan_mvp_submit_input_v1(host, &input) == 1,
                  "host submits a versioned captured button state");
            const auto frame_deadline = std::chrono::steady_clock::now() +
                std::chrono::seconds(2);
            do {
                (void)fly_lan_mvp_snapshot_read(host, &a);
                if (a.completed_frames > 0) break;
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
            } while (std::chrono::steady_clock::now() < frame_deadline);
            std::vector<std::uint8_t> pixels(FLY_RUNTIME_RGB565_BYTES);
            fly_latest_frame_v1 frame{};
            frame.struct_size = FLY_LATEST_FRAME_V1_SIZE;
            frame.version = FLY_LATEST_FRAME_VERSION_1;
            check(fly_lan_mvp_copy_latest_frame(host, pixels.data(), pixels.size(), &frame) == 1,
                  "timestamped frame is published");
            check(frame.source_time_ns == input.capture_time_ns &&
                  frame.applied_input_sequence[0] == input.sequence,
                  "published frame preserves input capture time and sequence");
            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            return failures == 0 ? 0 : 1;
        }
        if (mode == "--prediction" || mode == "--ready" || mode == "--stall") {
            const auto rom = read_rom(FLYNES_RUNTIME_ROM_FIXTURE);
            check(!rom.empty(), "real ROM fixture is readable");
            check(fly_lan_mvp_select_rom(host, rom.data(), rom.size()) == 1,
                  "host selects configuration");
            check(fly_lan_mvp_select_rom(guest, rom.data(), rom.size()) == 1,
                  "guest selects matching configuration");
            fly_runtime_source_timing_v1 source_timing{};
            source_timing.struct_size = FLY_RUNTIME_SOURCE_TIMING_V1_SIZE;
            source_timing.version = FLY_RUNTIME_SOURCE_TIMING_VERSION_1;
            check(fly_lan_mvp_source_timing(host, &source_timing) == 1 &&
                  source_timing.frame_rate_numerator > 0 &&
                  source_timing.frame_rate_denominator > 0,
                  "LAN presents the loaded source cadence without stepping");
            check(fly_lan_mvp_confirm(host) == 1, "first host confirmation is accepted");
            check(fly_lan_mvp_confirm(host) == 1, "duplicate host confirmation is idempotent");
            const auto one_ready_until = std::chrono::steady_clock::now() +
                                         std::chrono::milliseconds(250);
            while (std::chrono::steady_clock::now() < one_ready_until) {
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
            check(a.state != FLY_LAN_MVP_RUNNING && b.state != FLY_LAN_MVP_RUNNING,
                  "one confirmation cannot start either runtime");
            if (mode == "--ready") {
                check(fly_lan_mvp_select_rom(host, rom.data(), rom.size()) == 1,
                      "reselecting configuration invalidates local READY");
                (void)fly_lan_mvp_snapshot_read(host, &a);
                check(a.local_ready == 0, "reselection clears the prior confirmation");
                check(fly_lan_mvp_confirm(host) == 1,
                      "host reconfirms after reselection");
            }
            check(fly_lan_mvp_confirm(guest) == 1, "guest confirmation is accepted");
            check(wait_running(host, guest, 5000), "both confirmations start exactly one round");
            if (mode == "--prediction") {
                for (int frame = 0; frame < 4; ++frame) {
                    check(fly_lan_mvp_submit_input(host, frame == 0 ? 1u : 0u) == 1,
                          "local input is accepted without peer input");
                    std::this_thread::sleep_for(std::chrono::milliseconds(17));
                }
                fly_lan_mvp_snapshot ahead{};
                const auto ahead_until = std::chrono::steady_clock::now() +
                                         std::chrono::milliseconds(500);
                do {
                    (void)fly_lan_mvp_snapshot_read(host, &ahead);
                    if (ahead.completed_frames >= 4) break;
                    std::this_thread::sleep_for(std::chrono::milliseconds(2));
                } while (std::chrono::steady_clock::now() < ahead_until);
                check(ahead.completed_frames >= 4 && ahead.completed_frames <= 10,
                      "local frames advance at source cadence while remote input is late");
                std::vector<std::uint8_t> pixels(FLY_RUNTIME_RGB565_BYTES);
                fly_latest_frame_v1 before_replay{};
                before_replay.struct_size = FLY_LATEST_FRAME_V1_SIZE;
                before_replay.version = FLY_LATEST_FRAME_VERSION_1;
                check(fly_lan_mvp_copy_latest_frame(host, pixels.data(), pixels.size(),
                                                    &before_replay) == 1,
                      "predicted picture is published");
                std::array<std::int16_t, 256> heard{};
                fly_pcm_block_v1 heard_block{};
                heard_block.struct_size = FLY_PCM_BLOCK_V1_SIZE;
                heard_block.version = FLY_PCM_BLOCK_VERSION_1;
                check(fly_lan_mvp_pull_pcm(host, heard.data(),
                                          static_cast<std::uint32_t>(heard.size()), &heard_block) == 1 &&
                      heard_block.sample_count == heard.size(),
                      "predicted PCM is available without peer confirmation");
                check(fly_lan_mvp_submit_input(guest, 0x80u) == 1,
                      "late differing peer input is accepted");
                const auto corrected_until = std::chrono::steady_clock::now() +
                                             std::chrono::milliseconds(600);
                fly_latest_frame_v1 after_replay = before_replay;
                while (std::chrono::steady_clock::now() < corrected_until &&
                       after_replay.frame_sequence == before_replay.frame_sequence) {
                    (void)fly_lan_mvp_copy_latest_frame(host, pixels.data(), pixels.size(),
                                                        &after_replay);
                    std::this_thread::sleep_for(std::chrono::milliseconds(2));
                }
                check(after_replay.frame_index >= before_replay.frame_index &&
                      after_replay.frame_sequence > before_replay.frame_sequence,
                      "rollback or later source frame publishes a monotonic external sequence");
                fly_pcm_block_v1 next_block = heard_block;
                const bool next_pcm = fly_lan_mvp_pull_pcm(host, heard.data(),
                                          static_cast<std::uint32_t>(heard.size()), &next_block) == 1;
                fly_lan_mvp_stats_v1 stats{};
                stats.struct_size = FLY_LAN_MVP_STATS_V1_SIZE;
                stats.version = FLY_LAN_MVP_STATS_VERSION_1;
                check(fly_lan_mvp_stats_read(host, &stats) == 1,
                      "versioned statistics are readable");
                check(next_pcm && next_block.first_sample_sequence ==
                      heard_block.sample_count + stats.pcm_dropped_samples,
                      "rollback keeps delivered PCM and reports any bounded-queue drop");
                check(fly_lan_mvp_stats_read(host, &stats) == 1 &&
                      stats.simulated_frames >= 4 && stats.predicted_frames >= 4 &&
                      stats.rollback_count >= 1 && stats.replayed_frames >= 4 &&
                      stats.published_frames >= 5 &&
                      stats.pcm_delivered_samples >= heard_block.sample_count,
                      "versioned statistics separate real frames, replay, video and PCM");
                for (int burst = 0; burst < 10; ++burst)
                    check(fly_lan_mvp_submit_input(host, 0) == 1,
                          "high-frequency input sampling remains accepted");
                check(fly_lan_mvp_submit_input(host, 8) == 1,
                      "a fresh button overrides sampled idle input without a ten-frame queue");
                fly_lan_mvp_destroy(guest);
                fly_lan_mvp_destroy(host);
                return failures == 0 ? 0 : 1;
            }
            check(fly_lan_mvp_confirm(host) == 0 && fly_lan_mvp_confirm(guest) == 0,
                  "late confirmation cannot restart a running round");
            if (mode == "--stall") {
                check(fly_lan_mvp_submit_input(host, 0) == 1,
                      "host begins producing frames while the guest stops supplying input");
                const auto started_until = std::chrono::steady_clock::now() +
                                           std::chrono::milliseconds(1000);
                do {
                    (void)fly_lan_mvp_snapshot_read(host, &a);
                    if (a.completed_frames > 0) break;
                    std::this_thread::sleep_for(std::chrono::milliseconds(5));
                } while (std::chrono::steady_clock::now() < started_until);
                check(a.completed_frames > 0,
                      "host advances locally before the prediction window fills");
                std::this_thread::sleep_for(std::chrono::milliseconds(2100));
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                check(a.state == FLY_LAN_MVP_ENDED && b.state == FLY_LAN_MVP_ENDED,
                      "missing required input ends both runtimes");
                check(b.reason == FLY_LAN_MVP_REASON_STALL &&
                      (a.reason == FLY_LAN_MVP_REASON_STALL ||
                       a.reason == FLY_LAN_MVP_REASON_CONNECTION ||
                       a.reason == FLY_LAN_MVP_REASON_PEER_ENDED),
                      "two-second progress timeout ends the stalled peer and its connection");
            }
            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            return failures == 0 ? 0 : 1;
        }
        if (mode == "--play") {
            const auto rom = read_rom(FLYNES_RUNTIME_ROM_FIXTURE);
            check(!rom.empty(), "real ROM fixture is readable");
            check(fly_lan_mvp_select_rom(host, rom.data(), rom.size()) == 1,
                  "host loads a fresh real ROM");
            check(fly_lan_mvp_select_rom(guest, rom.data(), rom.size()) == 1,
                  "guest loads the same real ROM");
            check(fly_lan_mvp_confirm(host) == 1, "host confirms configuration");
            const auto one_ready_until = std::chrono::steady_clock::now() +
                                         std::chrono::milliseconds(300);
            while (std::chrono::steady_clock::now() < one_ready_until) {
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
            check(a.state != FLY_LAN_MVP_RUNNING && b.state != FLY_LAN_MVP_RUNNING,
                  "one confirmation cannot start the game");
            check(fly_lan_mvp_confirm(guest) == 1, "guest confirms configuration");
            check(wait_running(host, guest, 5000), "both confirmations start one round");
            (void)fly_lan_mvp_snapshot_read(host, &a);
            const auto before = a.completed_frames;
            check(fly_lan_mvp_submit_input(host, 0x01u) == 1,
                  "P1 submits its next distinct input");
            const auto one_input_until = std::chrono::steady_clock::now() +
                                         std::chrono::milliseconds(200);
            while (std::chrono::steady_clock::now() < one_input_until) {
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
            check(a.completed_frames > before && b.completed_frames == before,
                  "local frame advances without waiting for remote input");
            check(fly_lan_mvp_submit_input(guest, 0x80u) == 1,
                  "P2 submits a different input");
            check(wait_completed(host, guest, before + 1, 2000),
                   "late remote input corrects the predicted frame");
            (void)fly_lan_mvp_snapshot_read(host, &a);
            (void)fly_lan_mvp_snapshot_read(guest, &b);
            check(a.applied_buttons[0] == 0x01u && a.applied_buttons[1] == 0x80u &&
                  b.applied_buttons[0] == 0x01u && b.applied_buttons[1] == 0x80u,
                  "completed core frame reports both seats, including remote input");

            for (std::uint32_t index = 0; index < 62; ++index) {
                check(fly_lan_mvp_submit_input(host, (index & 1u) == 0 ? 0x02u : 0u) == 1,
                      "P1 sequence is accepted");
                check(fly_lan_mvp_submit_input(guest, (index & 1u) == 0 ? 0x40u : 0u) == 1,
                      "P2 sequence is accepted");
                check(wait_completed(host, guest, before + 2 + index, 2000),
                      "lockstep frame completes on both peers");
            }
            (void)fly_lan_mvp_snapshot_read(host, &a);
            (void)fly_lan_mvp_snapshot_read(guest, &b);
            check(a.completed_frames > 60 && b.completed_frames > 60,
                  "both runtimes progress independently past the digest boundary");
            std::cout << "digest observation completed=" << a.completed_frames << '/' << b.completed_frames
                      << " digest_frame=" << a.last_digest_frame << '/' << b.last_digest_frame
                      << " state=" << a.state << '/' << b.state
                      << " reason=" << a.reason << '/' << b.reason << '\n';
            // completed_frames includes prediction. A digest is published only
            // after remote confirmation, so compare an actually shared boundary.
            const auto digest_until = std::chrono::steady_clock::now() + std::chrono::seconds(2);
            while ((a.last_digest_frame == 0 || a.last_digest_frame != b.last_digest_frame) &&
                   a.state == FLY_LAN_MVP_RUNNING && b.state == FLY_LAN_MVP_RUNNING &&
                   std::chrono::steady_clock::now() < digest_until) {
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
            }
            check(a.last_digest_frame != 0 && a.last_digest_frame == b.last_digest_frame &&
                  std::memcmp(a.last_state_digest, b.last_state_digest, 32) == 0,
                  "periodic real-core state digests match");

            std::vector<std::uint8_t> host_frame(FLY_RUNTIME_RGB565_BYTES);
            std::vector<std::uint8_t> guest_frame(FLY_RUNTIME_RGB565_BYTES);
            fly_latest_frame_v1 host_meta{};
            host_meta.struct_size = FLY_LATEST_FRAME_V1_SIZE;
            host_meta.version = FLY_LATEST_FRAME_VERSION_1;
            fly_latest_frame_v1 guest_meta = host_meta;
            check(fly_lan_mvp_copy_latest_frame(host, host_frame.data(), host_frame.size(),
                                               &host_meta) == 1,
                  "host exposes the real core frame");
            check(fly_lan_mvp_copy_latest_frame(guest, guest_frame.data(), guest_frame.size(),
                                               &guest_meta) == 1,
                  "guest exposes the real core frame");
            check(host_meta.frame_index > 0 && guest_meta.frame_index > 0,
                  "both peers publish real core frames during independent scheduling");

            std::map<std::uint64_t, std::vector<std::uint8_t>> host_pictures;
            std::map<std::uint64_t, std::vector<std::uint8_t>> guest_pictures;
            bool same_frame_pixels = false;
            for (int attempt = 0; attempt < 240 && !same_frame_pixels; ++attempt) {
                (void)fly_lan_mvp_submit_input(host, 0);
                (void)fly_lan_mvp_submit_input(guest, 0);
                if (fly_lan_mvp_copy_latest_frame(host, host_frame.data(), host_frame.size(),
                        &host_meta) == 1 && host_meta.frame_index >= 60)
                    host_pictures[host_meta.frame_index] = host_frame;
                if (fly_lan_mvp_copy_latest_frame(guest, guest_frame.data(), guest_frame.size(),
                        &guest_meta) == 1 && guest_meta.frame_index >= 60)
                    guest_pictures[guest_meta.frame_index] = guest_frame;
                const auto matched_host = guest_pictures.find(host_meta.frame_index);
                const auto matched_guest = host_pictures.find(guest_meta.frame_index);
                same_frame_pixels =
                    (matched_host != guest_pictures.end() &&
                     host_pictures[host_meta.frame_index] == matched_host->second) ||
                    (matched_guest != host_pictures.end() &&
                     matched_guest->second == guest_pictures[guest_meta.frame_index]);
                if (host_pictures.size() > 64) host_pictures.erase(host_pictures.begin());
                if (guest_pictures.size() > 64) guest_pictures.erase(guest_pictures.begin());
                std::this_thread::sleep_for(std::chrono::milliseconds(8));
            }
            check(same_frame_pixels,
                  "independent peers publish identical raw pixels for one shared core frame");

            std::array<std::int16_t, 2048> host_pcm{};
            std::array<std::int16_t, 2048> guest_pcm{};
            fly_pcm_block_v1 host_block{};
            host_block.struct_size = FLY_PCM_BLOCK_V1_SIZE;
            host_block.version = FLY_PCM_BLOCK_VERSION_1;
            fly_pcm_block_v1 guest_block = host_block;
            check(fly_lan_mvp_pull_pcm(host, host_pcm.data(),
                                      static_cast<std::uint32_t>(host_pcm.size()), &host_block) == 1,
                  "host PCM reaches the shared consumer API");
            check(fly_lan_mvp_pull_pcm(guest, guest_pcm.data(),
                                      static_cast<std::uint32_t>(guest_pcm.size()), &guest_block) == 1,
                  "guest PCM reaches the shared consumer API");
            check(host_block.sample_count > 0 && guest_block.sample_count > 0,
                  "both peers produce PCM samples");
            check(host_block.media_time_ns == host_block.first_sample_sequence * 1'000'000'000ull / 48000 &&
                  guest_block.media_time_ns == guest_block.first_sample_sequence * 1'000'000'000ull / 48000,
                  "both peers expose coherent source PCM sample timestamps");
            for (int drain = 0; drain < 128 && host_block.sample_count != 0; ++drain)
                (void)fly_lan_mvp_pull_pcm(host, host_pcm.data(),
                    static_cast<std::uint32_t>(host_pcm.size()), &host_block);
            check(host_block.first_sample_sequence >= 2048,
                  "PCM reads advance the source sequence without synthetic silence");

            std::uint32_t queued = 0;
            while (queued < 20 && fly_lan_mvp_submit_input(host, 0) == 1) ++queued;
            check(queued == 20 && fly_lan_mvp_submit_input(host, 0) == 1,
                  "rapid UI sampling replaces the current button state instead of queuing frames");

            const auto connected_id = std::vector<std::uint8_t>(a.session_id, a.session_id + 16);
            check(fly_lan_mvp_set_paused(host, 1) == 1, "host pauses the current game");
            (void)fly_lan_mvp_snapshot_read(host, &a);
            const auto paused_frame = a.completed_frames;
            const auto pause_until = std::chrono::steady_clock::now() + std::chrono::milliseconds(2200);
            while (std::chrono::steady_clock::now() < pause_until) {
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
            check(a.state == FLY_LAN_MVP_RUNNING && b.state == FLY_LAN_MVP_RUNNING &&
                  a.paused && b.paused && a.completed_frames == paused_frame,
                  "pause freezes the game without disconnecting or timing out");
            check(fly_lan_mvp_set_paused(guest, 1) == 1,
                  "guest can also hold an independent pause request");
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
            check(fly_lan_mvp_set_paused(host, 0) == 1, "host resumes the same game");
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
            (void)fly_lan_mvp_snapshot_read(host, &a);
            (void)fly_lan_mvp_snapshot_read(guest, &b);
            check(a.paused && b.paused,
                  "clearing the host pause cannot cancel an active guest pause");
            check(fly_lan_mvp_set_paused(guest, 0) == 1,
                  "guest clears the remaining pause request");
            const auto resume_until = std::chrono::steady_clock::now() + std::chrono::milliseconds(1000);
            do {
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                if (!a.paused && !b.paused) break;
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            } while (std::chrono::steady_clock::now() < resume_until);
            check(!a.paused && !b.paused, "both apps resume after both owners clear pause");
            check(fly_lan_mvp_set_paused(host, 1) == 1 &&
                  fly_lan_mvp_set_paused(guest, 1) == 1,
                  "both players can pause again in the same running game");
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
            check(fly_lan_mvp_set_paused(guest, 0) == 1,
                  "guest can release its pause while host remains paused");
            std::this_thread::sleep_for(std::chrono::milliseconds(80));
            (void)fly_lan_mvp_snapshot_read(host, &a);
            (void)fly_lan_mvp_snapshot_read(guest, &b);
            check(a.paused && b.paused,
                  "clearing the guest pause cannot cancel an active host pause");
            check(fly_lan_mvp_set_paused(host, 0) == 1,
                  "host clears the remaining pause request");
            for (auto* pauser : {host, guest}) {
                auto* resumer = pauser == host ? guest : host;
                check(fly_lan_mvp_set_paused(pauser, 1) == 1, "room return pauses current game");
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
                (void)fly_lan_mvp_snapshot_read(host, &a);
                const auto room_frame = a.completed_frames;
                check(fly_lan_mvp_resume_game(resumer) == 1, "either player explicitly resumes current game");
                std::this_thread::sleep_for(std::chrono::milliseconds(200));
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                check(!a.paused && !b.paused && a.completed_frames > room_frame,
                      "continue in opposite room releases peer pause and advances original progress");
                check(std::equal(connected_id.begin(), connected_id.end(), a.session_id),
                      "continue retains the same connected session");
            }
            check(fly_lan_mvp_set_paused(host, 1) && fly_lan_mvp_set_paused(guest, 1),
                  "both players can be in paused rooms");
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            check(fly_lan_mvp_resume_game(guest) == 1, "guest continues both paused rooms");
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            (void)fly_lan_mvp_snapshot_read(host, &a);
            (void)fly_lan_mvp_snapshot_read(guest, &b);
            check(!a.paused && !b.paused, "one continue action clears both room pauses");
            check(fly_lan_mvp_return_lobby(guest) == 1, "either player can return both apps to lobby");
            check(wait_pair(host, guest, 3000), "return lobby drains old inputs on the same connection");
            (void)fly_lan_mvp_snapshot_read(host, &a);
            check(std::equal(connected_id.begin(), connected_id.end(), a.session_id),
                  "returning to lobby keeps the connected session identity");
            auto other_roms = read_distinct_roms();
            for (const auto& next_rom : other_roms) {
                if (next_rom == rom) continue;
                check(fly_lan_mvp_select_rom(host, next_rom.data(), next_rom.size()) == 1 &&
                      fly_lan_mvp_select_rom(guest, next_rom.data(), next_rom.size()) == 1,
                      "same connected peers can select a different local ROM");
                check(fly_lan_mvp_confirm(host) == 1 && fly_lan_mvp_confirm(guest) == 1 &&
                      wait_running(host, guest, 3000), "second game starts without pairing again");
                break;
            }

            fly_lan_mvp_destroy(guest);
            fly_lan_mvp_destroy(host);
            if (failures) return 1;
            std::cout << "PASS lan MVP real ROM lockstep\n";
            return 0;
        }
        if (mode == "--idle") {
            const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(7);
            while (std::chrono::steady_clock::now() < until) {
                (void)fly_lan_mvp_snapshot_read(host, &a);
                (void)fly_lan_mvp_snapshot_read(guest, &b);
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
            check(a.state == FLY_LAN_MVP_LOBBY && b.state == FLY_LAN_MVP_LOBBY,
                  "connected lobby survives the transport idle window");
        }
    }
    fly_lan_mvp_cancel(host);
    check(wait_state(host, FLY_LAN_MVP_ENDED, 1000), "host cancellation ends session");
    check(wait_state(guest, FLY_LAN_MVP_ENDED, 2500),
          "host cancellation closes guest connection");
    fly_lan_mvp_destroy(guest);
    fly_lan_mvp_destroy(host);

    auto* pin_host = fly_lan_mvp_create();
    auto* pin_guest = fly_lan_mvp_create();
    check(fly_lan_mvp_host(pin_host, ip.c_str(), token.data()) == 1,
          "pin rejection host starts");
    std::string bad_pin = wait_invite(pin_host);
    check(!bad_pin.empty(), "pin rejection invite available");
    if (!bad_pin.empty()) {
        const auto token_separator = bad_pin.rfind(':');
        const auto pin_separator = bad_pin.rfind(':', token_separator - 1);
        bad_pin[pin_separator + 1] = bad_pin[pin_separator + 1] == '0' ? '1' : '0';
        check(fly_lan_mvp_join(pin_guest, ip.c_str(), bad_pin.data(), bad_pin.size()) == 1,
              "guest attempts with wrong pin");
        check(wait_state(pin_guest, FLY_LAN_MVP_ENDED, 10000),
              "wrong pin cannot enter lobby");
        fly_lan_mvp_snapshot pin_state{};
        (void)fly_lan_mvp_snapshot_read(pin_guest, &pin_state);
        check(pin_state.reason == FLY_LAN_MVP_REASON_CONNECTION,
              "wrong pin fails TLS connection");
    }
    fly_lan_mvp_destroy(pin_guest);
    fly_lan_mvp_destroy(pin_host);

    auto* token_host = fly_lan_mvp_create();
    auto* token_guest = fly_lan_mvp_create();
    check(fly_lan_mvp_host(token_host, ip.c_str(), token.data()) == 1,
          "token rejection host starts");
    std::string bad_token = wait_invite(token_host);
    check(!bad_token.empty(), "token rejection invite available");
    if (!bad_token.empty()) {
        bad_token.back() = bad_token.back() == '0' ? '1' : '0';
        check(fly_lan_mvp_join(token_guest, ip.c_str(), bad_token.data(), bad_token.size()) == 1,
              "guest attempts with wrong token");
        check(wait_host_rejected(token_host, token_guest),
              "wrong token rejected inside encrypted JOIN");
    }
    fly_lan_mvp_destroy(token_guest);
    fly_lan_mvp_destroy(token_host);
    if (failures) return 1;
    std::cout << "PASS lan MVP real QUIC session\n";
    return 0;
}
