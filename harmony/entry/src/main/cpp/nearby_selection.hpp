#pragma once

#include "native_play_support.hpp"
#include <flynes/flynes_nearby_mvp.h>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace flynes::harmony {

template<class Retire, class Settle, class Reject, class Dispose>
void finish_nearby_selection(Retire&& retire, Settle&& settle, Reject&& reject, Dispose&& dispose) noexcept {
    bool failed = false;
    try { retire(); } catch (...) { failed = true; }
    // ArkTS can resume promise continuations from resolve/reject immediately.
    // Dispose first so a resumed caller cannot observe an outstanding handle.
    try { dispose(); } catch (...) { failed = true; }
    if (failed) {
        // Rejection transfers a remaining room through the reserved slot before
        // invoking N-API. The fallback does not allocate or create a thread.
        try { reject(); } catch (...) {}
    } else {
        try { settle(); } catch (...) { try { reject(); } catch (...) {} }
    }
}

// Retired owners are released off the UI thread, even if selection has already
// finished but its N-API completion has not run. No periodic wakeups are used.
class NearbyRetirement final {
public:
    struct Slot {
        std::shared_ptr<void> owner;
        Slot* next = nullptr;
    };
    using Reservation = std::unique_ptr<Slot>;
    static Reservation reserve() { return std::make_unique<Slot>(); }
    NearbyRetirement() : worker_([this] { run(); }) {}
    ~NearbyRetirement() {
        { std::lock_guard<std::mutex> lock(mutex_); stop_ = true; }
        ready_.notify_one();
        worker_.join();
    }
    template<class T> void retire(std::shared_ptr<T>& owner) {
        if (!owner) return;
        { std::lock_guard<std::mutex> lock(mutex_);
          owners_.push_back(owner); // On allocation failure the current owner remains intact.
          owner.reset(); }
        ready_.notify_one();
    }
    // The caller reserves this node before starting asynchronous work. This
    // fallback cannot allocate or start a thread at the completion boundary.
    template<class T> void retire_reserved(std::shared_ptr<T>& owner, Reservation& slot) noexcept {
        if (!owner) return;
        { std::lock_guard<std::mutex> lock(mutex_);
          slot->owner = std::move(owner);
          Slot* next = slot.release();
          if (last_reserved_) last_reserved_->next = next; else first_reserved_ = next;
          last_reserved_ = next; }
        ready_.notify_one();
    }
private:
    void run() {
        for (;;) {
            std::shared_ptr<void> owner;
            Reservation reserved;
            { std::unique_lock<std::mutex> lock(mutex_);
              ready_.wait(lock, [this] { return stop_ || !owners_.empty() || first_reserved_; });
              if (first_reserved_) {
                  reserved.reset(first_reserved_); first_reserved_ = first_reserved_->next;
                  if (!first_reserved_) last_reserved_ = nullptr;
                  owner = std::move(reserved->owner);
              } else {
                  if (owners_.empty()) return;
                  owner = std::move(owners_.front()); owners_.pop_front();
              } }
            owner.reset();
        }
    }
    std::mutex mutex_;
    std::condition_variable ready_;
    std::deque<std::shared_ptr<void>> owners_;
    Slot* first_reserved_ = nullptr;
    Slot* last_reserved_ = nullptr;
    bool stop_ = false;
    std::thread worker_;
};

struct NearbySelection final {
    std::shared_ptr<fly_lan_mvp_session> owner;
    std::vector<std::uint8_t> rom;
    std::string key;
    std::uint64_t generation = 0;
    std::atomic<bool> cancelled{false};
    fly_lan_mvp_snapshot frozen{};
    std::string peer_config_token;
    SourceTiming timing;
    bool selected = false;
    std::string error;
};

// Called only by the N-API executor. Ports are explicit so host tests can block
// at the real ownership boundary without needing a transport or private ROM.
inline void execute_nearby_selection(NearbySelection& work,
    const std::function<SourceTiming(const std::uint8_t*, std::size_t)>& timing,
    const std::function<int(fly_lan_mvp_session*, const std::uint8_t*, std::size_t, const char*)>& select) noexcept {
    try {
        if (!work.cancelled.load()) {
            work.timing = timing(work.rom.data(), work.rom.size());
            if (!work.cancelled.load()) work.selected = select(work.owner.get(), work.rom.data(), work.rom.size(), work.key.c_str()) == 1;
        }
    } catch (...) { work.error = "selection_failed"; }
    // If the room was retired, its last reference must leave on this worker.
    work.owner.reset();
}
} // namespace flynes::harmony
