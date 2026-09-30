#include "nearby_selection.hpp"
#include <chrono>
#include <future>
#include <iostream>
#include <stdexcept>

using namespace flynes::harmony;
using namespace std::chrono_literals;
void check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
int main() {
    try {
        const auto ui = std::this_thread::get_id();
        {
            bool disposed = false, observed_disposal = false;
            finish_nearby_selection([] {}, [&] { observed_disposal = disposed; }, [] {}, [&] { disposed = true; });
            check(observed_disposal, "promise continuation observed an undisposed async work handle");
        }
        {
            // Cancellation before execute leaves the final room reference in
            // completion. A failing retirement enqueue must still reject and
            // dispose the async work exactly once without escaping the callback.
            bool escaped = false; int settled = 0, rejected = 0, disposed = 0;
            try {
                finish_nearby_selection([] { throw std::bad_alloc(); }, [&] { ++settled; },
                    [&] { ++rejected; }, [&] { ++disposed; });
            } catch (...) { escaped = true; }
            check(!escaped && settled == 0 && rejected == 1 && disposed == 1,
                "retirement enqueue failure escaped completion or skipped promise/work cleanup");
        }
        {
            NearbyRetirement retirement;
            auto reservation = NearbyRetirement::reserve();
            std::promise<std::thread::id> destroyed;
            auto ended = destroyed.get_future();
            auto owner = std::shared_ptr<int>(new int(4), [&](int* pointer) {
                delete pointer; destroyed.set_value(std::this_thread::get_id());
            });
            int rejected = 0, disposed = 0;
            finish_nearby_selection([] { throw std::bad_alloc(); }, [] {}, [&] {
                retirement.retire_reserved(owner, reservation); ++rejected;
            }, [&] { ++disposed; });
            check(!owner && !reservation && rejected == 1 && disposed == 1,
                "cancel-before-execute fallback lost owner or async completion");
            check(ended.wait_for(1s) == std::future_status::ready && ended.get() != ui,
                "failed retirement destroyed final room on UI or leaked it");
        }
        {
            NearbySelection work;
            std::promise<void> entered, release, destroyed;
            auto gate = release.get_future().share();
            auto destroyed_result = destroyed.get_future();
            auto owner = std::shared_ptr<fly_lan_mvp_session>(reinterpret_cast<fly_lan_mvp_session*>(new int(1)),
                [&](fly_lan_mvp_session* pointer) { check(std::this_thread::get_id() != ui, "retired room destroyed on UI"); delete reinterpret_cast<int*>(pointer); destroyed.set_value(); });
            work.owner = owner; work.rom = {1, 2, 3}; work.key = "owned-game"; work.generation = 7;
            bool selected = false;
            auto worker = std::async(std::launch::async, [&] {
                execute_nearby_selection(work, [&](const std::uint8_t* bytes, std::size_t size) {
                    check(size == 3 && bytes[0] == 1, "ROM was not owned"); entered.set_value(); gate.wait(); return SourceTiming{};
                }, [&](fly_lan_mvp_session*, const std::uint8_t*, std::size_t, const char*) { selected = true; return 1; });
            });
            check(entered.get_future().wait_for(1s) == std::future_status::ready, "worker did not start");
            NearbyRetirement retirement;
            retirement.retire(owner); work.cancelled.store(true);
            check(!owner && !selected, "replacement mutated current owner");
            check(destroyed_result.wait_for(0ms) == std::future_status::timeout, "room died while borrowed by worker");
            check(worker.wait_for(0ms) == std::future_status::timeout, "worker did not remain blocked independently");
            release.set_value(); worker.get();
            check(!selected && !work.owner, "stale worker selected or retained room");
            check(destroyed_result.wait_for(1s) == std::future_status::ready, "retired room leaked");
        }
        {
            // Normal selection consumes an owned copy and touches only the captured room.
            NearbySelection work; std::vector<std::uint8_t> source{4, 5, 6}; work.rom = source; source[0] = 99;
            std::promise<void> destroyed; auto ended = destroyed.get_future();
            auto* original = reinterpret_cast<fly_lan_mvp_session*>(new int(2));
            work.owner = std::shared_ptr<fly_lan_mvp_session>(original, [&](fly_lan_mvp_session* pointer) {
                check(std::this_thread::get_id() != ui, "worker owner released on UI"); delete reinterpret_cast<int*>(pointer); destroyed.set_value(); });
            auto worker = std::async(std::launch::async, [&] { execute_nearby_selection(work,
                [](const std::uint8_t*, std::size_t) { return SourceTiming{}; },
                [&](fly_lan_mvp_session* room, const std::uint8_t* bytes, std::size_t size, const char*) {
                    check(std::this_thread::get_id() != ui && room == original && size == 3 && bytes[0] == 4, "selection lost captured inputs"); return 1;
                }); });
            worker.get(); check(work.selected && ended.wait_for(1s) == std::future_status::ready, "selection or lifetime failed");
        }
        {
            // Retirement itself cannot block the caller on a slow transport destructor.
            NearbyRetirement retirement; std::promise<void> entered, release, ended; auto gate = release.get_future().share();
            auto owner = std::shared_ptr<int>(new int(3), [&](int* pointer) { entered.set_value(); gate.wait(); delete pointer; ended.set_value(); });
            retirement.retire(owner);
            check(!owner && entered.get_future().wait_for(1s) == std::future_status::ready, "retirement did not detach");
            auto result = ended.get_future(); check(result.wait_for(0ms) == std::future_status::timeout, "fixture destructor did not block");
            release.set_value(); check(result.wait_for(1s) == std::future_status::ready, "retirement did not finish");
        }
        std::cout << "PASS nearby selection ownership, blocked worker, replacement, retirement\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
