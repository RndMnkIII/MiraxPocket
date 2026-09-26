//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_main.sv
// Summary  : Main CPU subsystem (encrypted Z80 + address decode)
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
//     H-005 [HYP]     Main address decode is built from 74LS138/139 + LS20/LS32 gates and
//                     matches the MAME map; board-side decode not traced.
//   Sources:
//     [SRC:MAME] memory map, LS259 bit usage, sound latch at 0xF800
//     [SRC:PCB R10] 74LS259 location as given by MAME
//   Known issues / notes:
//     Comment says work RAM is 2x 58725 '2Kx8' in the map and '4Kx8' in the
//     decode section; 2x 2Kx8 = 4Kx8 matches the C800-D7FF window.
//----------------------------------------------------------------------------
// Status: UNDER VALIDATION . Confidence: MEDIUM
// Open hypotheses: H-004, H-005
//============================================================================
// DESCRIPTION
//  Reconstructs the CT805-3 main-CPU side around a drop-in Z80 core (T80).
//  The address decode is written as flat combinational equations, the way the
//  board's 74LS138/139 + LS20/LS32 gates resolve it - one enable per region.
//
//  Memory map (verified from MAME misc/mirax.cpp, matches board):
//    0000-BFFF  R   program ROM  (via mirax_decrypt interposer)
//    C800-D7FF  RW  work RAM     (board: 2x 58725, 2Kx8)
//    E000-E3FF  RW  video RAM    (board: 2x 2114, tilemap 32x32)
//    E800-E9FF  RW  sprite RAM   (0x200 = 128 entries x 4)
//    EA00-EA3F  RW  color/scroll RAM (2 bytes per column x 32)
//    F000       R   P1
//    F100       R   P2
//    F200       R   DSW1
//    F300       R   watchdog (read, discarded)
//    F400       R   DSW2
//    F500-F507  W   LS259 addressable latch (R10)
//    F800       W   sound command latch + NMI to audio Z80
//
//  IRQ: vblank drives /NMI when the LS259 Q1 mask is set.
//============================================================================
`default_nettype none

module mirax_main
(
    input  wire        clk,          // CPU clock domain (3 MHz enable-gated upstream)
    input  wire        cen,          // clock enable = 12MHz/4
    input  wire        cen_3m180,    // clock enable = 12MHz/4, 180 deg phase
    input  wire        rst,

    // vblank pulse for NMI generation
    input  wire        vblank_rise,

    // ---- program ROM (encrypted image) : we drive scrambled addr, get raw data
    output wire [15:0] prog_addr,    // scrambled address into program EPROMs
    input  wire [ 7:0] prog_data,    // raw (encrypted) EPROM byte

    // ---- shared video memories (dual-port, video side elsewhere) ------------
    output wire        vram_cs,
    output wire        spr_cs,
    output wire        cram_cs,
    output wire [11:0] mem_addr,     // low address to the video-side RAMs
    output wire [ 7:0] cpu_dout,
    input  wire [ 7:0] vram_dout,
    input  wire [ 7:0] spr_dout,
    input  wire [ 7:0] cram_dout,
    output wire        mem_wr,

    // ---- inputs -------------------------------------------------------------
    input  wire [ 7:0] p1,
    input  wire [ 7:0] p2,
    input  wire [ 7:0] dsw1,
    input  wire [ 7:0] dsw2,

    // ---- sound command ------------------------------------------------------
    output reg  [ 7:0] sound_cmd,
    output reg         sound_cmd_wr,  // 1-cycle strobe -> pulses audio NMI

    // ---- control latch outputs (LS259) --------------------------------------
    output wire        flip_x,
    output wire        flip_y,
    output wire        coin1,
    output wire        coin2
);

    // -------------------- Z80 core (T80) ------------------------------------
    wire [15:0] cpu_addr;
    wire [ 7:0] cpu_din;
    wire [ 7:0] cpu_dout_i;
    wire        cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_m1_n;
    reg         nmi_n;

    assign cpu_dout = cpu_dout_i;

    T80pa u_cpu (
        .RESET_n (~rst),
        .CLK     (clk),
        .CEN_p   (cen),
        .CEN_n   (cen_3m180),
        .WAIT_n  (1'b1),
        .INT_n   (1'b1),
        .NMI_n   (nmi_n),
        .BUSRQ_n (1'b1),
        .M1_n    (cpu_m1_n),
        .MREQ_n  (cpu_mreq_n),
        .IORQ_n  (cpu_iorq_n),
        .RD_n    (cpu_rd_n),
        .WR_n    (cpu_wr_n),
        .A       (cpu_addr),
        .DI      (cpu_din),
        .DO      (cpu_dout_i)
    );

    // -------------------- program descrambler (potted module) ----------------
    wire [7:0] prog_dec;
    mirax_decrypt u_dec (
        .cpu_addr   (cpu_addr),
        .eprom_addr (prog_addr),
        .eprom_data (prog_data),
        .cpu_data   (prog_dec)
    );

    // -------------------- flat address decode (LS138/139-style) --------------
    wire cs_rom  = (cpu_addr <= 16'hBFFF);
    // work RAM window C800-D7FF (board: 2x 58725, 4Kx8)
    wire cs_wram_ex = (cpu_addr >= 16'hC800) && (cpu_addr <= 16'hD7FF);
    wire cs_vram = (cpu_addr[15:10] == 6'b111000);                 // E000-E3FF
    wire cs_spr  = (cpu_addr[15:9]  == 7'b1110100);                // E800-E9FF
    wire cs_cram = (cpu_addr[15:6]  == 10'b1110101000);            // EA00-EA3F

    wire cs_p1   = (cpu_addr[15:8] == 8'hF0);
    wire cs_p2   = (cpu_addr[15:8] == 8'hF1);
    wire cs_dsw1 = (cpu_addr[15:8] == 8'hF2);
    wire cs_wdog = (cpu_addr[15:8] == 8'hF3);
    wire cs_dsw2 = (cpu_addr[15:8] == 8'hF4);
    wire cs_ls259= (cpu_addr[15:8] == 8'hF5);
    wire cs_snd  = (cpu_addr[15:8] == 8'hF8);

    wire cpu_wr = ~cpu_wr_n & ~cpu_mreq_n;
    wire cpu_rd = ~cpu_rd_n & ~cpu_mreq_n;

    // -------------------- work RAM (58725 x2 -> 4Kx8 block RAM) ---------------
    reg [7:0] wram [0:4095];
    reg [7:0] wram_dout;
    wire [11:0] wram_a = cpu_addr[11:0] - 12'h800; // C800 base
    always @(posedge clk) begin
        if (cen) begin
            if (cs_wram_ex & cpu_wr) wram[wram_a] <= cpu_dout_i;
            wram_dout <= wram[wram_a];
        end
    end

    // -------------------- shared video-mem interface -------------------------
    assign vram_cs  = cs_vram;
    assign spr_cs   = cs_spr;
    assign cram_cs  = cs_cram;
    assign mem_addr = cpu_addr[11:0];
    assign mem_wr   = cpu_wr & (cs_vram | cs_spr | cs_cram);

    // -------------------- read mux -------------------------------------------
    assign cpu_din =
        cs_rom     ? prog_dec   :
        cs_wram_ex ? wram_dout  :
        cs_vram    ? vram_dout  :
        cs_spr     ? spr_dout   :
        cs_cram    ? cram_dout  :
        cs_p1      ? p1         :
        cs_p2      ? p2         :
        cs_dsw1    ? dsw1       :
        cs_dsw2    ? dsw2       :
        8'hFF;

    // -------------------- LS259 mainlatch (R10) ------------------------------
    wire [7:0] latch_q;
    ttl_ls259 u_ls259 (
        .clk (clk),
        .rst (rst),
        .g_n (~(cs_ls259 & cpu_wr & cen)),
        .a   (cpu_addr[2:0]),
        .d   (cpu_dout_i[0]),
        .q   (latch_q)
    );
    assign coin1  = latch_q[0];
    wire   nmi_en = latch_q[1];
    assign coin2  = latch_q[2];
    assign flip_x = latch_q[6];
    assign flip_y = latch_q[7];

    // -------------------- sound command write (0xF800) -----------------------
    always @(posedge clk) begin
        sound_cmd_wr <= 1'b0;
        if (rst) begin
            sound_cmd <= 8'h00;
        end else if (cen & cs_snd & cpu_wr) begin
            sound_cmd    <= cpu_dout_i;
            sound_cmd_wr <= 1'b1;
        end
    end

    // -------------------- NMI generation (vblank & mask) ---------------------
    always @(posedge clk) begin
        if (rst)
            nmi_n <= 1'b1;
        else begin
            if (!nmi_en)
                nmi_n <= 1'b1;                 // mask clear releases /NMI
            else if (vblank_rise)
                nmi_n <= 1'b0;                 // assert on vblank
        end
    end

endmodule

`default_nettype wire
