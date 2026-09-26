// ============================================================================
//  mirax_video.sv  -  Video engine (tilemap + sprite engine + color PROM DAC)
// ----------------------------------------------------------------------------
//  Screen 256x256, visible x 0..255 / y 8..247, ROT90, 60 Hz.
//
//  Tilemap (MAME draw_tilemap, exact):
//    tile   = videoram[32*y + x]
//    scroll = colorram[x*2]          (per-column vertical scroll)   <-- byte A
//    lowcol = colorram[x*2 + 1]                                     <-- byte B
//    tile_index = {lowcol[7:5], tile}     ((color & 0xe0)<<3 | code)
//    palette    = lowcol[2:0]
//    res_y = y*8 - scroll   ->  source row = (py + scroll)
//    -> colorram MUST be read as TWO bytes per column (fixed vs first draft).
//
//  Sprites: handled by mirax_sprite_engine (74S201 line-buffer model).
//
//  Priority (MAME screen_update): draw field (cols 2..29), then sprites, then
//  border cols 0,1,30,31 ON TOP -> HUD/score above sprites.
//
//  Color: 0x40 pens from 2x 82S123. DAC = resistor ladder (270/470/1K + 470x22).
//  prom byte = R[2:0] G[5:3] B[7:6]. Weights below are MAME's approximations;
//  swap for metered ladder values when available.
//
//  Per-column fetch pipeline runs on clk48 (8 clk48 per pixel), leaving ample
//  time for the 2-byte colorram read + tile ROM fetch ahead of each column.
// ============================================================================
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
    output reg  [ 5:0] cram_addr,
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
    //  H/V timing (74LS161/393 chain). 384x264 @ ~6.08 MHz -> ~60 Hz.
    // ======================================================================
    localparam HTOTAL=384, HSYNC_S=296, HSYNC_E=342;
    localparam VTOTAL=264, VSYNC_S=240, VSYNC_E=244;

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
    //  TILEMAP per-column fetch pipeline
    //  At the start of each 8-pixel column, read colorram twice (scroll,color),
    //  compute source row/line, fetch VRAM tile code, then tile ROM planes.
    //  Registers t_* hold the resolved column data used across its 8 pixels.
    // ======================================================================
    // --- LOOKAHEAD per-column fetch -----------------------------------------
    //  While displaying column `col`, prefetch column `col+1` (wraps 31->0
    //  within the SAME scanline), so all 8 pixels of every column use data
    //  fetched for THAT column. Fetched planes/palette are promoted into the
    //  "active" registers at the column boundary (phase 7).
    //
    //  Fetch sequence (ncol = next column), one read per pixel phase:
    //    p0 addr scroll  p1 latch scroll + addr color   p2 latch color + addr vram
    //    p3 form tile_addr   p4 latch tile planes   p7 promote to active regs
    reg  [7:0] fs_scroll, fs_color;
    reg  [7:0] fs_p0, fs_p1, fs_p2;  reg [2:0] fs_pal;
    reg  [7:0] a_p0, a_p1, a_p2;     reg [2:0] a_pal;

    wire [4:0] ncol   = col + 5'd1;                       // 31 -> 0 (same line)
    wire [8:0] nsrc_y = {1'b0,py} + {1'b0,fs_scroll};     // per-column scroll add
    wire [4:0] nrow   = nsrc_y[7:3];
    wire [2:0] nline  = nsrc_y[2:0];

    always @(posedge clk) if (ce_pix) begin
        case (px[2:0])
            3'd0: cram_addr <= {ncol,1'b0};                          // scroll byte
            3'd1: begin fs_scroll <= cram_data; cram_addr <= {ncol,1'b1}; end // color byte
            3'd2: begin fs_color  <= cram_data; vram_addr <= {nrow, ncol}; end
            3'd3: tile_addr <= { {fs_color[7:5], vram_data}, nline}; // tile_index*8 + line
            3'd4: begin fs_p0<=tile_p0; fs_p1<=tile_p1; fs_p2<=tile_p2; fs_pal<=fs_color[2:0]; end
            3'd7: begin a_p0<=fs_p0; a_p1<=fs_p1; a_p2<=fs_p2; a_pal<=fs_pal; end
            default: ;
        endcase
    end

    // display uses the ACTIVE (already-complete) column registers
    wire [2:0] tpix = { a_p2[7 - px[2:0]],
                        a_p1[7 - px[2:0]],
                        a_p0[7 - px[2:0]] };
    wire [5:0] tile_pen = {a_pal, tpix};
    wire border_col = (col <= 5'd1) || (col >= 5'd30);

    // ======================================================================
    //  SPRITE ENGINE (line buffer)
    // ======================================================================
    wire [5:0] spr_pen; wire spr_opaque;
    wire [8:0] disp_line = flip_y ? (9'd255 - {1'b0,sy}) : {1'b0,sy};

    mirax_sprite_engine u_spr (
        .clk(clk), .rst(rst), .flip_x(flip_x), .flip_y(flip_y),
        .disp_line(disp_line), .line_start(line_start), .build_gate(1'b1),
        .spr_addr(spr_addr), .spr_data(spr_data),
        .sprom_addr(sprom_addr), .sprom_p0(sprom_p0), .sprom_p1(sprom_p1), .sprom_p2(sprom_p2),
        .disp_x(px), .pen(spr_pen), .opaque(spr_opaque)
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