//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_pocket.sv
// Summary  : Mirax core for Analogue Pocket (openFPGA)
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
//   Sources:
//     [SRC:MAME] ROM set miraxa, single-slot .rom layout
//     Analogue openFPGA APF conventions
//----------------------------------------------------------------------------
// Status: UNDER VALIDATION (platform wrapper) . Confidence: MEDIUM
// Open hypotheses: H-001
//============================================================================
// DESCRIPTION
//                      SINGLE-SLOT external ROM loading (offset-routed)
//  ROMs are no longer baked in: they arrive as ONE contiguous blob through the
//  download port (ioctl_*), exactly the layout the .mra produces:
//
//    0x00000  prog (encrypted, data_code)   0xC000   -> mrom  AW=16
//    0x0C000  audiocpu                       0x2000   -> mrom  AW=13
//    0x0E000  tiles   (3 planes x 0x4000)    0xC000   -> mrom3 AW=14
//    0x1A000  sprites (3 planes x 0x8000)    0x18000  -> mrom3 AW=15
//    0x32000  color proms                    0x0040   -> mrom  AW=6
//    total = 0x32040 (205,376 bytes)
//
//  The program stays encrypted (mirax_decrypt descrambles on the bus). The core
//  is held in reset while ioctl_download is high, so half-loaded ROMs never run.
//
//  Provide clk_sys = 48 MHz and clk_vid = 6 MHz from the APF PLL.
//============================================================================
`default_nettype none

module mirax_pocket
(
    input  wire        clk_sys,       // 48 MHz  (core render + sprite FSM)
    input  wire        clk_vid,       // 6 MHz   (APF pixel clock; sample domain)
    input  wire        reset,
    input  wire        pause,         // 1 = freeze CPU + audio (e.g. Pocket menu open)

    // ---- single-slot ROM download (byte stream from core_top bridge) --------
    input  wire        ioctl_download, // high for the whole transfer
    input  wire        ioctl_wr,       // 1-cycle write strobe (clk_sys domain)
    input  wire [24:0] ioctl_addr,     // byte offset within the single .rom
    input  wire [ 7:0] ioctl_data,     // byte

    // controls (openFPGA standard 16-bit controller bitfields)
    input  wire [15:0] cont1_key,
    input  wire [15:0] cont2_key,
    input  wire [7:0]  dsw1,
    input  wire [7:0]  dsw2,

    // video
    output wire [7:0]  video_r,
    output wire [7:0]  video_g,
    output wire [7:0]  video_b,
    output wire        video_hs,
    output wire        video_vs,
    output wire        video_hb,
    output wire        video_vb,
    output wire        video_de,
    output wire        video_ce,

    // audio (signed 16-bit, mono duplicated)
    output wire [15:0] audio_l,
    output wire [15:0] audio_r
);
    // -------------------- reset (hold core during download) -----------------
    wire rst = reset | ioctl_download;

    // -------------------- clocks --------------------------------------------
    wire ce_6m, ce_3m, ce_12m, ce_240, ce_3m180;
    mirax_clocks u_clk (.clk48(clk_sys), .rst(rst),
        .ce_12m(ce_12m), .ce_6m(ce_6m), .ce_3m(ce_3m), .ce_3m180(ce_3m180), .ce_240hz(ce_240));

    // -------------------- clk_vid-aligned pixel enable ----------------------
    reg [2:0] vdsync;
    always @(posedge clk_sys) begin
        if (rst) vdsync <= 3'b000;
        else     vdsync <= {vdsync[1:0], clk_vid};
    end
    wire ce_pix = ~vdsync[2] & vdsync[1];   // 1 clk_sys pulse per clk_vid rising edge

    // ========================================================================
    //  PAUSE  -  gate ONLY the CPU/AY clock enables; video (ce_pix) and the
    //  audio output filter keep running. With no CPU cycles, VRAM/sprite/color
    //  RAM stay frozen, so the video engine scans a static, correct frame while
    //  the LCD stays locked. jt49 is fully cen-gated, so both AY-3-8912s freeze
    //  and hold their last sample; the DC blocker in mirax_audio_out then eases
    //  the held level to silence. Both Z80 phases are gated together so T80pa
    //  never advances mid-step. Synchronize pause into this 48 MHz domain.
    // ========================================================================
    reg [2:0] pause_sr;
    always @(posedge clk_sys) pause_sr <= {pause_sr[1:0], pause};
    wire pause_g = pause_sr[2];

    wire ce_3m_cpu    = ce_3m    & ~pause_g;   // main + sound Z80  (CEN_p)
    wire ce_3m180_cpu = ce_3m180 & ~pause_g;   // main + sound Z80  (CEN_n)
    wire ce_ay        = ce_3m    & ~pause_g;   // both AY-3-8912 (jt49 clk_en)

    // ========================================================================
    //  SINGLE-SLOT download router  (matches the .mra offset map)
    // ========================================================================
    localparam [24:0] BASE_AUD = 25'h00_C000;
    localparam [24:0] BASE_TIL = 25'h00_E000;
    localparam [24:0] BASE_SPR = 25'h01_A000;
    localparam [24:0] BASE_PRM = 25'h03_2000;
    localparam [24:0] BASE_END = 25'h03_2040;

    wire dl = ioctl_download & ioctl_wr;
    wire wr_prog = dl & (ioctl_addr <  BASE_AUD);
    wire wr_aud  = dl & (ioctl_addr >= BASE_AUD) & (ioctl_addr < BASE_TIL);
    wire wr_til  = dl & (ioctl_addr >= BASE_TIL) & (ioctl_addr < BASE_SPR);
    wire wr_spr  = dl & (ioctl_addr >= BASE_SPR) & (ioctl_addr < BASE_PRM);
    wire wr_prm  = dl & (ioctl_addr >= BASE_PRM) & (ioctl_addr < BASE_END);

    wire [15:0] wa_prog = ioctl_addr[15:0];                    // 0..0xBFFF
    wire [12:0] wa_aud  = (ioctl_addr - BASE_AUD);             // 0..0x1FFF
    wire [17:0] wa_til  = (ioctl_addr - BASE_TIL);             // 0..0xBFFF  (plane split inside)
    wire [17:0] wa_spr  = (ioctl_addr - BASE_SPR);             // 0..0x17FFF (plane split inside)
    wire [5:0]  wa_prm  = (ioctl_addr - BASE_PRM);             // 0..0x3F

    // -------------------- program ROM (encrypted, loadable) -----------------
    wire [15:0] prog_addr; wire [7:0] prog_data;
    mrom #(.AW(16)) u_prog (.clk(clk_sys),
        .addr(prog_addr), .data(prog_data),
        .we(wr_prog), .waddr(wa_prog), .wdata(ioctl_data));

    // -------------------- audio ROM (loadable) ------------------------------
    wire [12:0] srom_a; wire [7:0] srom_q;
    mrom #(.AW(13)) u_srom (.clk(clk_sys),
        .addr(srom_a), .data(srom_q),
        .we(wr_aud), .waddr(wa_aud), .wdata(ioctl_data));

    // -------------------- tile ROM (3 planes, loadable) ---------------------
    wire [13:0] tile_a; wire [7:0] tp0,tp1,tp2;
    mrom3 #(.AW(14)) u_tiles (.clk(clk_sys),
        .addr(tile_a), .p0(tp0), .p1(tp1), .p2(tp2),
        .we(wr_til), .waddr(wa_til), .wdata(ioctl_data));

    // -------------------- sprite ROM (3 planes, loadable) -------------------
    wire [14:0] spr_a; wire [7:0] sp0,sp1,sp2;
    mrom3 #(.AW(15)) u_sprom (.clk(clk_sys),
        .addr(spr_a), .p0(sp0), .p1(sp1), .p2(sp2),
        .we(wr_spr), .waddr(wa_spr), .wdata(ioctl_data));

    // -------------------- color PROMs (loadable) ----------------------------
    wire [5:0] prom_a; wire [7:0] prom_q;
    mrom #(.AW(6)) u_prom (.clk(clk_sys),
        .addr(prom_a), .data(prom_q),
        .we(wr_prm), .waddr(wa_prm), .wdata(ioctl_data));

    // -------------------- inputs --------------------------------------------
    wire [7:0] p1, p2;
    pocket_input_map u_in (.cont1_key(cont1_key), .cont2_key(cont2_key), .p1(p1), .p2(p2));

    // -------------------- shared video memories -----------------------------
    wire        vram_cs, spr_cs, cram_cs, mem_wr;
    wire [11:0] mem_addr; wire [7:0] cpu_dout;
    wire [7:0]  vram_cpu_q, spr_cpu_q, cram_cpu_q;
    wire [9:0]  v_vram_a; wire [7:0] v_vram_q;
    wire [8:0]  v_spr_a;  wire [7:0] v_spr_q;
    wire [5:0]  v_cram_a; wire [7:0] v_cram_q;

    dpram #(.AW(10)) u_vram (.clk(clk_sys),
        .a_addr(mem_addr[9:0]), .a_din(cpu_dout), .a_we(mem_wr & vram_cs), .a_dout(vram_cpu_q),
        .b_addr(v_vram_a), .b_din(8'h0), .b_we(1'b0), .b_dout(v_vram_q));
    dpram #(.AW(9)) u_spr (.clk(clk_sys),
        .a_addr(mem_addr[8:0]), .a_din(cpu_dout), .a_we(mem_wr & spr_cs), .a_dout(spr_cpu_q),
        .b_addr(v_spr_a), .b_din(8'h0), .b_we(1'b0), .b_dout(v_spr_q));
    dpram #(.AW(6)) u_cram (.clk(clk_sys),
        .a_addr(mem_addr[5:0]), .a_din(cpu_dout), .a_we(mem_wr & cram_cs), .a_dout(cram_cpu_q),
        .b_addr(v_cram_a), .b_din(8'h0), .b_we(1'b0), .b_dout(v_cram_q));

    // -------------------- main CPU ------------------------------------------
    wire flip_x, flip_y, coin1, coin2, vblank_rise;
    wire [7:0] sound_cmd; wire sound_cmd_wr;
    mirax_main u_main (
        .clk(clk_sys), .cen(ce_3m_cpu), .cen_3m180(ce_3m180_cpu), .rst(rst), .vblank_rise(vblank_rise),
        .prog_addr(prog_addr), .prog_data(prog_data),
        .vram_cs(vram_cs), .spr_cs(spr_cs), .cram_cs(cram_cs),
        .mem_addr(mem_addr), .cpu_dout(cpu_dout),
        .vram_dout(vram_cpu_q), .spr_dout(spr_cpu_q), .cram_dout(cram_cpu_q), .mem_wr(mem_wr),
        .p1(p1), .p2(p2), .dsw1(dsw1), .dsw2(dsw2),
        .sound_cmd(sound_cmd), .sound_cmd_wr(sound_cmd_wr),
        .flip_x(flip_x), .flip_y(flip_y), .coin1(coin1), .coin2(coin2));

    // -------------------- sound ---------------------------------------------
    wire [9:0]  snd;
    wire [10:0] snd_sum;
    mirax_sound u_sound (
        .clk(clk_sys), .cen(ce_3m_cpu), .cen_3m180(ce_3m180_cpu), .cen_ay(ce_ay), .rst(rst),
        .sound_cmd(sound_cmd), .sound_cmd_wr(sound_cmd_wr), .irq_tick(ce_240),
        .rom_addr(srom_a), .rom_data(srom_q),
        .sound_out(snd), .sound_sum(snd_sum));

    // output-stage model (DC block ~7 Hz + 1-pole ~15 kHz), tuned to CT805-3
    wire signed [15:0] snd_f;
    mirax_audio_out #(.LPK(5), .DCK(16), .POLES(1), .GAIN(5)) u_aout (
        .clk(clk_sys), .ce(ce_3m), .rst(rst),
        .ay_sum(snd_sum), .snd_out(snd_f));
    assign audio_l = snd_f;
    assign audio_r = snd_f;

    // -------------------- video ---------------------------------------------
    wire hb, vb;
    mirax_video u_video (
        .clk(clk_sys), .ce_pix(ce_pix), .rst(rst),
        .flip_x(flip_x), .flip_y(flip_y),
        .vram_addr(v_vram_a), .vram_data(v_vram_q),
        .cram_addr(v_cram_a), .cram_data(v_cram_q),
        .spr_addr(v_spr_a),   .spr_data(v_spr_q),
        .tile_addr(tile_a), .tile_p0(tp0), .tile_p1(tp1), .tile_p2(tp2),
        .sprom_addr(spr_a), .sprom_p0(sp0), .sprom_p1(sp1), .sprom_p2(sp2),
        .prom_addr(prom_a), .prom_data(prom_q),
        .red(video_r), .green(video_g), .blue(video_b),
        .hsync(video_hs), .vsync(video_vs), .hblank(hb), .vblank(vb),
        .vblank_rise(vblank_rise));

    assign video_de = ~(hb | vb);
    assign video_ce = ce_pix;
    assign video_hb = hb;
    assign video_vb = vb;
endmodule

// ---------------------------------------------------------------------------
//  Loadable single-port ROM (BRAM): read port + byte-write download port.
// ---------------------------------------------------------------------------
module mrom #(parameter AW=16) (
    input  wire            clk,
    input  wire [AW-1:0]   addr,
    output reg  [7:0]      data,
    input  wire            we,
    input  wire [AW-1:0]   waddr,
    input  wire [7:0]      wdata
);
    reg [7:0] mem [0:(1<<AW)-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        data <= mem[addr];
    end
endmodule

// ---------------------------------------------------------------------------
//  Loadable 3-plane ROM: one read address -> p0/p1/p2. Download stream is the
//  region laid out as plane0(SZ) ++ plane1(SZ) ++ plane2(SZ); the linear waddr
//  is split into the three plane BRAMs here.
// ---------------------------------------------------------------------------
module mrom3 #(parameter AW=14) (
    input  wire            clk,
    input  wire [AW-1:0]   addr,
    output reg  [7:0]      p0,
    output reg  [7:0]      p1,
    output reg  [7:0]      p2,
    input  wire            we,
    input  wire [17:0]     waddr,   // region-relative byte offset
    input  wire [7:0]      wdata
);
    localparam integer SZ = (1<<AW);
    reg [7:0] m0 [0:SZ-1];
    reg [7:0] m1 [0:SZ-1];
    reg [7:0] m2 [0:SZ-1];
    always @(posedge clk) begin
        if (we) begin
            if      (waddr <  SZ)       m0[waddr]          <= wdata;
            else if (waddr <  2*SZ)     m1[waddr - SZ]     <= wdata;
            else                        m2[waddr - 2*SZ]   <= wdata;
        end
        p0 <= m0[addr];
        p1 <= m1[addr];
        p2 <= m2[addr];
    end
endmodule