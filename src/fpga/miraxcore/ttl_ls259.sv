//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : ttl_ls259.sv
// Summary  : 74LS259 8-bit addressable latch  (board ref R10, "mainlatch")
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
//     [SRC:DS] 74LS259 addressable-latch behaviour
//     [SRC:MAME] bit assignment Q0/Q1/Q2/Q6/Q7
//   Known issues / notes:
//     /CLR is asynchronous on the real chip; modelled synchronously.
//----------------------------------------------------------------------------
// Status: VALIDATED vs MAME / board check pending . Confidence: HIGH
// Open hypotheses: none
//============================================================================
// DESCRIPTION
//  Faithful model of the addressable latch the CT805-3 uses at 0xF500-0xF507.
//  Writing to address offset A[2:0] with data bit D0 sets latch bit A to D0.
//  On the real chip /CLR is asynchronous; here we reset synchronously.
//
//  Bit map (from MAME + board R10):
//    Q0 -> coin counter 0
//    Q1 -> NMI mask (enables vblank NMI to main Z80)
//    Q2 -> coin counter 1  (only used by miraxa/miraxb)
//    Q6 -> flip screen X
//    Q7 -> flip screen Y
//    Q3..Q5 -> unused on this board
//============================================================================
`default_nettype none

module ttl_ls259
(
    input  wire        clk,
    input  wire        rst,       // async /CLR modelled synchronous
    input  wire        g_n,       // enable (active low): assert during the write strobe
    input  wire [2:0]  a,         // address lines (= CPU A2..A0 of 0xF500 block)
    input  wire        d,         // data (= CPU D0)
    output reg  [7:0]  q
);
    always @(posedge clk) begin
        if (rst)
            q <= 8'h00;
        else if (!g_n)
            q[a] <= d;
    end
endmodule

`default_nettype wire
