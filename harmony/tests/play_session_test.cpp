#include "play_session.hpp"
#include "../../shared/tests/fixtures/battery_counter_rom.hpp"

#include <nes/nes.h>

#include <cstdlib>
#include <exception>
#include <fstream>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

namespace {

int failures = 0;

void expect(bool condition, std::string_view message)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

template <typename Function>
std::string capture_error(Function&& function)
{
    try
    {
        function();
    }
    catch (const std::exception& error)
    {
        return error.what();
    }
    catch (...)
    {
        return "non-standard exception";
    }

    return {};
}

std::vector<std::uint8_t> read_rom(const char* path)
{
    std::ifstream input(path, std::ios::binary);
    if (!input)
    {
        return {};
    }
    input.seekg(0, std::ios::end);
    const std::streamoff size = input.tellg();
    if (size <= 0)
    {
        return {};
    }
    input.seekg(0, std::ios::beg);
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
    input.read(reinterpret_cast<char*>(bytes.data()), size);
    if (!input)
    {
        return {};
    }
    return bytes;
}

bool pixels_equal(const std::vector<std::uint8_t>& left, const std::vector<std::uint8_t>& right)
{
    return left == right;
}

bool pixels_are_uniform(const std::vector<std::uint8_t>& pixels)
{
    if (pixels.size() < 2)
    {
        return true;
    }
    for (std::size_t index = 1; index < pixels.size(); ++index)
    {
        if (pixels[index] != pixels[0])
        {
            return false;
        }
    }
    return true;
}

void test_empty_rom_is_rejected()
{
    const std::string message = capture_error([] {
        (void)flynes::harmony::PlaySession::open(nullptr, 0);
    });
    expect(message.find("validate rom") != std::string::npos,
           "empty ROM must identify its validation step");
    expect(message.find("fly_result=") != std::string::npos,
           "validation failure must include the fly_result code");
}

void test_step_publishes_complete_frame_pcm_and_port0_buttons()
{
    const std::vector<std::uint8_t> rom = read_rom(FLYNES_HARMONY_RUNTIME_ROM_FIXTURE);
    expect(!rom.empty(), "thwaite.nes fixture is readable");
    if (rom.empty())
    {
        return;
    }

    auto session = flynes::harmony::PlaySession::open(rom.data(), rom.size());
    expect(session != nullptr, "open must return a session");
    if (session == nullptr)
    {
        return;
    }

    session->set_port0_buttons(NES_BTN_START);
    const flynes::harmony::PlayStepResult first = session->step();
    expect(first.frame_index == 0, "first stepped frame index must be 0");
    expect(first.width == 256, "frame width must be 256");
    expect(first.height == 240, "frame height must be 240");
    expect(first.format == 1, "frame format must be RGB565");
    expect(first.bytes_written == 122880, "frame must be a complete 256x240 RGB565 buffer");
    expect(first.rgb565.size() == 122880, "rgb565 payload size must match bytes_written");
    expect(first.pcm_sample_count != 0, "step must publish PCM samples");
    expect(first.pcm.size() == first.pcm_sample_count, "pcm payload size must match sample count");
    expect(first.applied_buttons == NES_BTN_START, "port-0 START must be applied");
    expect(!pixels_are_uniform(first.rgb565), "published frame must not be a uniform fill");

    const flynes::harmony::PlayStepResult second = session->step();
    expect(second.frame_index == 1, "second stepped frame index must be 1");
}

void test_checkpoint_restores_pixels_after_later_frames()
{
    const std::vector<std::uint8_t> rom = read_rom(FLYNES_HARMONY_RUNTIME_ROM_FIXTURE);
    expect(!rom.empty(), "thwaite.nes fixture is readable");
    if (rom.empty())
    {
        return;
    }

    auto session = flynes::harmony::PlaySession::open(rom.data(), rom.size());
    if (session == nullptr)
    {
        expect(false, "open must return a session");
        return;
    }

    flynes::harmony::PlayStepResult latest{};
    for (int index = 0; index < 30; ++index)
    {
        latest = session->step();
    }
    const std::vector<std::uint8_t> saved_pixels = latest.rgb565;
    const std::vector<std::uint8_t> checkpoint = session->save_checkpoint();
    expect(!checkpoint.empty(), "checkpoint must contain bytes");

    for (int index = 0; index < 30; ++index)
    {
        latest = session->step();
    }
    const std::vector<std::uint8_t> later_checkpoint = session->save_checkpoint();
    expect(later_checkpoint != checkpoint, "later frames must advance checkpoint bytes");

    session->load_checkpoint(checkpoint.data(), checkpoint.size());
    const flynes::harmony::PlayStepResult restored = session->copy_latest_frame();
    expect(pixels_equal(restored.rgb565, saved_pixels),
           "load_checkpoint must restore the saved picture");

    const flynes::harmony::PlayStepResult continued = session->step();
    expect(continued.frame_index == 30, "resume after load must keep the saved timeline");
}

void test_restart_preserves_battery_progress()
{
    const auto rom = battery_counter_rom();
    auto session = flynes::harmony::PlaySession::open(rom.data(), rom.size());
    flynes::harmony::PlayStepResult first;
    std::vector<std::uint32_t> first_counts;
    for (int frame = 0; frame < 20; ++frame) {
        first = session->step();
        if (frame > 0) first_counts.push_back(first.pcm_sample_count);
    }
    session->set_port0_buttons(NES_BTN_START);
    session->restart();
    const auto restarted = session->copy_latest_frame();
    expect(restarted.frame_index == 0, "cold restart publishes first frame on a new core timeline");
    expect(restarted.applied_buttons == 0, "cold restart clears held input");
    const auto second_frame = session->step();
    std::vector<std::uint32_t> restarted_counts{second_frame.pcm_sample_count};
    flynes::harmony::PlayStepResult second = restarted;
    for (int frame = 2; frame < 20; ++frame) {
        second = session->step();
        restarted_counts.push_back(second.pcm_sample_count);
    }
    expect(restarted_counts == first_counts,
           "cold restart replays the startup PCM cadence without an old fractional phase");
    expect(second.rgb565 != first.rgb565,
           "cold restart retains battery counter and increments it, instead of rewinding SRAM");
    auto fresh = flynes::harmony::PlaySession::open(rom.data(), rom.size());
    flynes::harmony::PlayStepResult clean;
    (void)fresh->step();
    const auto fresh_second = fresh->step();
    expect(second_frame.pcm_sample_count == fresh_second.pcm_sample_count,
           "cold restart resets fractional audio cadence to the startup clock");
    for (int frame = 2; frame < 20; ++frame) clean = fresh->step();
    expect(clean.rgb565 == first.rgb565, "battery fixture has a deterministic fresh cartridge baseline");
}

} // namespace

int main()
{
    std::uint32_t observed = 0;
    auto external = flynes::harmony::PlaySession::from_frame_source(
        [&](std::uint32_t buttons) {
            observed = buttons;
            flynes::harmony::PlayStepResult frame{};
            frame.rgb565 = {1, 2};
            frame.pcm = {123, -456};
            return frame;
        });
    external->set_port0_buttons(0x89);
    flynes::harmony::PlayStepResult external_frame{};
    (void)capture_error([&] { external_frame = external->step(); });
    expect(observed == 0x89, "existing play session forwards local controls to the external session");
    expect(external_frame.rgb565 == std::vector<std::uint8_t>({1, 2}) &&
           external_frame.pcm == std::vector<std::int16_t>({123, -456}),
           "existing play runtime receives external picture AND speaker PCM");
    test_empty_rom_is_rejected();
    test_step_publishes_complete_frame_pcm_and_port0_buttons();
    test_checkpoint_restores_pixels_after_later_frames();
    test_restart_preserves_battery_progress();

    if (failures != 0)
    {
        std::cerr << failures << " failure(s)\n";
        return EXIT_FAILURE;
    }

    std::cout << "PASS: Harmony play session contract\n";
    return EXIT_SUCCESS;
}
