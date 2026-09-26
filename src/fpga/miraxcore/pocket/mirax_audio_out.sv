//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_audio_out.sv
// Summary  : Output-stage model for the Mirax 2x AY-3-8912 audio
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
//     H-010 [HYP]     Both AY-3-8912 are mixed through identical 1K resistors (equal
//                     weight). Resistors identified in photos; wiring not traced.
//     H-011 [HYP]     Audio output stage (MB3712, ~10uF input coupling, 470pF, no large
//                     shunt cap) inferred from photos; filter corners are estimates.
//   Sources:
//     [SRC:PCB A3] MB3712 power amplifier, VR1, 2200uF output cap (silkscreen)
//   Known issues / notes:
//     Filter corners are approximations, not measured on the board.
//----------------------------------------------------------------------------
// Status: UNDER VALIDATION . Confidence: LOW
// Open hypotheses: H-010, H-011
//============================================================================
// DESCRIPTION
//  Replaces the raw "(sum-512)<<6" in the Pocket wrapper with a small, faithful
//  model of the board's analog output stage:
//
//    [ jt49 log-DAC + 3-ch sum, per chip ]  -> ay_sum  (done upstream)
//        |
//        +--> (1) DC blocker (1-pole high-pass)   == series AC-coupling cap
//        +--> (2) 2-pole low-pass (reconstruction) == board RC / active LPF
//        +--> (3) gain + saturation to signed 16-bit
//
//  All fixed-point, adders/shifts only (no multipliers). Runs at the processing
//  enable `ce` (use ce_3m = 3.000 MHz). Because the LPF band-limits well below
//  the 48 kHz I2S rate, the downstream serializer can sample snd_out directly
//  with no extra anti-alias filtering.
//
//  Corner frequencies (small-alpha approximation):
//    LPF pole  fc ~= f_ce / (2*pi * 2^LPK)     e.g. 3 MHz, LPK=5 -> ~14.9 kHz
//    DC block  fc ~= f_ce / (2*pi * 2^DCK)     e.g. 3 MHz, DCK=16 -> ~7.3 Hz
//
//  Defaults chosen from the CT805-3 board (photo):
//    * Two AY-3-8912 mixed through equal 1K resistors -> ay_sum is already the
//      faithful equal-weight mix (jt49 sums the 3 channels per chip).
//    * Output stage = Fujitsu MB3712 amp. Its ~10uF input coupling cap sets a
//      very low high-pass (a few Hz) -> DCK=16. The only treble rolloff is a
//      470pF at the amp input (tens of kHz) and there is NO large shunt cap at
//      the AY outputs -> the board filters gently, so ONE ~15 kHz pole (POLES=1)
//      matches it. Set POLES=2 / raise LPK only if you want it softer.
//============================================================================
`default_nettype none

module mirax_audio_out #(
    parameter integer FB    = 8,  // internal fractional bits (headroom vs dead-zone)
    parameter integer LPK   = 5,  // low-pass pole shift  (bigger = lower corner)
    parameter integer DCK   = 16, // DC-block shift       (bigger = lower corner)
    parameter integer POLES = 1,  // 1 = single ~15kHz pole (board-like), 2 = softer
    parameter integer GAIN  = 5   // output left-shift toward full-scale 16-bit
)(
    input  wire               clk,        // 48 MHz
    input  wire               ce,         // processing enable (ce_3m = 3 MHz)
    input  wire               rst,
    input  wire        [10:0] ay_sum,     // ay1(0..1023) + ay2(0..1023) = 0..2046
    output reg  signed [15:0] snd_out
);
    // center near 0 so the DC blocker starts settled (it removes the residual)
    wire signed [12:0] x   = $signed({2'b00, ay_sum}) - 13'sd1023;
    wire signed [31:0] x_q = $signed(x) <<< FB;

    reg  signed [31:0] x_q1;   // previous input (Q.FB)
    reg  signed [31:0] dc_y;   // DC-blocked signal
    reg  signed [31:0] lp1;    // low-pass state 1
    reg  signed [31:0] lp2;    // low-pass state 2
    reg  signed [31:0] o;      // integer-scaled output (pre-saturate)

    localparam integer SH = FB - GAIN;                 // net down-shift after gain
    wire        signed [31:0] rnd = 32'sd1 <<< (SH-1); // rounding bias

    always @(posedge clk) begin
        if (rst) begin
            x_q1<=0; dc_y<=0; lp1<=0; lp2<=0; o<=0; snd_out<=0;
        end else if (ce) begin
            // (1) 1-pole DC blocker:  y = (x - x1) + y - (y >> DCK)
            dc_y <= (x_q - x_q1) + dc_y - (dc_y >>> DCK);
            x_q1 <= x_q;

            // (2) low-pass reconstruction: 1 pole (board-like) or 2 (softer)
            lp1  <= lp1 + ((dc_y - lp1) >>> LPK);
            lp2  <= lp2 + ((lp1  - lp2) >>> LPK);

            // (3) back to integer with output gain + rounding, then saturate
            o <= (((POLES >= 2) ? lp2 : lp1) + rnd) >>> SH;
            if      (o >  32'sd32767)  snd_out <= 16'sd32767;
            else if (o < -32'sd32768)  snd_out <= -16'sd32768;
            else                       snd_out <= o[15:0];
        end
    end
endmodule