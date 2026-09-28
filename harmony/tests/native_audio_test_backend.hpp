#pragma once

// Host link seam for OHAudio and the platform GPU only. NativePlayRuntime,
// PlaySession, PCM support and the NES core are compiled without substitution.
#include <cstdint>
#include <vector>
#include <condition_variable>
#include <mutex>
#include "render_mailbox.hpp"
#include "motion_frame_scheduler.hpp"

struct OH_AudioRendererStruct;
using OH_AudioRenderer = OH_AudioRendererStruct;
struct OH_AudioStreamBuilder;
using OH_AudioStream_Result = int;
using OH_AudioRenderer_OnWriteDataCallback = int (*)(OH_AudioRenderer*, void*, void*, std::int32_t);
constexpr int AUDIOSTREAM_SUCCESS = 0;
constexpr int AUDIOSTREAM_TYPE_RENDERER = 1;
constexpr int AUDIOSTREAM_SAMPLE_S16LE = 1;
constexpr int AUDIOSTREAM_ENCODING_TYPE_RAW = 1;
constexpr int AUDIOSTREAM_LATENCY_MODE_FAST = 1;
constexpr int AUDIOSTREAM_LATENCY_MODE_NORMAL = 0;
constexpr int AUDIOSTREAM_USAGE_GAME = 1;
constexpr int AUDIO_DATA_CALLBACK_RESULT_INVALID = -1;
constexpr int AUDIO_DATA_CALLBACK_RESULT_VALID = 0;
int OH_AudioStreamBuilder_Create(OH_AudioStreamBuilder**, int);
int OH_AudioStreamBuilder_Destroy(OH_AudioStreamBuilder*);
int OH_AudioStreamBuilder_SetSamplingRate(OH_AudioStreamBuilder*, int);
int OH_AudioStreamBuilder_SetChannelCount(OH_AudioStreamBuilder*, int);
int OH_AudioStreamBuilder_SetSampleFormat(OH_AudioStreamBuilder*, int);
int OH_AudioStreamBuilder_SetEncodingType(OH_AudioStreamBuilder*, int);
int OH_AudioStreamBuilder_SetLatencyMode(OH_AudioStreamBuilder*, int);
int OH_AudioStreamBuilder_SetRendererInfo(OH_AudioStreamBuilder*, int);
int OH_AudioStreamBuilder_SetFrameSizeInCallback(OH_AudioStreamBuilder*, int);
int OH_AudioStreamBuilder_SetRendererWriteDataCallback(OH_AudioStreamBuilder*, OH_AudioRenderer_OnWriteDataCallback, void*);
int OH_AudioStreamBuilder_GenerateRenderer(OH_AudioStreamBuilder*, OH_AudioRenderer**);
int OH_AudioRenderer_Start(OH_AudioRenderer*);
int OH_AudioRenderer_Pause(OH_AudioRenderer*);
int OH_AudioRenderer_Flush(OH_AudioRenderer*);
int OH_AudioRenderer_Stop(OH_AudioRenderer*);
int OH_AudioRenderer_Release(OH_AudioRenderer*);
int OH_AudioRenderer_GetFrameSizeInCallback(OH_AudioRenderer*, std::int32_t*);
int OH_AudioRenderer_GetSamplingRate(OH_AudioRenderer*, std::int32_t*);
int OH_AudioRenderer_GetChannelCount(OH_AudioRenderer*, std::int32_t*);
int OH_AudioRenderer_GetAudioTimestampInfo(OH_AudioRenderer*, std::int64_t*, std::int64_t*);

namespace flynes::harmony {
struct TestRenderStatus { struct { bool motion_qualified = false; } display; };
struct TestRenderer {
    RenderMailbox mailbox;
    MotionFrameScheduler motion;
    std::mutex gate_mutex;
    std::condition_variable gate_wake;
    bool block = false;
    bool entered = false;
    TestRenderer() { mailbox.create_surface(1, 256, 240); motion.create_surface(1); }
    bool submit_frame(std::uint64_t index, std::uint32_t width, std::uint32_t height,
                      const std::vector<std::uint8_t>& pixels, bool discontinuity = false) {
        {
            std::unique_lock lock(gate_mutex);
            if (block) {
                entered = true;
                gate_wake.notify_all();
                gate_wake.wait(lock, [&] { return !block; });
            }
        }
        const bool accepted = mailbox.submit_source_frame(1, index, width, height, pixels);
        return motion.submit(1, index, width, height, pixels, discontinuity) && accepted;
    }
    TestRenderStatus status() const { return {}; }
};
inline TestRenderer& harmony_renderer() { static TestRenderer renderer; return renderer; }
}
