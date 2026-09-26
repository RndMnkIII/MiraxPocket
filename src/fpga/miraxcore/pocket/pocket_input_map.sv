//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : pocket_input_map.sv
// Summary  : Analogue Pocket controller -> Mirax P1/P2/DSW
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
//     [SRC:MAME] P1/P2 port bit order; control mapping is a design choice
//----------------------------------------------------------------------------
// Status: STABLE (platform glue) . Confidence: HIGH
// Open hypotheses: none
//============================================================================
// DESCRIPTION
//  Maps the openFPGA standard controller bitfield (cont1_key/cont2_key from the
//  APF bridge) to Mirax's active-HIGH input ports.
//
//  openFPGA cont_key[15:0] standard order:
//    0 dpad-up   1 dpad-down  2 dpad-left  3 dpad-right
//    4 A         5 B          6 X          7 Y
//    8 L1        9 R1        10 L2        11 R2   12 L3  13 R3
//   14 Select   15 Start
//
//  Mirax P1 (0xF000, active HIGH):
//    b0 DOWN  b1 START1  b2 LEFT  b3 RIGHT  b4 BUTTON1  b5 UP  b6 COIN1  b7 COIN2
//  Mirax P2 (0xF100, active HIGH):
//    b0 DOWN  b1 START2  b2 LEFT  b3 RIGHT  b4 BUTTON1  b5 UP  (b6/b7 unused)
//
//  Fire = A or B (either face button). Coin = Select, Start = Start.
//============================================================================
`default_nettype none

module pocket_input_map
(
    input  wire [15:0] cont1_key,
    input  wire [15:0] cont2_key,
    output wire [7:0]  p1,
    output wire [7:0]  p2
);
    // P1 from controller 1
    assign p1[0] = cont1_key[1];               // DOWN
    assign p1[1] = cont1_key[15];              // START1
    assign p1[2] = cont1_key[2];               // LEFT
    assign p1[3] = cont1_key[3];               // RIGHT
    assign p1[4] = cont1_key[4] | cont1_key[5];// BUTTON1 (A or B)
    assign p1[5] = cont1_key[0];               // UP
    assign p1[6] = cont1_key[14];              // COIN1  (Select)
    assign p1[7] = cont2_key[14];              // COIN2  (P2 Select)

    // P2 from controller 2
    assign p2[0] = cont2_key[1];               // DOWN
    assign p2[1] = cont2_key[15];              // START2
    assign p2[2] = cont2_key[2];               // LEFT
    assign p2[3] = cont2_key[3];               // RIGHT
    assign p2[4] = cont2_key[4] | cont2_key[5];// BUTTON1
    assign p2[5] = cont2_key[0];               // UP
    assign p2[6] = 1'b0;
    assign p2[7] = 1'b0;
endmodule

`default_nettype wire
