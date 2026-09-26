//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_decrypt.sv
// Summary  : Main-CPU program descrambler ("ORIGINAL SEAL" module)
// Board    : CURRENT CT805-3 (MAME set: miraxa)
// Created  : see git history
// Revised  : 2026-09-26
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License v3 or later. It is
// distributed WITHOUT ANY WARRANTY. See LICENSE or
// <https://www.gnu.org/licenses/gpl-3.0.html> for the full text.
//----------------------------------------------------------------------------
// EXPERIMENTAL CORE - AI-ASSISTED DEVELOPMENT
//
// Human author : Javier (RndMnkIII)
//   - Project direction, fidelity criteria and final decisions
//   - PCB photography, measurements and verification on real hardware
//   - Review, correction and acceptance of all RTL
//
// AI assistant : Claude (Anthropic), model claude-opus-5-5
//   - Registration of both PCB sides and trace following
//   - Hardware hypotheses ([HYP:AI])
//   - Draft RTL, helper scripts and documentation
//
// AI contributions are treated as hypotheses until verified on the board.
// Tag conventions and hypothesis log: doc/hypotheses.md
//----------------------------------------------------------------------------
// HYPOTHESES
//   Open:
//     H-004 [HYP]     The white potted "ORIGINAL SEAL" block is the main-CPU decryption
//                     module and is purely combinational (not opened / not traced).
//     H-013 [HYP]     Third PROM (MAME 'mirax.prm', NO_DUMP): mirax_top says CT805-3 has
//                     none, mirax_decrypt says it may encode the scheme. CONFLICT.
//   Sources:
//     [SRC:MAME] init_mirax address/data bitswaps (verified against ROM CRCs)
//----------------------------------------------------------------------------
// Status: UNDER VALIDATION . Confidence: HIGH (algorithm) / LOW (hardware form)
// Open hypotheses: H-004, H-013
//============================================================================
// DESCRIPTION
//  On the real CT805-3 board the main Z80 program passes through the white
//  epoxy-potted "ORIGINAL SEAL / CURRENT TECHNOLOGY / serial 1797" module.
//  That module is a fixed COMBINATIONAL bus interposer: it permutes a few of
//  the address lines feeding the program EPROMs and permutes+inverts the data
//  lines coming back. No clock, no state - exactly like the potted logic.
//
//  The program EPROMs are stored ENCRYPTED (byte-identical to the original
//  dumps, region "data_code"); descrambling happens on the bus, so the ROM
//  images you burn/verify still match the MAME CRC/SHA1.
//
//  Reference algorithm (MAME misc/mirax.cpp, init_mirax), reformulated as a
//  live interposer instead of a one-shot table build:
//
//    MAME:  ROM[bitswap16(i, 15..9, 5,7,6,8, 4,3,2,1,0)] = f(DATA[i])
//
//  * Address: the permutation touches only address bits {5,6,7,8}, mapping the
//    ordered inputs (8,7,6,5) to (5,7,6,8) -> i.e. it SWAPS bit5 and bit8 and
//    leaves 6,7 in place. That is an INVOLUTION, so to fetch the decrypted byte
//    the CPU wants at address A we simply read the EPROM at A with A5<->A8
//    swapped.
//
//  * Data: permutation + XOR 0xFF, two variants chosen by the 16 KB bank (the
//    A5/A8 swap never crosses a 16 KB boundary, so decrypted-A[15:14] selects
//    the bank cleanly):
//        bank 0  (0x0000-0x3FFF) : bitswap8(e, 1,3,7,0,5,6,4,2) ^ FF
//        bank 1  (0x4000-0x7FFF) : bitswap8(e, 2,1,0,6,7,5,3,4) ^ FF
//        bank 2  (0x8000-0xBFFF) : bitswap8(e, 1,3,7,0,5,6,4,2) ^ FF
//
//  OPEN FIDELITY ITEM: the 3rd small PROM on the board (MAME "mirax.prm",
//  NO_DUMP) is suspected to encode this very scheme. If you dump it off your
//  CT805-3, cross-check these constants against it.
//============================================================================
`default_nettype none

module mirax_decrypt
(
    input  wire [15:0] cpu_addr,     // address the Z80 core drives (0x0000-0xBFFF)
    output wire [15:0] eprom_addr,   // scrambled address into the program EPROMs
    input  wire [ 7:0] eprom_data,   // raw (encrypted) byte from the EPROMs
    output wire [ 7:0] cpu_data      // decrypted byte back to the Z80 core
);
    // ---- address: swap A5 <-> A8, everything else straight through ----------
    // [SRC:MAME] init_mirax ; [HYP H-004] physical form = potted module
    assign eprom_addr = { cpu_addr[15:9],
                          cpu_addr[5],       // -> A8
                          cpu_addr[7:6],     //    A7,A6
                          cpu_addr[8],       // -> A5
                          cpu_addr[4:0] };

    // ---- data: two fixed pin permutations, then invert ----------------------
    // {MSB..LSB} = source bit indices
    wire [7:0] dec_a = { eprom_data[1], eprom_data[3], eprom_data[7], eprom_data[0],
                         eprom_data[5], eprom_data[6], eprom_data[4], eprom_data[2] } ^ 8'hFF;

    wire [7:0] dec_b = { eprom_data[2], eprom_data[1], eprom_data[0], eprom_data[6],
                         eprom_data[7], eprom_data[5], eprom_data[3], eprom_data[4] } ^ 8'hFF;

    // bank select on decrypted A[15:14]: 00->A, 01->B, 10->A
    assign cpu_data = (cpu_addr[15:14] == 2'b01) ? dec_b : dec_a;
endmodule

`default_nettype wire
