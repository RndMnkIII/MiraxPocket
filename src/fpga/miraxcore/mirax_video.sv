//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_video.sv
// Summary  : Video engine (tilemap + sprite engine + color PROM DAC)
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
//     H-003 [HYP]     Video timing HTOTAL=384, VTOTAL=262 and sync start/end positions
//                     are estimates (MAME only gives set_refresh(60) + 256x256).
//     H-012 [HYP]     CPU/video share VRAM + colorram through 74LS157 address muxes on
//                     alternate dot-clock phases (motivates the per-frame snapshot).
//     H-021 [HYP:AI]  Colour DAC weights: 1K/470/270 (R,G) and 470/270 (B) from PCB
//                     tracing; MAME assumes 1K/470/220 and 1K/470.
//     H-022 [HYP:HUM] MRA3/MRB3 = two 32-entry RGB332 banks selected via /CE, outputs
//                     in parallel -> one 64x8 palette.
//   Sources:
//     [SRC:MAME] draw_tilemap, column scroll, palette decode
//     [SRC:PCB A11,B11] colour PROMs MRA3/MRB3 + resistor network at A12
//   Known issues / notes:
//     The DAC still uses MAME weights (0x21/0x47/0x97, 0x52/0xAD). Switch to
//     mirax_dac_lut.svh once H-021 is confirmed.
//----------------------------------------------------------------------------
// Status: UNDER VALIDATION . Confidence: MEDIUM
// Open hypotheses: H-001, H-003, H-012, H-021, H-022
//============================================================================
// DESCRIPTION
//  Screen 256x256, visible x 0..255 / y 8..247, ROT90, ~60 Hz.
//  VTOTAL = 262 (15 kHz-friendly for CRT via Analogizer).
//
//  Tilemap (MAME draw_tilemap, exact):
//    tile   = videoram[32*y + x]
//    scroll = colorram[x*2]          (per-column vertical scroll)
//    lowcol = colorram[x*2 + 1]
//    tile_index = {lowcol[7:5], tile}
//    palette    = lowcol[2:0]
//    source row = (py + scroll)
//
//  COLORRAM SNAPSHOT (per-frame, matches the board's LS157 time-multiplexing):
//    The real CT805-3 shares VRAM/colorram between CPU and video via 74LS157
//    address muxes on opposite dot-clock phases -> the video never reads a
//    colorram byte the CPU is writing that instant. Our shared BRAM is true
//    dual-port, so a CPU write to a column's scroll while the raster reads it
//    corrupts that column for the whole frame (one column shifted ~1 tile).
//    Fix: snapshot the 32 scroll + 32 color bytes into registers during vblank
//    and have the pipeline read the FROZEN buffers -> a coherent per-frame view,
//    immune to mid-frame CPU writes (what MAME gets for free by drawing once).
//============================================================================
`default_nettype none

module mirax_video
(
    input  wire        clk,          // 48 MHz
    input  wire        ce_pix,       // 6 MHz pixel enable
    input  wire        rst,

    input  wire        flip_x,
    input  wire        flip_y,

    // VRAM / CRAM / sprite RAM (video read port)
    output reg  [ 9:0] vram_addr,
    input  wire [ 7:0] vram_data,
    output reg  [ 5:0] cram_addr,     // now driven only by the snapshot FSM
    input  wire [ 7:0] cram_data,
    output wire [ 8:0] spr_addr,
    input  wire [ 7:0] spr_data,

    // tile ROM (3 planes x 0x4000)
    output reg  [13:0] tile_addr,
    input  wire [ 7:0] tile_p0,
    input  wire [ 7:0] tile_p1,
    input  wire [ 7:0] tile_p2,

    // sprite ROM (3 planes x 0x8000)
    output wire [14:0] sprom_addr,
    input  wire [ 7:0] sprom_p0,
    input  wire [ 7:0] sprom_p1,
    input  wire [ 7:0] sprom_p2,

    // color PROM (0x40 x 8)
    output wire [ 5:0] prom_addr,
    input  wire [ 7:0] prom_data,

    // video out
    output reg  [ 7:0] red,
    output reg  [ 7:0] green,
    output reg  [ 7:0] blue,
    output wire        hsync,
    output wire        vsync,
    output wire        hblank,
    output wire        vblank,
    output wire        vblank_rise
);

    // ======================================================================
    //  H/V timing. 384 x 262 @ ~6.0 MHz -> Hfreq 15.625 kHz, Vfreq ~59.6 Hz.
    // ======================================================================
    // [HYP H-003] totals and sync positions are estimates  [VERIFY]
    localparam HTOTAL=384, HSYNC_S=306, HSYNC_E=334;
    localparam VTOTAL=262, VSYNC_S=249, VSYNC_E=253;

    reg [8:0] hc, vc;
    reg       line_start;
    always @(posedge clk) begin
        line_start <= 1'b0;
        if (rst) begin hc<=0; vc<=0; end
        else if (ce_pix) begin
            if (hc==HTOTAL-1) begin
                hc<=0; line_start<=1'b1;
                vc <= (vc==VTOTAL-1) ? 9'd0 : vc+9'd1;
            end else hc<=hc+9'd1;
        end
    end

    assign hsync = ~((hc>=HSYNC_S)&&(hc<HSYNC_E));
    assign vsync = ~((vc>=VSYNC_S)&&(vc<VSYNC_E));
    wire h_active = (hc < 256);
    wire v_active = (vc >= 8) && (vc < 248);
    assign hblank = ~h_active;
    assign vblank = ~v_active;
    reg vblank_d;
    always @(posedge clk) if (ce_pix) vblank_d <= vblank;
    assign vblank_rise = vblank & ~vblank_d;

    wire [7:0] sx = hc[7:0];
    wire [7:0] sy = vc[7:0];
    wire [7:0] px = flip_x ? (8'd255 - sx) : sx;
    wire [7:0] py = flip_y ? (8'd255 - sy) : sy;
    wire [4:0] col = px[7:3];

    // ======================================================================
    //  COLORRAM SNAPSHOT  (fills once per frame during vblank)
    //  scroll_buf[c] = colorram[c*2] ; color_buf[c] = colorram[c*2+1]
    //  cram_addr is driven ONLY here; the pipeline reads the buffers.
    // ======================================================================
    reg [7:0] scroll_buf [0:31];
    reg [7:0] color_buf  [0:31];

    //  Snapshot near the END of vblank (entering line vc==5), AFTER the vblank
    //  NMI handler (fired at vc==248) has written the scroll table, and well
    //  before active resumes at vc==8. Triggering at vblank_rise would race the
    //  CPU's own colorram writes and capture a half-updated table.
    reg [8:0] vc_d;
    always @(posedge clk) if (ce_pix) vc_d <= vc;
    wire snap_trig = (vc == 9'd5) && (vc_d == 9'd4);   // one-shot at start of line 5

    localparam [1:0] SNAP_A=2'd0, SNAP_B=2'd1, SNAP_C=2'd2;
    reg [1:0] snap_st;
    reg [4:0] snap_col;
    reg       snapping;
    always @(posedge clk) begin
        if (rst) begin snapping<=1'b0; snap_st<=SNAP_A; snap_col<=5'd0; cram_addr<=6'd0; end
        else if (ce_pix) begin
            if (snap_trig) begin
                snapping <= 1'b1; snap_st <= SNAP_A; snap_col <= 5'd0;
            end else if (snapping) begin
                case (snap_st)
                    SNAP_A: begin cram_addr <= {snap_col, 1'b0}; snap_st <= SNAP_B; end
                    SNAP_B: begin scroll_buf[snap_col] <= cram_data;      // scroll valid
                                  cram_addr <= {snap_col, 1'b1}; snap_st <= SNAP_C; end
                    SNAP_C: begin color_buf[snap_col] <= cram_data;       // color valid
                                  if (snap_col == 5'd31) snapping <= 1'b0;
                                  else begin snap_col <= snap_col + 5'd1; snap_st <= SNAP_A; end
                             end
                    default: snap_st <= SNAP_A;
                endcase
            end
        end
    end

    // ======================================================================
    //  TILEMAP per-column fetch pipeline (reads the frozen snapshot buffers)
    //  Column-0 priming: the last 8-pixel window of each line (hc 376..383,
    //  all hblank) prefetches column 0 of the NEXT line using that line's py.
    // ======================================================================
    reg  [7:0] fs_scroll, fs_color;
    reg  [7:0] fs_p0, fs_p1, fs_p2;  reg [2:0] fs_pal;
    reg  [7:0] a_p0, a_p1, a_p2;     reg [2:0] a_pal;

    wire        last_win = (hc >= 9'd376);
    wire [8:0]  vc_next  = (vc==VTOTAL-1) ? 9'd0 : vc + 9'd1;
    wire [7:0]  sy_next  = vc_next[7:0];
    wire [7:0]  py_next  = flip_y ? (8'd255 - sy_next) : sy_next;

    //  Prefetch target column. The pipeline fetches the column that will be
    //  DISPLAYED during the next raster tile. Under flip_x the display column
    //  index (col = px[7:3] = 31-rcol) decreases as the raster advances, so the
    //  next-displayed column is col-1, not col+1. Column-0 priming likewise
    //  targets the first-displayed column of the next line (31 when flipped).
    wire [4:0]  fcol   = last_win ? (flip_x ? 5'd31 : 5'd0)
                                  : (flip_x ? (col - 5'd1) : (col + 5'd1));
    wire [7:0]  py_use = last_win ? py_next : py;
    wire [8:0]  nsrc_y = {1'b0,py_use} + {1'b0,fs_scroll};
    wire [4:0]  nrow   = nsrc_y[7:3];
    wire [2:0]  nline  = nsrc_y[2:0];

    //  Phase runs on the RASTER position sx[2:0] (always forward) so the
    //  fetch/latch/promote sequence keeps correct timing under flip_x. Flip is
    //  applied only to the column address (fcol) and the pixel bit-select
    //  (px[2:0], below). For flip_x=0, sx[2:0]==px[2:0] -> identical behaviour.
    always @(posedge clk) if (ce_pix) begin
        case (sx[2:0])
            3'd1: fs_scroll <= scroll_buf[fcol];                     // from snapshot
            3'd2: begin fs_color <= color_buf[fcol];                 // from snapshot
                        vram_addr <= {nrow, fcol}; end
            3'd3: tile_addr <= { {fs_color[7:5], vram_data}, nline};
            3'd4: begin fs_p0<=tile_p0; fs_p1<=tile_p1; fs_p2<=tile_p2; fs_pal<=fs_color[2:0]; end
            3'd7: if ((hc < 9'd256) || last_win) begin              // gate: no hblank clobber
                      a_p0<=fs_p0; a_p1<=fs_p1; a_p2<=fs_p2; a_pal<=fs_pal;
                  end
            default: ;
        endcase
    end

    wire [2:0] tpix = { a_p2[7 - px[2:0]],
                        a_p1[7 - px[2:0]],
                        a_p0[7 - px[2:0]] };
    wire [5:0] tile_pen = {a_pal, tpix};
    wire border_col = (col <= 5'd1) || (col >= 5'd30);

    // ======================================================================
    //  SPRITE ENGINE (line buffer)
    // ======================================================================
    wire [5:0] spr_pen; wire spr_opaque;
    //  disp_line is the RASTER line (not flipped). flip_y is fully baked into the
    //  engine's y_top (0x100-b0-16 vs b0), sfy and the in-char row select, exactly
    //  as MAME does; flipping disp_line too would double-apply and misplace sprites.
    wire [8:0] disp_line = {1'b0, sy};

    mirax_sprite_engine u_spr (
        .clk(clk), .rst(rst), .flip_x(flip_x), .flip_y(flip_y),
        .disp_line(disp_line), .line_start(line_start), .build_gate(1'b1),
        .spr_addr(spr_addr), .spr_data(spr_data),
        .sprom_addr(sprom_addr), .sprom_p0(sprom_p0), .sprom_p1(sprom_p1), .sprom_p2(sprom_p2),
        //  Buffer is built in FINAL screen X (sx=240-b3); read it at the raster
        //  pixel sx, not px, or flip_x cancels out and sprites stay unmirrored.
        .disp_x(sx), .pen(spr_pen), .opaque(spr_opaque)
    );

    // ======================================================================
    //  Compose: field -> sprite -> border field on top
    // ======================================================================
    wire [5:0] pen_sel =
        border_col                 ? tile_pen :
        (spr_opaque ? spr_pen : tile_pen);

    assign prom_addr = pen_sel;

    // ======================================================================
    //  Color PROM -> resistor-ladder DAC
    // ======================================================================
    // [SRC:MAME] weights 0x21/0x47/0x97 and 0x52/0xAD.
    // [HYP:AI H-021] PCB suggests 1K/470/270 (R,G), 470/270 (B)  [VERIFY]
    function [7:0] dac3; input b0,b1,b2;
        begin dac3 = (b0?8'h21:0)+(b1?8'h47:0)+(b2?8'h97:0); end endfunction
    function [7:0] dac2; input b0,b1;
        begin dac2 = (b0?8'h52:0)+(b1?8'hAD:0); end endfunction

    always @(posedge clk) if (ce_pix) begin
        if (h_active && v_active) begin
            red   <= dac3(prom_data[0], prom_data[1], prom_data[2]);
            green <= dac3(prom_data[3], prom_data[4], prom_data[5]);
            blue  <= dac2(prom_data[6], prom_data[7]);
        end else begin
            red<=8'h0; green<=8'h0; blue<=8'h0;
        end
    end

endmodule