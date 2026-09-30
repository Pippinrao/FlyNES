#include "flynes/flynes_nearby_mvp.h"

#include "lan_mvp/invite.hpp"
#include "lan_mvp/wire.hpp"
#include "lan_mvp/pause.hpp"
#include "../../runtime/serialized_state_capture.hpp"
#include "wire/sha256.hpp"
#include "flynes_quic_provider.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

using flynes::session::lan_mvp::Invite;
namespace wire = flynes::session::lan_mvp::wire;

namespace {
enum class Operation : std::uint32_t {
    Material = 1, Listen = 2, Accept = 3, Connect = 4,
    OpenStream = 5, AcceptStream = 6, Read = 7, Write = 8
};
enum class Role { None, Host, Guest };
constexpr std::chrono::seconds kInviteLife{120};
constexpr std::chrono::seconds kProgressTimeout{2};
constexpr std::uint64_t kPredictionDepth = 10;
constexpr std::uint64_t kRollbackSlots = 12;
constexpr std::uint64_t kDigestInterval = 60;
constexpr std::size_t kLocalInputCapacity = 16;

std::uint64_t monotonic_ns() {
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

std::string endpoint(const Invite& invite) {
    std::string result;
    for (std::size_t i = 0; i < invite.ipv4.size(); ++i) {
        if (i != 0) result.push_back('.');
        result += std::to_string(invite.ipv4[i]);
    }
    result.push_back(':');
    result += std::to_string(invite.port);
    return result;
}

std::uint64_t big_endian_u64(const std::uint8_t* bytes) {
    std::uint64_t value = 0;
    for (unsigned i = 0; i < 8; ++i) value = (value << 8u) | bytes[i];
    return value;
}

std::uint32_t big_endian_u32(const std::uint8_t* bytes) {
    std::uint32_t value = 0;
    for (unsigned i = 0; i < 4; ++i) value = (value << 8u) | bytes[i];
    return value;
}

void append_u64(std::vector<std::uint8_t>* bytes, std::uint64_t value) {
    for (int shift = 56; shift >= 0; shift -= 8)
        bytes->push_back(static_cast<std::uint8_t>(value >> static_cast<unsigned>(shift)));
}

void append_u32(std::vector<std::uint8_t>* bytes, std::uint32_t value) {
    for (int shift = 24; shift >= 0; shift -= 8)
        bytes->push_back(static_cast<std::uint8_t>(value >> static_cast<unsigned>(shift)));
}

bool same_bytes(const std::uint8_t* a, const std::uint8_t* b, std::size_t size) {
    std::uint8_t difference = 0;
    for (std::size_t i = 0; i < size; ++i) difference |= a[i] ^ b[i];
    return difference == 0;
}

std::array<std::uint8_t, 32> make_config_hash(
        const std::array<std::uint8_t, 32>& rom_hash,
        const fly_runtime_source_timing_v1& timing) {
    static constexpr char kCompatibility[] = "flynes-lan-mvp-prediction-v4-resume-ack";
    std::vector<std::uint8_t> bytes(rom_hash.begin(), rom_hash.end());
    bytes.insert(bytes.end(), kCompatibility, kCompatibility + sizeof(kCompatibility) - 1);
    append_u32(&bytes, timing.source_region);
    append_u32(&bytes, timing.frame_rate_numerator);
    append_u32(&bytes, timing.frame_rate_denominator);
    append_u32(&bytes, timing.sample_rate);
    return flynes::session::wire::sha256(bytes.data(), bytes.size());
}
} // namespace

struct Event {
    std::uint64_t operation = 0;
    std::int32_t result = 0;
    std::uint64_t resource = 0;
    std::vector<std::uint8_t> bytes;
};

struct SimulatedFrame {
    std::uint32_t local = 0;
    std::uint32_t remote = 0;
    std::uint64_t local_sequence = 0;
    std::uint64_t local_capture_time_ns = 0;
    std::uint64_t audio_first = 0;
    std::array<std::uint8_t, 32> state_hash{};
};

struct LocalInputState {
    std::uint32_t buttons = 0;
    std::uint64_t sequence = 0;
    std::uint64_t capture_time_ns = 0;
};

struct fly_lan_mvp_session {
    std::atomic<unsigned> references{1};
    std::mutex mutex;
    std::condition_variable wake;
    std::thread worker;
    bool worker_stop = false;
    bool input_dirty = false;
    fly_lan_mvp_diagnostic_sink diagnostic_sink = nullptr;
    void* diagnostic_context = nullptr;
    const std::chrono::steady_clock::time_point created = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point previous_pump = created;
    std::uint64_t diagnostic_sequence = 0;
    std::uint64_t read_bytes = 0, written_bytes = 0;
    std::uint32_t last_logged_state = ~0u;
    FlynesQuicProvider* provider = nullptr;
    std::vector<Event> events;
    std::unordered_map<std::uint64_t, Operation> operations;
    std::uint64_t next_operation = 1;
    Role role = Role::None;
    fly_lan_mvp_snapshot view{};
    Invite invite{};
    std::string qr;
    std::chrono::steady_clock::time_point deadline{};
    std::chrono::steady_clock::time_point last_progress{};
    std::uint64_t material = 0;
    std::uint64_t listener = 0;
    std::uint64_t connection = 0;
    std::uint64_t send_stream = 0;
    std::uint64_t recv_stream = 0;
    wire::Decoder decoder;
    bool read_inflight = false;
    bool write_inflight = false;
    std::deque<std::vector<std::uint8_t>> writes;
    fly_runtime_t* runtime = nullptr;
    std::array<std::uint8_t, 32> local_rom_hash{};
    std::array<std::uint8_t, 32> remote_rom_hash{};
    std::array<std::uint8_t, 32> local_config_hash{};
    std::array<std::uint8_t, 32> remote_config_hash{};
    bool local_configured = false;
    bool peer_configured = false;
    bool local_ready = false;
    bool peer_ready = false;
    flynes::session::lan_mvp::PauseState pause;
    std::map<std::uint64_t, std::uint32_t> local_inputs;
    std::map<std::uint64_t, std::uint32_t> remote_inputs;
    std::map<std::uint64_t, SimulatedFrame> history;
    std::uint64_t confirmed_frames = 0;
    std::uint32_t current_local_buttons = 0;
    std::uint64_t current_local_sequence = 0;
    std::uint64_t current_local_capture_time_ns = 0;
    std::uint64_t next_local_sequence = 0;
    std::deque<LocalInputState> pending_local_inputs;
    bool has_input_state = false;
    std::chrono::nanoseconds frame_period{16'639'267};
    std::chrono::steady_clock::time_point next_frame_due{};
    std::uint32_t last_submitted_buttons = 0;
    std::array<std::uint32_t, 2> last_applied_buttons{};
    std::uint64_t lobby_generation = 0;
    std::uint64_t pcm_produced = 0, pcm_consumed = 0;
    std::uint32_t sample_rate = FLY_RUNTIME_DEFAULT_SAMPLE_RATE;
    std::deque<std::int16_t> pcm_queue;
    std::vector<std::uint8_t> published_frame;
    fly_latest_frame_v1 published_meta{};
    std::uint64_t publication_sequence = 0;
    std::uint64_t last_read_publication_sequence = 0;
    bool has_published_frame = false;
    fly_lan_mvp_stats_v1 stats{};
    std::map<std::uint64_t, std::array<std::uint8_t, 32>> local_digests;
    std::map<std::uint64_t, std::array<std::uint8_t, 32>> remote_digests;

    ~fly_lan_mvp_session() {
        if (runtime != nullptr) fly_runtime_destroy(runtime);
    }

    void trace(const char* event, const std::string& detail = {}) {
        if (!diagnostic_sink) return;
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - created).count();
        const std::string line = "seq=" + std::to_string(++diagnostic_sequence) +
            " age_ms=" + std::to_string(ms) + " role=" + std::to_string(static_cast<int>(role)) +
            " event=" + event + " state=" + std::to_string(view.state) +
            " reason=" + std::to_string(view.reason) + " frame=" + std::to_string(view.completed_frames) +
            " pending=" + std::to_string(operations.size()) + " callbacks=" + std::to_string(events.size()) +
            " writes=" + std::to_string(writes.size()) +
            " tx=" + std::to_string(written_bytes) + " rx=" + std::to_string(read_bytes) + " " + detail;
        diagnostic_sink(diagnostic_context, line.c_str());
    }

    void sync_view() {
        view.role = role == Role::Host ? FLY_LAN_MVP_ROLE_HOST_P1 :
                    role == Role::Guest ? FLY_LAN_MVP_ROLE_GUEST_P2 :
                                          FLY_LAN_MVP_ROLE_NONE;
        view.local_configured = local_configured ? 1u : 0u;
        view.peer_configured = peer_configured ? 1u : 0u;
        view.local_ready = local_ready ? 1u : 0u;
        view.peer_ready = peer_ready ? 1u : 0u;
        if (local_configured)
            std::memcpy(view.config_hash, local_config_hash.data(), local_config_hash.size());
    }

    void stop_runtime() {
        local_inputs.clear();
        remote_inputs.clear();
        history.clear();
        if (runtime != nullptr) {
            fly_runtime_destroy(runtime);
            runtime = nullptr;
        }
    }

    void end(std::uint32_t reason) {
        if (view.state == FLY_LAN_MVP_ENDED) return;
        view.state = FLY_LAN_MVP_ENDED;
        view.reason = reason;
        trace("end", "op=" + std::to_string(view.transport_operation) +
            " result=" + std::to_string(view.transport_result));
        qr.clear();
        writes.clear();
        write_inflight = false;
        read_inflight = false;
        stop_runtime();
        for (const auto& pending : operations)
            (void)flynes_quic_provider_cancel(provider, pending.first);
        operations.clear();
        if (connection != 0)
            (void)flynes_quic_provider_close(provider, next_operation++, connection, 0);
        if (listener != 0)
            (void)flynes_quic_provider_close(provider, next_operation++, listener, 0);
    }

    template <typename Submit>
    bool submit(Operation kind, Submit call) {
        const auto operation = next_operation++;
        operations.emplace(operation, kind);
        if (view.state != FLY_LAN_MVP_RUNNING)
            trace("submit", "id=" + std::to_string(operation) +
                " op=" + std::to_string(static_cast<unsigned>(kind)));
        const auto result = call(operation);
        if (result == FLYNES_QUIC_ACCEPTED) return true;
        operations.erase(operation);
        view.transport_result = result;
        view.transport_operation = static_cast<std::uint32_t>(kind);
        end(FLY_LAN_MVP_REASON_CONNECTION);
        return false;
    }

    bool begin_read() {
        if (read_inflight || recv_stream == 0 || view.state == FLY_LAN_MVP_ENDED) return true;
        read_inflight = true;
        if (submit(Operation::Read, [this](std::uint64_t op) {
                return flynes_quic_provider_read(provider, op, recv_stream,
                                                  wire::kMaxBodySize + 2);
            })) return true;
        read_inflight = false;
        return false;
    }

    bool begin_next_write() {
        if (write_inflight || writes.empty() || send_stream == 0 ||
            view.state == FLY_LAN_MVP_ENDED) return true;
        write_inflight = true;
        const auto& bytes = writes.front();
        if (submit(Operation::Write, [this, &bytes](std::uint64_t op) {
                return flynes_quic_provider_write(provider, op, send_stream,
                                                   bytes.data(), bytes.size(), 0);
            })) return true;
        write_inflight = false;
        return false;
    }

    bool queue_message(wire::Kind kind, const std::vector<std::uint8_t>& payload) {
        std::vector<std::uint8_t> bytes;
        if (!wire::encode(kind, payload, &bytes)) {
            end(FLY_LAN_MVP_REASON_REJECTED);
            return false;
        }
        writes.push_back(std::move(bytes));
        if (kind != wire::Kind::Input && kind != wire::Kind::Digest)
            trace("message_tx", "kind=" + std::to_string(static_cast<unsigned>(kind)) +
                " size=" + std::to_string(payload.size()));
        return begin_next_write();
    }

    bool configs_match() const {
        return local_configured && peer_configured &&
               same_bytes(local_rom_hash.data(), remote_rom_hash.data(), local_rom_hash.size()) &&
               same_bytes(local_config_hash.data(), remote_config_hash.data(),
                          local_config_hash.size());
    }

    void compare_digest(std::uint64_t frame) {
        const auto local = local_digests.find(frame);
        const auto remote = remote_digests.find(frame);
        if (local == local_digests.end() || remote == remote_digests.end()) return;
        if (!same_bytes(local->second.data(), remote->second.data(), local->second.size())) {
            end(FLY_LAN_MVP_REASON_DESYNC);
            return;
        }
        local_digests.erase(local);
        remote_digests.erase(remote);
    }

    void publish_digest(std::uint64_t frame) {
        if ((frame + 1) % 300 == 0) trace("progress");
        const auto found = history.find(frame);
        if (found == history.end()) {
            end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
            return;
        }
        const auto& state = found->second.state_hash;
        local_digests[frame] = state;
        view.last_digest_frame = frame;
        std::memcpy(view.last_state_digest, state.data(), state.size());
        std::vector<std::uint8_t> payload;
        payload.reserve(40);
        append_u64(&payload, frame);
        payload.insert(payload.end(), state.begin(), state.end());
        (void)queue_message(wire::Kind::Digest, payload);
        compare_digest(frame);
    }

    std::uint32_t predicted_remote(std::uint64_t frame) const {
        auto found = remote_inputs.lower_bound(frame);
        if (found == remote_inputs.begin()) return 0;
        return (--found)->second;
    }

    void trim_unplayed_pcm(std::uint64_t first_sample) {
        const auto retained = first_sample > pcm_consumed ? first_sample - pcm_consumed : 0;
        while (pcm_queue.size() > retained) pcm_queue.pop_back();
        pcm_produced = pcm_consumed + pcm_queue.size();
    }

    bool collect_pcm(const fly_frame_result_v1& result) {
        if (!result.pcm_published) return true;
        const auto count = static_cast<std::uint32_t>(
            result.audio_last_sample_sequence - result.audio_first_sample_sequence + 1);
        std::vector<std::int16_t> samples(count);
        fly_pcm_block_v1 block{};
        block.struct_size = FLY_PCM_BLOCK_V1_SIZE;
        block.version = FLY_PCM_BLOCK_VERSION_1;
        const auto pulled = fly_runtime_pull_pcm(runtime, samples.data(), count, &block);
        if (pulled != FLY_RESULT_OK ||
            block.sample_count != count ||
            block.first_sample_sequence != result.audio_first_sample_sequence) {
            trace("runtime_error", "stage=pcm_pull result=" + std::to_string(pulled) +
                " expected_count=" + std::to_string(count) +
                " actual_count=" + std::to_string(block.sample_count) +
                " expected_first=" + std::to_string(result.audio_first_sample_sequence) +
                " actual_first=" + std::to_string(block.first_sample_sequence));
            end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
            return false;
        }
        for (std::uint32_t index = 0; index < count; ++index) {
            const auto sequence = block.first_sample_sequence + index;
            if (sequence >= pcm_consumed + pcm_queue.size()) pcm_queue.push_back(samples[index]);
        }
        constexpr std::size_t kPcmBudgetSamples = 8192;
        while (pcm_queue.size() > kPcmBudgetSamples) {
            pcm_queue.pop_front();
            ++pcm_consumed;
            ++stats.pcm_dropped_samples;
        }
        stats.pcm_generated_samples += count;
        stats.pcm_queue_high_samples = std::max<std::uint64_t>(
            stats.pcm_queue_high_samples, pcm_queue.size());
        pcm_produced = pcm_consumed + pcm_queue.size();
        return true;
    }

    bool publish_frame() {
        published_frame.resize(FLY_RUNTIME_RGB565_BYTES);
        fly_latest_frame_v1 meta{};
        meta.struct_size = FLY_LATEST_FRAME_V1_SIZE;
        meta.version = FLY_LATEST_FRAME_VERSION_1;
        if (fly_runtime_copy_latest_frame(runtime, published_frame.data(),
                                          published_frame.size(), &meta) != FLY_RESULT_OK) {
            trace("runtime_error", "stage=frame_copy");
            end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
            return false;
        }
        meta.frame_sequence = ++publication_sequence;
        ++stats.published_frames;
        published_meta = meta;
        has_published_frame = true;
        return true;
    }

    bool step_frame(std::uint64_t frame, std::uint32_t local, std::uint32_t remote,
                    std::uint64_t local_sequence, std::uint64_t local_capture_time_ns,
                    bool publish = true) {
        flynes::runtime_detail::last_capture = {};
        const auto captured = fly_runtime_capture_rollback(runtime,
                static_cast<std::uint32_t>(frame % kRollbackSlots));
        if (captured != FLY_RESULT_OK) {
            const auto& detail = flynes::runtime_detail::last_capture;
            trace("runtime_error", "stage=rollback_capture frame=" + std::to_string(frame) +
                " result=" + std::to_string(captured) + " core_result=" + std::to_string(detail.core_result) +
                " core_call_returned=" + std::to_string(detail.core_call_returned) +
                " attempts=" + std::to_string(detail.attempts) + " capacity=" + std::to_string(detail.capacity) +
                " written=" + std::to_string(detail.written) + " needed=" + std::to_string(detail.needed));
            end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
            return false;
        }
        fly_frame_input_v1 input{};
        input.struct_size = FLY_FRAME_INPUT_V1_SIZE;
        input.version = FLY_FRAME_INPUT_VERSION_1;
        input.timeline_epoch = 1;
        input.frame_index = frame;
        input.capture_time_ns = local_capture_time_ns;
        input.predicted_port_mask = remote_inputs.count(frame) == 0
            ? (role == Role::Host ? 2u : 1u) : 0u;
        if (role == Role::Host) {
            input.buttons[0] = local;
            input.buttons[1] = remote;
        } else {
            input.buttons[0] = remote;
            input.buttons[1] = local;
        }
        input.input_sequence[0] = role == Role::Host ? local_sequence : frame + 1;
        input.input_sequence[1] = role == Role::Host ? frame + 1 : local_sequence;
        input.batch_sequence = frame + 1;
        fly_frame_result_v1 result{};
        result.struct_size = FLY_FRAME_RESULT_V1_SIZE;
        result.version = FLY_FRAME_RESULT_VERSION_1;
        const auto stepped = fly_runtime_step_frame(runtime, &input, &result);
        if (stepped != FLY_RESULT_OK) {
            trace("runtime_error", "stage=frame_step frame=" + std::to_string(frame) +
                " result=" + std::to_string(stepped));
            end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
            return false;
        }
        stats.last_core_step_ns = monotonic_ns();
        SimulatedFrame used{};
        used.local = local;
        used.remote = remote;
        used.local_sequence = local_sequence;
        used.local_capture_time_ns = local_capture_time_ns;
        used.audio_first = result.audio_first_sample_sequence;
        if (!collect_pcm(result)) return false;
        if ((frame + 1) % kDigestInterval == 0) {
            fly_runtime_frame_digest_v1 digest{};
            digest.struct_size = FLY_RUNTIME_FRAME_DIGEST_V1_SIZE;
            digest.version = FLY_RUNTIME_FRAME_DIGEST_VERSION_1;
            if (fly_runtime_copy_frame_digest(runtime, 1, frame, &digest) != FLY_RESULT_OK) {
                trace("runtime_error", "stage=frame_digest frame=" + std::to_string(frame));
                end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
                return false;
            }
            std::memcpy(used.state_hash.data(), digest.state_sha256, used.state_hash.size());
        }
        history[frame] = used;
        if (input.buttons[0] != last_applied_buttons[0] ||
            input.buttons[1] != last_applied_buttons[1]) {
            trace("input_apply", "input_frame=" + std::to_string(frame) +
                " p1=" + std::to_string(input.buttons[0]) +
                " p2=" + std::to_string(input.buttons[1]));
            last_applied_buttons = {input.buttons[0], input.buttons[1]};
        }
        view.applied_buttons[0] = input.buttons[0];
        view.applied_buttons[1] = input.buttons[1];
        return !publish || publish_frame();
    }

    void confirm_history() {
        while (confirmed_frames < view.completed_frames) {
            const auto actual = remote_inputs.find(confirmed_frames);
            const auto used = history.find(confirmed_frames);
            if (actual == remote_inputs.end() || used == history.end() ||
                actual->second != used->second.remote) break;
            const auto confirmed = confirmed_frames++;
            if ((confirmed + 1) % kDigestInterval == 0) publish_digest(confirmed);
        }
        while (!history.empty() && history.begin()->first + kRollbackSlots < confirmed_frames)
            history.erase(history.begin());
        while (!remote_inputs.empty() && remote_inputs.begin()->first + kRollbackSlots < confirmed_frames)
            remote_inputs.erase(remote_inputs.begin());
        while (!local_inputs.empty() && local_inputs.begin()->first + kRollbackSlots < confirmed_frames)
            local_inputs.erase(local_inputs.begin());
    }

    void replay_from(std::uint64_t first) {
        trace("rollback_start", "first=" + std::to_string(first));
        if (first < confirmed_frames || first + kRollbackSlots < view.completed_frames ||
            fly_runtime_restore_rollback(runtime,
                static_cast<std::uint32_t>(first % kRollbackSlots)) != FLY_RESULT_OK) {
            end(FLY_LAN_MVP_REASON_DESYNC);
            return;
        }
        const auto earliest = history.find(first);
        if (earliest == history.end()) { end(FLY_LAN_MVP_REASON_DESYNC); return; }
        trim_unplayed_pcm(earliest->second.audio_first);
        ++stats.rollback_count;
        for (std::uint64_t frame = first; frame < view.completed_frames; ++frame) {
            const auto used = history.find(frame);
            if (used == history.end()) { end(FLY_LAN_MVP_REASON_DESYNC); return; }
            const auto actual = remote_inputs.find(frame);
            const std::uint32_t remote = actual == remote_inputs.end()
                ? predicted_remote(frame) : actual->second;
            if (!step_frame(frame, used->second.local, remote,
                    used->second.local_sequence, used->second.local_capture_time_ns, false)) return;
            ++stats.replayed_frames;
        }
        if (!publish_frame()) return;
        trace("rollback", "first=" + std::to_string(first));
        confirm_history();
    }

    void advance() {
        if (view.state != FLY_LAN_MVP_RUNNING || view.paused || runtime == nullptr) return;
        const auto now = std::chrono::steady_clock::now();
        if (!has_input_state || now < next_frame_due ||
            view.completed_frames - confirmed_frames >= kPredictionDepth) return;
        const auto frame = view.completed_frames;
        const LocalInputState local = pending_local_inputs.empty()
            ? LocalInputState{current_local_buttons, current_local_sequence, current_local_capture_time_ns}
            : pending_local_inputs.front();
        std::vector<std::uint8_t> payload;
        payload.reserve(12);
        append_u64(&payload, frame);
        append_u32(&payload, local.buttons);
        if (!queue_message(wire::Kind::Input, payload)) return;
        local_inputs[frame] = local.buttons;
        const auto actual = remote_inputs.find(frame);
        const auto remote = actual == remote_inputs.end() ? predicted_remote(frame) : actual->second;
        if (!step_frame(frame, local.buttons, remote, local.sequence, local.capture_time_ns)) return;
        // A deadline/prediction stall never consumes a transition. It belongs to
        // this exact successful core frame, including its original capture data.
        if (!pending_local_inputs.empty()) pending_local_inputs.pop_front();
        ++stats.simulated_frames;
        if (actual == remote_inputs.end()) ++stats.predicted_frames;
        view.completed_frames = frame + 1;
        last_progress = now;
        confirm_history();
        next_frame_due += frame_period;
        if (next_frame_due < now) next_frame_due = now + frame_period;
    }

    void clear_pending_input() {
        pending_local_inputs.clear();
        current_local_buttons = 0;
        current_local_sequence = current_local_capture_time_ns = 0;
        last_submitted_buttons = 0;
    }

    void enter_running() {
        if (view.state == FLY_LAN_MVP_RUNNING || runtime == nullptr || !configs_match() ||
            !local_ready || !peer_ready) return;
        view.state = FLY_LAN_MVP_RUNNING;
        view.reason = FLY_LAN_MVP_REASON_NONE;
        view.completed_frames = 0;
        pcm_produced = pcm_consumed = 0;
        pcm_queue.clear();
        has_published_frame = false;
        view.last_digest_frame = 0;
        std::memset(view.last_state_digest, 0, sizeof(view.last_state_digest));
        local_inputs.clear();
        remote_inputs.clear();
        history.clear();
        confirmed_frames = 0;
        current_local_buttons = 0;
        current_local_sequence = current_local_capture_time_ns = next_local_sequence = 0;
        has_input_state = false;
        pending_local_inputs.clear();
        local_digests.clear();
        remote_digests.clear();
        fly_runtime_source_timing_v1 timing{};
        timing.struct_size = FLY_RUNTIME_SOURCE_TIMING_V1_SIZE;
        timing.version = FLY_RUNTIME_SOURCE_TIMING_VERSION_1;
        if (fly_runtime_get_source_timing(runtime, &timing) != FLY_RESULT_OK ||
            timing.frame_rate_numerator == 0) { end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH); return; }
        frame_period = std::chrono::nanoseconds(1'000'000'000ull *
            timing.frame_rate_denominator / timing.frame_rate_numerator);
        sample_rate = timing.sample_rate;
        next_frame_due = std::chrono::steady_clock::now();
        last_progress = std::chrono::steady_clock::now();
    }

    void maybe_start_host() {
        if (role != Role::Host || view.state == FLY_LAN_MVP_RUNNING ||
            !local_ready || !peer_ready || !configs_match()) return;
        const std::vector<std::uint8_t> payload(local_config_hash.begin(),
                                                local_config_hash.end());
        if (queue_message(wire::Kind::Start, payload)) enter_running();
    }

    void clear_game() {
        stop_runtime();
        local_configured = peer_configured = local_ready = peer_ready = false;
        local_rom_hash = {}; remote_rom_hash = {};
        local_config_hash = {}; remote_config_hash = {};
        local_digests.clear(); remote_digests.clear();
        confirmed_frames = 0;
        view.completed_frames = view.last_digest_frame = 0;
        pcm_produced = pcm_consumed = 0;
        pcm_queue.clear();
        has_published_frame = false;
        pause = {};
        view.paused = 0;
        std::memset(view.peer_game_key, 0, sizeof(view.peer_game_key));
        view.applied_buttons[0] = view.applied_buttons[1] = 0;
        std::memset(view.config_hash, 0, sizeof(view.config_hash));
        std::memset(view.last_state_digest, 0, sizeof(view.last_state_digest));
        view.reason = FLY_LAN_MVP_REASON_NONE;
        current_local_buttons = 0;
        current_local_sequence = current_local_capture_time_ns = next_local_sequence = 0;
        has_input_state = false;
        pending_local_inputs.clear();
        last_submitted_buttons = 0; last_applied_buttons = {};
    }

    bool return_lobby() {
        if (view.state == FLY_LAN_MVP_RETURNING) return true;
        if (view.state != FLY_LAN_MVP_RUNNING && view.state != FLY_LAN_MVP_LOBBY &&
            view.state != FLY_LAN_MVP_CONFIGURING) return false;
        if (role == Role::Guest) {
            view.state = FLY_LAN_MVP_RETURNING;
            return queue_message(wire::Kind::LobbyRequest, {});
        }
        clear_game();
        view.state = FLY_LAN_MVP_RETURNING;
        std::vector<std::uint8_t> payload;
        append_u64(&payload, ++lobby_generation);
        return queue_message(wire::Kind::Lobby, payload);
    }

    void handle_message(const wire::Message& message) {
        if (message.kind != wire::Kind::Input && message.kind != wire::Kind::Digest)
            trace("message_rx", "kind=" + std::to_string(static_cast<unsigned>(message.kind)) +
                " size=" + std::to_string(message.payload.size()));
        if (message.kind == wire::Kind::LobbyRequest && role == Role::Host && message.payload.empty()) {
            (void)return_lobby();
            return;
        }
        if (message.kind == wire::Kind::Lobby && role == Role::Guest && message.payload.size() == 8) {
            clear_game();
            lobby_generation = big_endian_u64(message.payload.data());
            view.state = FLY_LAN_MVP_LOBBY;
            (void)queue_message(wire::Kind::LobbyAck, message.payload);
            return;
        }
        if (message.kind == wire::Kind::LobbyAck && role == Role::Host &&
            view.state == FLY_LAN_MVP_RETURNING && message.payload.size() == 8 &&
            big_endian_u64(message.payload.data()) == lobby_generation) {
            view.state = FLY_LAN_MVP_LOBBY;
            return;
        }
        // The bidirectional stream barrier drains the previous game's messages
        // before either side can send a new config or restart frame numbering.
        if (view.state == FLY_LAN_MVP_RETURNING) return;
        if (message.kind == wire::Kind::Pause && message.payload.size() == 1) {
            if (view.state != FLY_LAN_MVP_RUNNING) return;
            const auto reply = pause.receive(message.payload[0], role == Role::Host);
            view.paused = pause.paused();
            if (view.paused) clear_pending_input();
            last_progress = std::chrono::steady_clock::now();
            if (reply) (void)queue_message(wire::Kind::Pause, {*reply});
            if (!view.paused) advance();
            return;
        }
        if (message.kind == wire::Kind::Join) {
            if (role != Role::Host || view.state != FLY_LAN_MVP_INVITING ||
                message.payload.size() != invite.token.size() ||
                std::chrono::steady_clock::now() >= deadline ||
                !same_bytes(invite.token.data(), message.payload.data(), invite.token.size())) {
                end(std::chrono::steady_clock::now() >= deadline
                        ? FLY_LAN_MVP_REASON_EXPIRED : FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            std::array<std::uint8_t, 48> seed{};
            std::memcpy(seed.data(), invite.token.data(), 16);
            std::memcpy(seed.data() + 16, invite.spki_pin.data(), 32);
            const auto hash = flynes::session::wire::sha256(seed.data(), seed.size());
            std::memcpy(view.session_id, hash.data(), 16);
            qr.clear();
            const std::vector<std::uint8_t> payload(view.session_id, view.session_id + 16);
            if (queue_message(wire::Kind::Accept, payload)) view.state = FLY_LAN_MVP_LOBBY;
            return;
        }
        if (message.kind == wire::Kind::Accept) {
            if (role != Role::Guest || view.state != FLY_LAN_MVP_JOINING ||
                message.payload.size() != 16) {
                end(FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            std::memcpy(view.session_id, message.payload.data(), 16);
            view.state = FLY_LAN_MVP_LOBBY;
            return;
        }
        if (message.kind == wire::Kind::Config) {
            if ((view.state != FLY_LAN_MVP_LOBBY &&
                 view.state != FLY_LAN_MVP_CONFIGURING) || message.payload.size() < 64 ||
                 message.payload.size() >= 64 + sizeof(view.peer_game_key)) {
                end(FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            const bool changed = peer_configured &&
                (!same_bytes(remote_rom_hash.data(), message.payload.data(), 32) ||
                 !same_bytes(remote_config_hash.data(), message.payload.data() + 32, 32));
            std::memcpy(remote_rom_hash.data(), message.payload.data(), 32);
            std::memcpy(remote_config_hash.data(), message.payload.data() + 32, 32);
            std::memset(view.peer_game_key, 0, sizeof(view.peer_game_key));
            if (message.payload.size() > 64)
                std::memcpy(view.peer_game_key, message.payload.data() + 64, message.payload.size() - 64);
            peer_configured = true;
            if (changed) {
                local_ready = false;
                peer_ready = false;
            }
            view.state = FLY_LAN_MVP_CONFIGURING;
            if (local_configured &&
                !same_bytes(local_rom_hash.data(), remote_rom_hash.data(), 32)) {
                view.reason = FLY_LAN_MVP_REASON_ROM_MISMATCH;
                local_ready = peer_ready = false;
                return;
            }
            if (local_configured &&
                !same_bytes(local_config_hash.data(), remote_config_hash.data(), 32)) {
                view.reason = FLY_LAN_MVP_REASON_CONFIG_MISMATCH;
                local_ready = peer_ready = false;
                return;
            }
            maybe_start_host();
            return;
        }
        if (message.kind == wire::Kind::Ready) {
            if ((view.state != FLY_LAN_MVP_CONFIGURING &&
                 view.state != FLY_LAN_MVP_LOBBY) || message.payload.size() != 32 ||
                !peer_configured ||
                !same_bytes(remote_config_hash.data(), message.payload.data(), 32)) {
                end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
                return;
            }
            peer_ready = true;
            maybe_start_host();
            return;
        }
        if (message.kind == wire::Kind::Start) {
            if (role != Role::Guest || view.state != FLY_LAN_MVP_CONFIGURING ||
                message.payload.size() != 32 || !local_ready || !peer_ready ||
                !same_bytes(local_config_hash.data(), message.payload.data(), 32) ||
                !configs_match()) {
                end(FLY_LAN_MVP_REASON_CONFIG_MISMATCH);
                return;
            }
            enter_running();
            return;
        }
        if (message.kind == wire::Kind::Input) {
            if (view.state != FLY_LAN_MVP_RUNNING || message.payload.size() != 12) {
                end(FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            const auto frame = big_endian_u64(message.payload.data());
            const auto buttons = big_endian_u32(message.payload.data() + 8);
            stats.last_remote_receive_ns = monotonic_ns();
            if (frame < confirmed_frames || frame > view.completed_frames + 256 ||
                frame + kRollbackSlots < view.completed_frames) {
                end(FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            const auto [found, inserted] = remote_inputs.emplace(frame, buttons);
            if (!inserted && found->second != buttons) {
                end(FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            if (frame < view.completed_frames) {
                const auto used = history.find(frame);
                if (used == history.end()) {
                    end(FLY_LAN_MVP_REASON_DESYNC);
                    return;
                }
                if (used->second.remote != buttons) replay_from(frame);
                else confirm_history();
            }
            return;
        }
        if (message.kind == wire::Kind::Digest) {
            if (view.state != FLY_LAN_MVP_RUNNING || message.payload.size() != 40) {
                end(FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            std::array<std::uint8_t, 32> digest{};
            std::memcpy(digest.data(), message.payload.data() + 8, digest.size());
            const auto frame = big_endian_u64(message.payload.data());
            remote_digests[frame] = digest;
            compare_digest(frame);
            return;
        }
        if (message.kind == wire::Kind::End) {
            end(FLY_LAN_MVP_REASON_PEER_ENDED);
            return;
        }
        end(FLY_LAN_MVP_REASON_REJECTED);
    }

    void consume(Event event) {
        const auto found = operations.find(event.operation);
        if (found == operations.end() || view.state == FLY_LAN_MVP_ENDED) return;
        const auto kind = found->second;
        operations.erase(found);
        if (view.state != FLY_LAN_MVP_RUNNING || event.result != FLYNES_QUIC_OK)
            trace("complete", "id=" + std::to_string(event.operation) +
                " op=" + std::to_string(static_cast<unsigned>(kind)) +
                " result=" + std::to_string(event.result) + " size=" + std::to_string(event.bytes.size()));
        if (event.result != FLYNES_QUIC_OK) {
            // Only emit known provider categories; never arbitrary peer-controlled text.
            const std::string category(event.bytes.begin(), event.bytes.end());
            for (const char* safe : {"timeout", "closed", "tls", "reset", "io", "transport"})
                if (category == safe) trace("transport_error", "category=" + category);
            view.transport_result = event.result;
            view.transport_operation = static_cast<std::uint32_t>(kind);
            end(FLY_LAN_MVP_REASON_CONNECTION);
            return;
        }
        switch (kind) {
        case Operation::Material: {
            if (event.resource == 0 || event.bytes.empty()) {
                end(FLY_LAN_MVP_REASON_CONNECTION); return;
            }
            material = event.resource;
            invite.spki_pin = flynes::session::wire::sha256(event.bytes.data(), event.bytes.size());
            const auto address = endpoint(invite);
            (void)submit(Operation::Listen, [this, &address](std::uint64_t op) {
                return flynes_quic_provider_listen(provider, op,
                    reinterpret_cast<const std::uint8_t*>(address.data()), address.size(),
                    material, 30000);
            });
            break;
        }
        case Operation::Listen: {
            listener = event.resource;
            if (listener == 0 || event.bytes.empty()) {
                end(FLY_LAN_MVP_REASON_CONNECTION); return;
            }
            const std::string address(event.bytes.begin(), event.bytes.end());
            const auto colon = address.rfind(':');
            if (colon == std::string::npos) { end(FLY_LAN_MVP_REASON_CONNECTION); return; }
            unsigned port = 0;
            for (std::size_t i = colon + 1; i < address.size(); ++i) {
                if (address[i] < '0' || address[i] > '9') {
                    end(FLY_LAN_MVP_REASON_CONNECTION); return;
                }
                port = port * 10u + static_cast<unsigned>(address[i] - '0');
                if (port > 65535) { end(FLY_LAN_MVP_REASON_CONNECTION); return; }
            }
            if (port == 0) { end(FLY_LAN_MVP_REASON_CONNECTION); return; }
            invite.port = static_cast<std::uint16_t>(port);
            trace("listen_ready", "endpoint=" + endpoint(invite));
            if (!flynes::session::lan_mvp::format_invite(invite, &qr)) {
                end(FLY_LAN_MVP_REASON_CONNECTION); return;
            }
            deadline = std::chrono::steady_clock::now() + kInviteLife;
            (void)submit(Operation::Accept, [this](std::uint64_t op) {
                return flynes_quic_provider_accept(provider, op, listener);
            });
            break;
        }
        case Operation::Accept:
            connection = event.resource;
            if (connection == 0) { end(FLY_LAN_MVP_REASON_CONNECTION); return; }
            (void)submit(Operation::AcceptStream, [this](std::uint64_t op) {
                return flynes_quic_provider_accept_bidi(provider, op, connection);
            });
            break;
        case Operation::Connect:
            connection = event.resource;
            if (connection == 0) { end(FLY_LAN_MVP_REASON_CONNECTION); return; }
            (void)submit(Operation::OpenStream, [this](std::uint64_t op) {
                return flynes_quic_provider_open_bidi(provider, op, connection);
            });
            break;
        case Operation::OpenStream:
        case Operation::AcceptStream:
            if (event.resource == 0 || event.bytes.size() != 8) {
                end(FLY_LAN_MVP_REASON_CONNECTION); return;
            }
            send_stream = event.resource;
            recv_stream = big_endian_u64(event.bytes.data());
            if (role == Role::Guest) {
                const std::vector<std::uint8_t> payload(invite.token.begin(), invite.token.end());
                (void)queue_message(wire::Kind::Join, payload);
            }
            (void)begin_read();
            (void)begin_next_write();
            break;
        case Operation::Write:
            if (!writes.empty()) written_bytes += writes.front().size();
            write_inflight = false;
            if (!writes.empty()) writes.pop_front();
            (void)begin_next_write();
            break;
        case Operation::Read: {
            read_bytes += event.bytes.size();
            read_inflight = false;
            if (event.bytes.empty() || !decoder.push(event.bytes.data(), event.bytes.size())) {
                end(event.bytes.empty() ? FLY_LAN_MVP_REASON_CONNECTION
                                        : FLY_LAN_MVP_REASON_REJECTED);
                return;
            }
            wire::Message message{};
            while (view.state != FLY_LAN_MVP_ENDED && decoder.pop(&message))
                handle_message(message);
            if (!decoder.failed()) (void)begin_read();
            break;
        }
        }
    }

    void pump() {
        const auto now = std::chrono::steady_clock::now();
        const auto gap = std::chrono::duration_cast<std::chrono::milliseconds>(now - previous_pump).count();
        if (gap > 1000 && view.state != FLY_LAN_MVP_ENDED)
            trace("pump_gap", "gap_ms=" + std::to_string(gap));
        previous_pump = now;
        std::vector<Event> work;
        work.swap(events);
        for (auto& event : work) consume(std::move(event));
        if (role == Role::Host && view.state == FLY_LAN_MVP_INVITING && !qr.empty() &&
            std::chrono::steady_clock::now() >= deadline)
            end(FLY_LAN_MVP_REASON_EXPIRED);
        if (view.state == FLY_LAN_MVP_RUNNING && !view.paused &&
            std::chrono::steady_clock::now() - last_progress >= kProgressTimeout)
            end(FLY_LAN_MVP_REASON_STALL);
        sync_view();
        if (last_logged_state != view.state) {
            last_logged_state = view.state;
            trace("state");
        }
    }

    void run() {
        std::unique_lock<std::mutex> lock(mutex);
        while (!worker_stop) {
            pump();
            advance();
            input_dirty = false;
            auto due = std::chrono::steady_clock::now() + std::chrono::milliseconds(5);
            if (view.state == FLY_LAN_MVP_RUNNING && !view.paused &&
                view.completed_frames - confirmed_frames < kPredictionDepth &&
                has_input_state && next_frame_due < due)
                due = next_frame_due;
            wake.wait_until(lock, due, [this] {
                return worker_stop || input_dirty || !events.empty();
            });
        }
    }
};

namespace {
void retain(void* context) {
    auto* session = static_cast<fly_lan_mvp_session*>(context);
    session->references.fetch_add(1, std::memory_order_relaxed);
}
void release(void* context) {
    auto* session = static_cast<fly_lan_mvp_session*>(context);
    if (session->references.fetch_sub(1, std::memory_order_acq_rel) == 1) delete session;
}
void completion(void* context, std::uint64_t operation, std::int32_t result,
                std::uint32_t, std::uint64_t resource, const std::uint8_t* bytes,
                std::size_t size) {
    auto* session = static_cast<fly_lan_mvp_session*>(context);
    Event event{};
    event.operation = operation;
    event.result = result;
    event.resource = resource;
    if (bytes != nullptr && size != 0) event.bytes.assign(bytes, bytes + size);
    std::lock_guard<std::mutex> lock(session->mutex);
    session->events.push_back(std::move(event));
    session->wake.notify_one();
    if (session->view.state != FLY_LAN_MVP_RUNNING || result != FLYNES_QUIC_OK)
        session->trace("callback", "id=" + std::to_string(operation) + " result=" + std::to_string(result));
}
} // namespace

extern "C" fly_lan_mvp_session* fly_lan_mvp_create(void) {
    auto* session = new (std::nothrow) fly_lan_mvp_session;
    if (session == nullptr) return nullptr;
    FlynesQuicCallbacks callbacks{};
    callbacks.struct_size = sizeof(callbacks);
    callbacks.abi_version = FLYNES_QUIC_PROVIDER_ABI_V1;
    callbacks.context = session;
    callbacks.retain = retain;
    callbacks.release = release;
    callbacks.completion = completion;
    session->provider = flynes_quic_provider_create(&callbacks);
    if (session->provider == nullptr) { release(session); return nullptr; }
    try {
        session->worker = std::thread([session] { session->run(); });
    } catch (...) {
        flynes_quic_provider_release(session->provider);
        release(session);
        return nullptr;
    }
    return session;
}

extern "C" void fly_lan_mvp_set_diagnostic_sink(fly_lan_mvp_session* session,
        fly_lan_mvp_diagnostic_sink sink, void* context) {
    if (!session) return;
    std::lock_guard<std::mutex> lock(session->mutex);
    session->diagnostic_sink = sink;
    session->diagnostic_context = context;
}

extern "C" int fly_lan_mvp_host(fly_lan_mvp_session* session, const char* host_ipv4,
                                  const std::uint8_t* token16) {
    if (session == nullptr || host_ipv4 == nullptr || token16 == nullptr) return 0;
    std::array<std::uint8_t, 4> ip{};
    if (!flynes::session::lan_mvp::parse_lan_ipv4(host_ipv4, &ip)) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->view.state != FLY_LAN_MVP_IDLE) return 0;
    session->role = Role::Host;
    session->invite.ipv4 = ip;
    session->invite.port = 0;
    std::memcpy(session->invite.token.data(), token16, 16);
    session->view.state = FLY_LAN_MVP_INVITING;
    session->sync_view();
    session->trace("host", std::string("bind=") + host_ipv4);
    return session->submit(Operation::Material, [session](std::uint64_t op) {
        return flynes_quic_provider_generate_self_signed(session->provider, op);
    }) ? 1 : 0;
}

extern "C" int fly_lan_mvp_join(fly_lan_mvp_session* session, const char* local_ipv4,
                                  const char* qr_text, std::size_t qr_size) {
    if (session == nullptr || local_ipv4 == nullptr || qr_text == nullptr) return 0;
    Invite invite{};
    if (!flynes::session::lan_mvp::parse_invite(std::string_view(qr_text, qr_size), &invite))
        return 0;
    std::array<std::uint8_t, 4> local_ip{};
    if (!flynes::session::lan_mvp::parse_lan_ipv4(local_ipv4, &local_ip)) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->view.state != FLY_LAN_MVP_IDLE) return 0;
    session->role = Role::Guest;
    session->invite = invite;
    session->view.state = FLY_LAN_MVP_JOINING;
    session->sync_view();
    const auto address = endpoint(invite);
    Invite local{};
    local.ipv4 = local_ip;
    const auto bind = endpoint(local);
    session->trace("join", "bind=" + bind + " peer=" + address);
    return session->submit(Operation::Connect, [session, &address, &bind](std::uint64_t op) {
        return flynes_quic_provider_connect(session->provider, op,
            reinterpret_cast<const std::uint8_t*>(bind.data()), bind.size(),
            reinterpret_cast<const std::uint8_t*>(address.data()), address.size(),
            session->invite.spki_pin.data(), session->invite.spki_pin.size(), 10000);
    }) ? 1 : 0;
}

extern "C" std::size_t fly_lan_mvp_copy_invite(fly_lan_mvp_session* session, char* out,
                                                  std::size_t capacity) {
    if (session == nullptr) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->qr.empty() || session->view.state != FLY_LAN_MVP_INVITING) return 0;
    const auto needed = session->qr.size() + 1;
    if (out != nullptr && capacity >= needed) std::memcpy(out, session->qr.c_str(), needed);
    return needed;
}

extern "C" int fly_lan_mvp_snapshot_read(fly_lan_mvp_session* session,
                                            fly_lan_mvp_snapshot* out) {
    if (session == nullptr || out == nullptr) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    *out = session->view;
    return 1;
}

extern "C" int fly_lan_mvp_copy_peer_config_hash_v1(fly_lan_mvp_session* session,
                                                       std::uint8_t out[32]) {
    if (session == nullptr || out == nullptr) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (!session->peer_configured) return 0;
    std::memcpy(out, session->remote_config_hash.data(), 32);
    return 1;
}

extern "C" int fly_lan_mvp_stats_read(fly_lan_mvp_session* session,
                                        fly_lan_mvp_stats_v1* out) {
    if (session == nullptr || out == nullptr ||
        out->struct_size < FLY_LAN_MVP_STATS_V1_SIZE ||
        out->version != FLY_LAN_MVP_STATS_VERSION_1) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    *out = session->stats;
    out->struct_size = FLY_LAN_MVP_STATS_V1_SIZE;
    out->version = FLY_LAN_MVP_STATS_VERSION_1;
    return 1;
}

extern "C" int fly_lan_mvp_source_timing(fly_lan_mvp_session* session,
                                            fly_runtime_source_timing_v1* out) {
    if (session == nullptr || out == nullptr) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    return session->runtime != nullptr &&
           fly_runtime_get_source_timing(session->runtime, out) == FLY_RESULT_OK ? 1 : 0;
}

extern "C" int fly_lan_mvp_select_rom(fly_lan_mvp_session* session,
                                         const std::uint8_t* bytes, std::size_t size) {
    return fly_lan_mvp_select_game(session, bytes, size, "");
}

extern "C" int fly_lan_mvp_select_game(fly_lan_mvp_session* session,
    const std::uint8_t* bytes, std::size_t size, const char* game_key) {
    if (session == nullptr || bytes == nullptr || size == 0) return 0;
    if (!game_key || std::strlen(game_key) >= sizeof(session->view.peer_game_key)) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->view.state != FLY_LAN_MVP_LOBBY &&
        session->view.state != FLY_LAN_MVP_CONFIGURING) return 0;
    fly_runtime_config config{};
    config.struct_size = FLY_RUNTIME_CONFIG_V1_SIZE;
    config.version = FLY_RUNTIME_CONFIG_VERSION_1;
    fly_runtime_t* candidate = nullptr;
    if (fly_runtime_create(&config, &candidate) != FLY_RESULT_OK || candidate == nullptr)
        return 0;
    const auto rom_hash = flynes::session::wire::sha256(bytes, size);
    if (fly_runtime_load_rom_fresh(candidate, bytes, size, rom_hash.data()) != FLY_RESULT_OK) {
        fly_runtime_destroy(candidate);
        session->view.reason = FLY_LAN_MVP_REASON_ROM_INVALID;
        return 0;
    }
    fly_runtime_source_timing_v1 timing{};
    timing.struct_size = FLY_RUNTIME_SOURCE_TIMING_V1_SIZE;
    timing.version = FLY_RUNTIME_SOURCE_TIMING_VERSION_1;
    if (fly_runtime_get_source_timing(candidate, &timing) != FLY_RESULT_OK) {
        fly_runtime_destroy(candidate);
        session->view.reason = FLY_LAN_MVP_REASON_ROM_INVALID;
        return 0;
    }
    const auto config_hash = make_config_hash(rom_hash, timing);
    if (session->peer_configured &&
        !same_bytes(rom_hash.data(), session->remote_rom_hash.data(), rom_hash.size())) {
        fly_runtime_destroy(candidate);
        session->view.reason = FLY_LAN_MVP_REASON_ROM_MISMATCH;
        return 0;
    }
    if (session->peer_configured &&
        !same_bytes(config_hash.data(), session->remote_config_hash.data(), config_hash.size())) {
        fly_runtime_destroy(candidate);
        session->view.reason = FLY_LAN_MVP_REASON_CONFIG_MISMATCH;
        return 0;
    }
    if (session->runtime != nullptr) fly_runtime_destroy(session->runtime);
    session->runtime = candidate;
    session->local_rom_hash = rom_hash;
    session->local_config_hash = config_hash;
    session->local_configured = true;
    session->local_ready = false;
    // A matching peer may have sent READY before this device finished loading its ROM.
    // Its confirmation remains valid for the same config hash.
    session->view.reason = FLY_LAN_MVP_REASON_NONE;
    session->view.state = FLY_LAN_MVP_CONFIGURING;
    std::vector<std::uint8_t> payload(rom_hash.begin(), rom_hash.end());
    payload.insert(payload.end(), config_hash.begin(), config_hash.end());
    payload.insert(payload.end(), game_key, game_key + std::strlen(game_key));
    session->sync_view();
    return session->queue_message(wire::Kind::Config, payload) ? 1 : 0;
}

extern "C" int fly_lan_mvp_confirm(fly_lan_mvp_session* session) {
    if (session == nullptr) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->view.state != FLY_LAN_MVP_CONFIGURING ||
        !session->local_configured || session->runtime == nullptr) return 0;
    if (session->local_ready) return 1;
    session->local_ready = true;
    const std::vector<std::uint8_t> payload(session->local_config_hash.begin(),
                                            session->local_config_hash.end());
    const bool sent = session->queue_message(wire::Kind::Ready, payload);
    session->maybe_start_host();
    session->sync_view();
    return sent ? 1 : 0;
}

extern "C" int fly_lan_mvp_submit_input_v1(fly_lan_mvp_session* session,
                                             const fly_lan_mvp_input_v1* input) {
    if (session == nullptr || input == nullptr ||
        input->struct_size < FLY_LAN_MVP_INPUT_V1_SIZE ||
        input->version != FLY_LAN_MVP_INPUT_VERSION_1 || input->reserved != 0) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->view.state != FLY_LAN_MVP_RUNNING || session->view.paused) return 0;
    const bool changed = input->buttons != session->current_local_buttons;
    // Complete states preserve ordering (including releases and direction
    // changes). Reserve the final slot for all-up; held refreshes use no slots.
    const auto limit = input->buttons == 0 ? kLocalInputCapacity : kLocalInputCapacity - 1;
    if (changed && session->pending_local_inputs.size() >= limit) {
        session->trace("input_rejected", "reason=state_queue_full buttons=" +
            std::to_string(input->buttons) + " queued=" +
            std::to_string(session->pending_local_inputs.size()));
        return 0;
    }
    const auto submitted_ns = monotonic_ns();
    session->current_local_buttons = input->buttons;
    session->current_local_capture_time_ns = input->capture_time_ns == 0
        ? submitted_ns : input->capture_time_ns;
    session->current_local_sequence = input->sequence == 0
        ? ++session->next_local_sequence : input->sequence;
    session->next_local_sequence = std::max(session->next_local_sequence,
                                             session->current_local_sequence);
    if (changed) session->pending_local_inputs.push_back({input->buttons,
        session->current_local_sequence, session->current_local_capture_time_ns});
    session->has_input_state = true;
    session->stats.last_input_submit_ns = submitted_ns;
    if (input->buttons != session->last_submitted_buttons) {
        session->trace("input_submit", "input_frame=" +
            std::to_string(session->view.completed_frames) +
            " buttons=" + std::to_string(input->buttons));
        session->last_submitted_buttons = input->buttons;
    }
    session->input_dirty = true;
    session->wake.notify_one();
    return 1;
}

extern "C" int fly_lan_mvp_submit_input(fly_lan_mvp_session* session,
                                          std::uint32_t buttons) {
    fly_lan_mvp_input_v1 input{};
    input.struct_size = FLY_LAN_MVP_INPUT_V1_SIZE;
    input.version = FLY_LAN_MVP_INPUT_VERSION_1;
    input.buttons = buttons;
    return fly_lan_mvp_submit_input_v1(session, &input);
}

extern "C" int fly_lan_mvp_set_paused(fly_lan_mvp_session* session, int paused) {
    if (!session) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->view.state != FLY_LAN_MVP_RUNNING) return 0;
    const auto previous = session->pause;
    const auto outgoing = session->pause.set_local(paused != 0, session->role == Role::Host);
    session->view.paused = session->pause.paused();
    if (!session->queue_message(wire::Kind::Pause,
            {static_cast<std::uint8_t>(outgoing != 0)})) {
        session->pause = previous;
        session->view.paused = session->pause.paused();
        return 0;
    }
    session->last_progress = std::chrono::steady_clock::now();
    if (session->view.paused) session->clear_pending_input();
    if (!session->view.paused) session->wake.notify_one();
    return 1;
}
extern "C" int fly_lan_mvp_resume_game(fly_lan_mvp_session* session) {
    if (!session) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->view.state != FLY_LAN_MVP_RUNNING || session->pause.resume_pending) return 0;
    if (!session->queue_message(wire::Kind::Pause, {2})) return 0;
    (void)session->pause.resume();
    session->view.paused = session->pause.paused();
    session->last_progress = std::chrono::steady_clock::now();
    session->wake.notify_one();
    return 1;
}

extern "C" int fly_lan_mvp_return_lobby(fly_lan_mvp_session* session) {
    if (!session) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    return session->return_lobby() ? 1 : 0;
}

extern "C" int fly_lan_mvp_copy_latest_frame(fly_lan_mvp_session* session,
                                                void* rgb565_out, std::size_t capacity,
                                                fly_latest_frame_v1* meta_out) {
    if (session == nullptr || rgb565_out == nullptr || meta_out == nullptr ||
        capacity < FLY_RUNTIME_RGB565_BYTES || meta_out->struct_size < FLY_LATEST_FRAME_V1_SIZE ||
        meta_out->version != FLY_LATEST_FRAME_VERSION_1) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (!session->has_published_frame) return 0;
    if (session->last_read_publication_sequence == session->publication_sequence)
        ++session->stats.repeated_frame_reads;
    session->last_read_publication_sequence = session->publication_sequence;
    std::memcpy(rgb565_out, session->published_frame.data(), FLY_RUNTIME_RGB565_BYTES);
    std::memcpy(meta_out, &session->published_meta, sizeof(session->published_meta));
    return 1;
}

extern "C" int fly_lan_mvp_pull_pcm(fly_lan_mvp_session* session,
                                      std::int16_t* samples_out,
                                      std::uint32_t sample_capacity,
                                      fly_pcm_block_v1* block_out) {
    if (session == nullptr || samples_out == nullptr || block_out == nullptr || sample_capacity == 0 ||
        block_out->struct_size < FLY_PCM_BLOCK_V1_SIZE || block_out->version != FLY_PCM_BLOCK_VERSION_1) return 0;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->runtime == nullptr) return 0;
    if (session->pcm_queue.empty()) {
        block_out->sample_count = 0;
        block_out->first_sample_sequence = session->pcm_consumed;
        block_out->media_time_ns = 0;
        return 1;
    }
    const auto count = std::min<std::size_t>(session->pcm_queue.size(), sample_capacity);
    block_out->first_sample_sequence = session->pcm_consumed;
    block_out->sample_count = static_cast<std::uint32_t>(count);
    block_out->media_time_ns = session->sample_rate == 0 ? 0 :
        session->pcm_consumed * 1'000'000'000ull / session->sample_rate;
    for (std::size_t index = 0; index < count; ++index) {
        samples_out[index] = session->pcm_queue.front();
        session->pcm_queue.pop_front();
    }
    session->pcm_consumed += count;
    session->stats.pcm_delivered_samples += count;
    return 1;
}

extern "C" void fly_lan_mvp_cancel(fly_lan_mvp_session* session) {
    if (session == nullptr) return;
    std::lock_guard<std::mutex> lock(session->mutex);
    session->end(FLY_LAN_MVP_REASON_CANCELLED);
}

extern "C" void fly_lan_mvp_destroy(fly_lan_mvp_session* session) {
    if (session == nullptr) return;
    fly_lan_mvp_cancel(session);
    {
        std::lock_guard<std::mutex> lock(session->mutex);
        session->worker_stop = true;
        session->wake.notify_one();
    }
    if (session->worker.joinable()) session->worker.join();
    flynes_quic_provider_release(session->provider);
    release(session);
}
