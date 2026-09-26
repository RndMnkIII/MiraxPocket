//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_clocks.sv
// Summary  : Clock-enable generation from a single 48 MHz domain
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
//     H-001 [HYP]     Every clock is an integer division of the 12 MHz crystal;
//                     pixel clock = 12/2 = 6 MHz. Counter CLK net B9(74S161)<->B10
//                     traced on the solder side; its source (via under B8) is not.
//     H-002 [HYP]     AY-3-8912 clock = 12/4 = 3 MHz (MAME). Some CTI boards use /6 = 2 MHz.
//   Sources:
//     [SRC:PCB X1,M2] 12 MHz crystal + 74LS368 oscillator (traced, CONF:MEDIUM)
//     [SRC:MAME] CPU and AY at 12/4 = 3 MHz; sound IRQ 4x60 Hz
//   Known issues / notes:
//     Header text cites the crystal as 'ref L2'; in the photos it sits between
//     K2 and M2 (next to M2 74LS368). Check the silkscreen reference.
//----------------------------------------------------------------------------
// Status: UNDER VALIDATION . Confidence: LOW
// Open hypotheses: H-001, H-002
//============================================================================
// DESCRIPTION
//  The board runs off a 12.000 MHz crystal (ref L2). Everything is a clean
//  divide of it, so on FPGA we run one fast clock and gate with enables:
//     main/sound Z80 : 12/4 = 3.00 MHz
//     AY-3-8912      : 12/4 = 3.00 MHz  (see open item: possibly /6 = 2 MHz)
//     pixel clock    : ~6 MHz (dot clock; tune HTOTAL to match the monitor)
//  Feed this a 48 MHz clock (12 MHz x4) for exact integer division.
//============================================================================
`default_nettype none

module mirax_clocks
(
    input  wire clk48,
    input  wire rst,
    output reg  ce_12m,
    output reg  ce_6m,     // pixel
    output reg  ce_3m,     // cpu / ay
    output reg  ce_3m180,  // cpu / ay (180 deg phase)
    output reg  ce_240hz   // sound periodic irq tick (4*60)
);
    // [HYP H-001] 6 MHz pixel = 12/2 ; [HYP H-002] AY = 12/4  [VERIFY]
    reg [3:0] div;
    always @(posedge clk48) begin
        if (rst) begin div<=0; ce_12m<=0; ce_6m<=0; ce_3m<=0; end
        else begin
            div <= div + 4'd1;
            ce_12m <= (div[1:0]==2'b00);       // 48/4
            ce_6m  <= (div[2:0]==3'b000);      // 48/8
            ce_3m  <= (div[3:0]==4'b0000);     // 48/16
            ce_3m180 <= (div[3:0]==4'b1000);     // 48/16, 180 deg phase
        end
    end

    // 240 Hz tick: divide 48 MHz by 200000
    reg [17:0] t;
    always @(posedge clk48) begin
        if (rst) begin t<=0; ce_240hz<=0; end
        else begin
            ce_240hz <= 1'b0;
            if (t==18'd199999) begin t<=0; ce_240hz<=1'b1; end
            else t<=t+18'd1;
        end
    end
endmodule

`default_nettype wire
