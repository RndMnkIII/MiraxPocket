//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : dpram.sv
// Summary  : generic synchronous dual-port RAM (block-RAM inferred)
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
//     FPGA abstraction of the discrete SRAMs; no board behaviour modelled
//----------------------------------------------------------------------------
// Status: STABLE (FPGA infrastructure) . Confidence: N/A
// Open hypotheses: none
//============================================================================
// DESCRIPTION
//  Models the many discrete SRAMs (2114/2148/58725/6116/74S201) as BRAM with
//  a CPU port and a video port. Byte-wide.
//============================================================================
`default_nettype none

module dpram #(parameter AW=10, parameter DW=8) (
    input  wire            clk,
    // port A (CPU)
    input  wire [AW-1:0]   a_addr,
    input  wire [DW-1:0]   a_din,
    input  wire            a_we,
    output reg  [DW-1:0]   a_dout,
    // port B (video, read-mostly)
    input  wire [AW-1:0]   b_addr,
    input  wire [DW-1:0]   b_din,
    input  wire            b_we,
    output reg  [DW-1:0]   b_dout
);
    reg [DW-1:0] mem [0:(1<<AW)-1];
    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        a_dout <= mem[a_addr];
    end
    always @(posedge clk) begin
        if (b_we) mem[b_addr] <= b_din;
        b_dout <= mem[b_addr];
    end
endmodule

`default_nettype wire
