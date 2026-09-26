//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_top.sv
// Summary  : Top-level wiring for the Mirax core (target-agnostic)
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
//     H-013 [HYP]     Third PROM (MAME 'mirax.prm', NO_DUMP): mirax_top says CT805-3 has
//                     none, mirax_decrypt says it may encode the scheme. CONFLICT.
//   Sources:
//     [SRC:MAME] ROM set miraxa region layout
//   Known issues / notes:
//     mirax_main.cen_3m180 and mirax_sound.cen_3m180 are left unconnected here
//     (mirax_pocket.sv connects them). Use mirax_pocket.sv as the real top.
//----------------------------------------------------------------------------
// Status: LEGACY / REFERENCE . Confidence: N/A
// Open hypotheses: H-013
//============================================================================
// DESCRIPTION
//  Ties main CPU + sound + video + shared memories + ROM loading.
//  ROM interface is the common "download" convention: a byte stream with an
//  index that selects the destination region. Wire ioctl_* to your platform
//  (openFPGA data loader / Analogizer) at the wrapper above this.
//
//  ROM load map (region select via ioctl_index), target = miraxa (set 2):
//    0 : maincpu program (encrypted)  48K  (p5/r5/s5 43v)  -> stored as-is
//    1 : audiocpu                      8K  (mxr2)
//    2 : tiles   (3 x 16K)            48K
//    3 : sprites (3 x 32K span)       96K  (loaded per MAME offsets)
//    4 : color proms  MRA3,MRB3       64B  (2 x 82S123)
//  (No third NO_DUMP prom on this board - set 2 only carries MRA3/MRB3.)
//============================================================================
`default_nettype none

module mirax_top
(
    input  wire        clk48,
    input  wire        reset,

    // controls (active-high, arranged to match P1/P2 port bit order)
    input  wire [7:0]  p1_in,
    input  wire [7:0]  p2_in,
    input  wire [7:0]  dsw1,
    input  wire [7:0]  dsw2,

    // video out
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        hsync,
    output wire        vsync,
    output wire        hblank,
    output wire        vblank,
    output wire        ce_pix,     // pixel enable (aux/debug: for TB frame sampling)

    // audio
    output wire [9:0]  audio,

    // ROM download
    input  wire        ioctl_download,
    input  wire [7:0]  ioctl_index,
    input  wire        ioctl_wr,
    input  wire [24:0] ioctl_addr,
    input  wire [7:0]  ioctl_data
);
    // -------------------- clocks --------------------------------------------
    wire ce_6m, ce_3m, ce_12m, ce_240;
    mirax_clocks u_clk (.clk48(clk48), .rst(reset),
        .ce_12m(ce_12m), .ce_6m(ce_6m), .ce_3m(ce_3m), .ce_240hz(ce_240));
    assign ce_pix = ce_6m;

    // -------------------- program ROM (encrypted image, 48K) ----------------
    // main drives a *scrambled* address; ROM returns raw bytes.
    wire [15:0] prog_addr; wire [7:0] prog_data;
    rom_sp #(.AW(16), .FILE("")) u_prog (
        .clk(clk48), .addr(prog_addr[15:0]), .data(prog_data),
        .wr(ioctl_wr & ioctl_download & (ioctl_index==8'd0)),
        .waddr(ioctl_addr[15:0]), .wdata(ioctl_data));

    // -------------------- shared video memories -----------------------------
    // VRAM 1Kx8, sprite 0x200, colorram 0x40 : CPU port + video port
    wire        vram_cs, spr_cs, cram_cs, mem_wr;
    wire [11:0] mem_addr; wire [7:0] cpu_dout;
    wire [7:0]  vram_cpu_q, spr_cpu_q, cram_cpu_q;

    wire [9:0] v_vram_a; wire [7:0] v_vram_q;
    dpram #(.AW(10)) u_vram (.clk(clk48),
        .a_addr(mem_addr[9:0]), .a_din(cpu_dout), .a_we(mem_wr & vram_cs), .a_dout(vram_cpu_q),
        .b_addr(v_vram_a), .b_din(8'h0), .b_we(1'b0), .b_dout(v_vram_q));

    wire [8:0] v_spr_a; wire [7:0] v_spr_q;
    dpram #(.AW(9)) u_spr (.clk(clk48),
        .a_addr(mem_addr[8:0]), .a_din(cpu_dout), .a_we(mem_wr & spr_cs), .a_dout(spr_cpu_q),
        .b_addr(v_spr_a), .b_din(8'h0), .b_we(1'b0), .b_dout(v_spr_q));

    wire [5:0] v_cram_a; wire [7:0] v_cram_q;
    dpram #(.AW(6)) u_cram (.clk(clk48),
        .a_addr(mem_addr[5:0]), .a_din(cpu_dout), .a_we(mem_wr & cram_cs), .a_dout(cram_cpu_q),
        .b_addr(v_cram_a), .b_din(8'h0), .b_we(1'b0), .b_dout(v_cram_q));

    // -------------------- main CPU ------------------------------------------
    wire flip_x, flip_y, coin1, coin2, vblank_rise;
    wire [7:0] sound_cmd; wire sound_cmd_wr;

    mirax_main u_main (
        .clk(clk48), .cen(ce_3m), .rst(reset),
        .vblank_rise(vblank_rise),
        .prog_addr(prog_addr), .prog_data(prog_data),
        .vram_cs(vram_cs), .spr_cs(spr_cs), .cram_cs(cram_cs),
        .mem_addr(mem_addr), .cpu_dout(cpu_dout),
        .vram_dout(vram_cpu_q), .spr_dout(spr_cpu_q), .cram_dout(cram_cpu_q),
        .mem_wr(mem_wr),
        .p1(p1_in), .p2(p2_in), .dsw1(dsw1), .dsw2(dsw2),
        .sound_cmd(sound_cmd), .sound_cmd_wr(sound_cmd_wr),
        .flip_x(flip_x), .flip_y(flip_y), .coin1(coin1), .coin2(coin2));

    // -------------------- sound ---------------------------------------------
    wire [12:0] srom_a; wire [7:0] srom_q;
    rom_sp #(.AW(13), .FILE("")) u_srom (
        .clk(clk48), .addr(srom_a), .data(srom_q),
        .wr(ioctl_wr & ioctl_download & (ioctl_index==8'd1)),
        .waddr(ioctl_addr[12:0]), .wdata(ioctl_data));

    mirax_sound u_sound (
        .clk(clk48), .cen(ce_3m), .cen_ay(ce_3m), .rst(reset),
        .sound_cmd(sound_cmd), .sound_cmd_wr(sound_cmd_wr), .irq_tick(ce_240),
        .rom_addr(srom_a), .rom_data(srom_q), .sound_out(audio));

    // -------------------- gfx ROMs ------------------------------------------
    wire [13:0] tile_a; wire [7:0] tp0,tp1,tp2;
    rom_planes3 #(.AW(14)) u_tiles (
        .clk(clk48), .addr(tile_a), .p0(tp0), .p1(tp1), .p2(tp2),
        .wr(ioctl_wr & ioctl_download & (ioctl_index==8'd2)),
        .waddr({1'b0, ioctl_addr[15:0]}), .wdata(ioctl_data));

    wire [14:0] spr_a; wire [7:0] sp0,sp1,sp2;
    rom_planes3 #(.AW(15)) u_sprom (
        .clk(clk48), .addr(spr_a), .p0(sp0), .p1(sp1), .p2(sp2),
        .wr(ioctl_wr & ioctl_download & (ioctl_index==8'd3)),
        .waddr(ioctl_addr[16:0]), .wdata(ioctl_data));

    // -------------------- color PROM (0x40) ---------------------------------
    wire [5:0] prom_a; wire [7:0] prom_q;
    rom_sp #(.AW(6), .FILE("")) u_prom (
        .clk(clk48), .addr(prom_a), .data(prom_q),
        .wr(ioctl_wr & ioctl_download & (ioctl_index==8'd4)),
        .waddr(ioctl_addr[5:0]), .wdata(ioctl_data));

    // -------------------- video ---------------------------------------------
    mirax_video u_video (
        .clk(clk48), .ce_pix(ce_6m), .rst(reset),
        .flip_x(flip_x), .flip_y(flip_y),
        .vram_addr(v_vram_a), .vram_data(v_vram_q),
        .cram_addr(v_cram_a), .cram_data(v_cram_q),
        .spr_addr(v_spr_a),   .spr_data(v_spr_q),
        .tile_addr(tile_a), .tile_p0(tp0), .tile_p1(tp1), .tile_p2(tp2),
        .sprom_addr(spr_a), .sprom_p0(sp0), .sprom_p1(sp1), .sprom_p2(sp2),
        .prom_addr(prom_a), .prom_data(prom_q),
        .red(vga_r), .green(vga_g), .blue(vga_b),
        .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
        .vblank_rise(vblank_rise));

endmodule

// ---- tiny ROM helpers (single-port read + download write) ------------------
module rom_sp #(parameter AW=16, parameter FILE="") (
    input wire clk, input wire [AW-1:0] addr, output reg [7:0] data,
    input wire wr, input wire [AW-1:0] waddr, input wire [7:0] wdata);
    reg [7:0] mem [0:(1<<AW)-1];
    always @(posedge clk) begin
        if (wr) mem[waddr] <= wdata;
        data <= mem[addr];
    end
endmodule

// three parallel planes packed at RGN_FRAC(1/3) offsets in one download stream
module rom_planes3 #(parameter AW=14) (
    input wire clk, input wire [AW-1:0] addr,
    output reg [7:0] p0, output reg [7:0] p1, output reg [7:0] p2,
    input wire wr, input wire [16:0] waddr, input wire [7:0] wdata);
    localparam SZ = (1<<AW);
    reg [7:0] m0 [0:SZ-1];
    reg [7:0] m1 [0:SZ-1];
    reg [7:0] m2 [0:SZ-1];
    always @(posedge clk) begin
        if (wr) begin
            if      (waddr <  SZ)     m0[waddr]        <= wdata;
            else if (waddr <  2*SZ)   m1[waddr-SZ]     <= wdata;
            else                      m2[waddr-2*SZ]   <= wdata;
        end
        p0 <= m0[addr]; p1 <= m1[addr]; p2 <= m2[addr];
    end
endmodule

`default_nettype wire
