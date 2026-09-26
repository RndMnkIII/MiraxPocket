//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : rom_init.sv
// Summary  : ROMs baked into the bitstream (no ioctl load step)
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
//   Open: none
//   Sources:
//     FPGA infrastructure; no board behaviour modelled
//----------------------------------------------------------------------------
// Status: STABLE (FPGA infrastructure) . Confidence: N/A
// Open hypotheses: none
//============================================================================
// DESCRIPTION
//  Each ROM is an inferred block-RAM initialized at synthesis from a .hex file
//  (one 2-digit hex byte per line, as produced by sim/rom_build.py). Quartus
//  turns the initial $readmemh into the M9K/M10K power-on contents, so the ROM
//  data ships INSIDE the .rbf bitstream and is present the instant the core
//  loads - no APF data-slot download needed.
//
//  Put the generated .hex files where Quartus can find them (the project dir,
//  or set a search path). Filenames must match the HEX parameter below.
//============================================================================
`default_nettype none

module rom_init_sp #(parameter AW = 16, parameter HEX = "") (
    input  wire            clk,
    input  wire [AW-1:0]   addr,
    output reg  [7:0]      data
);
    (* ramstyle = "no_rw_check" *) reg [7:0] mem [0:(1<<AW)-1];
    initial begin
        if (HEX != "") $readmemh(HEX, mem);
    end
    always @(posedge clk) data <= mem[addr];
endmodule

`default_nettype wire
