#pragma once

#include <algorithm>
#include <cstdint>
#include <vector>

// Synthetic NROM: initialize battery RAM once, increment it on each CPU reset,
// and continuously show that counter as the universal background palette color.
// The observable picture distinguishes cold reset from restoring a snapshot or
// replacing the cartridge with a fresh core that discards battery RAM.
inline std::vector<std::uint8_t> battery_counter_rom()
{
    std::vector<std::uint8_t> rom(16 + 16384 + 8192, 0);
    rom[0] = 'N'; rom[1] = 'E'; rom[2] = 'S'; rom[3] = 0x1a;
    rom[4] = 1; rom[5] = 1; rom[6] = 2; rom[8] = 1;
    const std::uint8_t program[] = {
        0x78, 0xd8,                         // SEI; CLD
        0xad, 0x01, 0x60, 0xc9, 0xa5,       // LDA $6001; CMP #$a5
        0xf0, 0x0a,                         // BEQ initialized
        0xa9, 0xa5, 0x8d, 0x01, 0x60,       // magic marker
        0xa9, 0x00, 0x8d, 0x00, 0x60,       // initial counter
        0xee, 0x00, 0x60,                   // INC $6000
        0x2c, 0x02, 0x20,                   // loop: BIT $2002
        0xa9, 0x3f, 0x8d, 0x06, 0x20,
        0xa9, 0x00, 0x8d, 0x06, 0x20,       // PPU address $3f00
        0xad, 0x00, 0x60, 0x29, 0x0f,
        0x8d, 0x07, 0x20,                   // battery counter -> palette
        0xa9, 0x00, 0x8d, 0x06, 0x20,
        0x8d, 0x06, 0x20,                   // PPU address $0000
        0x4c, 0x16, 0x80                    // JMP loop
    };
    std::copy(std::begin(program), std::end(program), rom.begin() + 16);
    for (std::size_t vector = 0x3ffa; vector <= 0x3ffe; vector += 2)
        rom[16 + vector + 1] = 0x80;
    return rom;
}
