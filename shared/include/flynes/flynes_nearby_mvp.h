#ifndef FLYNES_NEARBY_MVP_H
#define FLYNES_NEARBY_MVP_H

#include <stddef.h>
#include <stdint.h>

#include <flynes/flynes_runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct fly_lan_mvp_session fly_lan_mvp_session;

enum {
    FLY_LAN_MVP_IDLE = 0,
    FLY_LAN_MVP_INVITING = 1,
    FLY_LAN_MVP_JOINING = 2,
    FLY_LAN_MVP_LOBBY = 3,
    FLY_LAN_MVP_ENDED = 4,
    FLY_LAN_MVP_CONFIGURING = 5,
    FLY_LAN_MVP_RUNNING = 6,
    FLY_LAN_MVP_RETURNING = 7,
};

enum {
    FLY_LAN_MVP_REASON_NONE = 0,
    FLY_LAN_MVP_REASON_INVALID_INVITE = 1,
    FLY_LAN_MVP_REASON_CONNECTION = 2,
    FLY_LAN_MVP_REASON_REJECTED = 3,
    FLY_LAN_MVP_REASON_EXPIRED = 4,
    FLY_LAN_MVP_REASON_CANCELLED = 5,
    FLY_LAN_MVP_REASON_ROM_INVALID = 6,
    FLY_LAN_MVP_REASON_ROM_MISMATCH = 7,
    FLY_LAN_MVP_REASON_CONFIG_MISMATCH = 8,
    FLY_LAN_MVP_REASON_STALL = 9,
    FLY_LAN_MVP_REASON_DESYNC = 10,
    FLY_LAN_MVP_REASON_PEER_ENDED = 11,
};

enum {
    FLY_LAN_MVP_ROLE_NONE = 0,
    FLY_LAN_MVP_ROLE_HOST_P1 = 1,
    FLY_LAN_MVP_ROLE_GUEST_P2 = 2,
};

typedef struct fly_lan_mvp_snapshot {
    uint32_t state;
    uint32_t reason;
    uint8_t session_id[16];
    int32_t transport_result;
    uint32_t transport_operation;
    uint32_t role;
    uint32_t local_configured;
    uint32_t peer_configured;
    uint32_t local_ready;
    uint32_t peer_ready;
    uint64_t completed_frames;
    uint8_t config_hash[32];
    uint64_t last_digest_frame;
    uint8_t last_state_digest[32];
    uint32_t applied_buttons[2]; // P1/P2 of the last completed core frame.
    uint32_t paused;
    char peer_game_key[256]; // Local catalog identity, never a filesystem path.
} fly_lan_mvp_snapshot;

// Process-local monotonic diagnostics. Counters are cumulative for this session;
// timestamps from different devices must never be subtracted.
#define FLY_LAN_MVP_STATS_VERSION_1 1u
typedef struct fly_lan_mvp_stats_v1 {
    uint32_t struct_size;
    uint32_t version;
    uint64_t simulated_frames;
    uint64_t replayed_frames;
    uint64_t predicted_frames;
    uint64_t rollback_count;
    uint64_t published_frames;
    uint64_t repeated_frame_reads;
    uint64_t pcm_generated_samples;
    uint64_t pcm_delivered_samples;
    uint64_t pcm_dropped_samples;
    uint64_t pcm_queue_high_samples;
    uint64_t last_input_submit_ns;
    uint64_t last_remote_receive_ns;
    uint64_t last_core_step_ns;
} fly_lan_mvp_stats_v1;
#define FLY_LAN_MVP_STATS_V1_SIZE ((uint32_t)sizeof(fly_lan_mvp_stats_v1))

fly_lan_mvp_session* fly_lan_mvp_create(void);
// Optional diagnostic sink. Lines contain metadata only, never QR/token/ROM bytes.
// Called under the session lock; must not re-enter any session API. Context must
// remain alive until destroy returns. No per-frame traffic is logged while running.
typedef void (*fly_lan_mvp_diagnostic_sink)(void* context, const char* line);
void fly_lan_mvp_set_diagnostic_sink(fly_lan_mvp_session*,
    fly_lan_mvp_diagnostic_sink, void* context);
// host_ipv4 is the actual reachable interface address. token16 is secure random input.
int fly_lan_mvp_host(fly_lan_mvp_session*, const char* host_ipv4, const uint8_t* token16);
int fly_lan_mvp_join(fly_lan_mvp_session*, const char* local_ipv4,
                     const char* qr_text, size_t qr_size);
// Returns required bytes including NUL; 0 means no active QR. Never log the text.
size_t fly_lan_mvp_copy_invite(fly_lan_mvp_session*, char* out, size_t capacity);
int fly_lan_mvp_snapshot_read(fly_lan_mvp_session*, fly_lan_mvp_snapshot* out);
// Copy the peer's current 32-byte configuration hash without changing snapshot ABI layout.
// Returns 1 only after the peer has supplied a configuration.
int fly_lan_mvp_copy_peer_config_hash_v1(fly_lan_mvp_session*, uint8_t out[32]);
int fly_lan_mvp_stats_read(fly_lan_mvp_session*, fly_lan_mvp_stats_v1* out);
// Reads the loaded game's actual source cadence without advancing the session.
// Returns 0 before local ROM selection or for an invalid timing structure.
int fly_lan_mvp_source_timing(fly_lan_mvp_session*, fly_runtime_source_timing_v1* out);
int fly_lan_mvp_select_rom(fly_lan_mvp_session*, const uint8_t* bytes, size_t size);
int fly_lan_mvp_select_game(fly_lan_mvp_session*, const uint8_t* bytes, size_t size, const char* game_key);
int fly_lan_mvp_confirm(fly_lan_mvp_session*);
int fly_lan_mvp_set_paused(fly_lan_mvp_session*, int paused);
int fly_lan_mvp_return_lobby(fly_lan_mvp_session*);
// capture_time_ns uses this process's monotonic clock. A zero timestamp means
// "capture at submission"; sequence zero requests an assigned local sequence.
// Neither value is sent to the peer or subtracted from a remote clock.
#define FLY_LAN_MVP_INPUT_VERSION_1 1u
typedef struct fly_lan_mvp_input_v1 {
    uint32_t struct_size;
    uint32_t version;
    uint32_t buttons;
    uint32_t reserved;
    uint64_t sequence;
    uint64_t capture_time_ns;
} fly_lan_mvp_input_v1;
#define FLY_LAN_MVP_INPUT_V1_SIZE ((uint32_t)sizeof(fly_lan_mvp_input_v1))
int fly_lan_mvp_submit_input_v1(fly_lan_mvp_session*, const fly_lan_mvp_input_v1* input);
// Legacy callers are timestamped at this function boundary.
int fly_lan_mvp_submit_input(fly_lan_mvp_session*, uint32_t buttons);
int fly_lan_mvp_copy_latest_frame(fly_lan_mvp_session*, void* rgb565_out,
                                  size_t capacity, fly_latest_frame_v1* meta_out);
int fly_lan_mvp_pull_pcm(fly_lan_mvp_session*, int16_t* samples_out,
                         uint32_t sample_capacity, fly_pcm_block_v1* block_out);
void fly_lan_mvp_cancel(fly_lan_mvp_session*);
void fly_lan_mvp_destroy(fly_lan_mvp_session*);

#ifdef __cplusplus
}
#endif
#endif
