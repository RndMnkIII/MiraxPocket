//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : pocket_video_out.sv
// Summary  : Minimal APF (Analogue Pocket) video output stage
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
//     Analogue openFPGA APF video interface conventions
//----------------------------------------------------------------------------
// Status: STABLE (platform glue) . Confidence: N/A
// Open hypotheses: none
//============================================================================
// DESCRIPTION
//  Note: HS is emitted ONLY on the rising edge of core_hs, and is suppressed for
//  one clock after DE falls (hs_enable_dly). Feed a synthetic core_hs whose
//  rising edge sits a few cycles inside hblank, clear of the DE<->HS guards
//  (this core generates core_hs_apf/core_vs_apf from blanking for exactly that).
//============================================================================
`default_nettype none
`timescale 1ns/1ps

module pocket_video_out
(
    input  wire        clk_vid,            //! Pixel clock (drives the scaler)
    input  wire        clk_vid_90deg,      //! Pixel clock, 90deg phase
    input  wire        reset,

    // ---- video from the core (RGB888 + syncs/blanks, clk_vid domain) --------
    input  wire [7:0]  core_r,
    input  wire [7:0]  core_g,
    input  wire [7:0]  core_b,
    input  wire        core_hs,            //! Horizontal sync (active high)
    input  wire        core_vs,            //! Vertical   sync (active high)
    input  wire        core_hb,            //! Horizontal blank
    input  wire        core_vb,            //! Vertical   blank

    // ---- output to the APF scaler -------------------------------------------
    output reg  [23:0] video_rgb,          //! R[23:16] G[15:8] B[7:0]
    output reg         video_hs,
    output reg         video_vs,
    output reg         video_de,
    output wire        video_skip,
    output wire        video_rgb_clock,
    output wire        video_rgb_clock_90
);

    // Hardwired for a progressive, non-interlaced core writing scaler slot 0.
    // (These were constant inputs in the original video_mixer instantiation.)
    localparam        FIELD        = 1'b0;   // [0] even / [1] odd
    localparam        INTERLACED   = 1'b0;   // [0] progressive / [1] interlaced
    localparam [2:0]  VIDEO_PRESET = 3'd0;   // AP scaler preset slot

    // Data-enable straight from the core blanking (matches de_out = ~(hb|vb)).
    wire de_in = ~(core_hb | core_vb);

    reg        hs_last, vs_last, de_last;   // edge detection
    reg        hs_enable_dly;               // gap after DE falls (blocks HS 1clk)
    reg        de_enable_dly;               // gap after HS rises (blocks DE 1clk)
    reg  [1:0] vs_dly_cnt;                  // 3-cycle countdown after VS rise

    always_ff @(posedge clk_vid) begin : apf_video_out
        if (reset) begin
            video_rgb     <= 24'h0;
            video_hs      <= 1'b0;
            video_vs      <= 1'b0;
            video_de      <= 1'b0;
            hs_last       <= 1'b0;
            vs_last       <= 1'b0;
            de_last       <= 1'b0;
            vs_dly_cnt    <= 2'd0;
            hs_enable_dly <= 1'b1;
            de_enable_dly <= 1'b1;
        end
        else begin
            // previous state for edge detection
            vs_last <= core_vs;
            hs_last <= core_hs;
            de_last <= de_in;

            // default outputs for this cycle
            video_rgb <= 24'h0;
            video_hs  <= 1'b0;
            video_vs  <= 1'b0;
            video_de  <= 1'b0;

            // --- timing-gap state (read this cycle, updated for next) ---------
            // 1) VS->HS 3-cycle gap
            if (~vs_last && core_vs)        vs_dly_cnt <= 2'd2;
            else if (vs_dly_cnt > 2'd0)     vs_dly_cnt <= vs_dly_cnt - 2'd1;

            // 2) DE->HS 1-cycle gap
            hs_enable_dly <= 1'b1;
            if (de_last && ~de_in)          hs_enable_dly <= 1'b0;

            // 3) HS->DE 1-cycle gap
            de_enable_dly <= 1'b1;
            if (~hs_last && core_hs)        de_enable_dly <= 1'b0;

            // --- output generation -------------------------------------------
            // single-cycle VS pulse + frame-info word
            if (~vs_last && core_vs) begin
                video_vs  <= 1'b1;
                // [3] last field | [2] field | [1] interlaced | [0] rescan
                video_rgb <= { 20'h0, ~FIELD, FIELD, INTERLACED, 1'b0 };
            end

            // single-cycle HS pulse, respecting all gaps
            if ((~hs_last && core_hs) && (vs_dly_cnt == 2'd0) && hs_enable_dly)
                video_hs <= 1'b1;

            // DE + active pixel, respecting the gap after HS
            if (de_in && de_enable_dly) begin
                video_de  <= 1'b1;
                video_rgb <= { core_r, core_g, core_b };
            end
            // scaler-slot command on the falling edge of DE
            else if (de_last && ~de_in) begin
                video_rgb <= { 8'h0, VIDEO_PRESET, 13'h0 };
            end
        end
    end

    assign video_rgb_clock    = clk_vid;
    assign video_rgb_clock_90 = clk_vid_90deg;
    assign video_skip         = 1'b0;

endmodule