// ============================================================================
//  mirax_sprite_engine.sv  -  Per-line sprite renderer (74S201 line-buffer model)
// ----------------------------------------------------------------------------
//  Replaces the discrete 74S201 (256x1 x6) sprite line buffer + the LS-glue
//  that walks sprite RAM. Double-buffered: while one buffer feeds the current
//  scanline, the other is (re)built for the next line across the whole line
//  time, then the two swap at line start.
//
//  Sprite record (4 bytes in spriteram, 128 records, MAME draw_sprites):
//    b0 = Y
//    b1 = tile low + flips : bit6 fx (guess), bit7 fy (guess)
//    b2 = color/bank       : color = b2[2:0]
//    b3 = X
//  spr_offs = (b1 & 0x3f) + ((b2 & 0xe0) << 1) + ((b2 & 0x10) << 5)
//  cull:  b0==0 || b3==0  -> skip
//  y = flip_y ? b0            : 0x100 - b0 - 16
//  x = flip_x ? 240 - b3      : b3
//  fx = flip_x ^ b1[6];  fy = flip_y ^ b1[7]
//
//  Sprite gfx = 16x16, 3bpp planar, layout16:
//    each 16x16 char = 32 bytes/plane; plane regions at RGN_FRAC(0,1,2 /3).
//    byte(char,row r,col c) = char*32 + rowbyte + (c>=8 ? 8 : 0)
//        rowbyte = (r < 8) ? r : r + 8
//    pixel bit = 7 - (c & 7)      (MSB-first within the byte)
//    plane bit weight: p0=LSB, p1, p2=MSB  (pen[2:0] = {p2,p1,p0})
//  pen 0 (all planes 0) = transparent.
//
//  TIMING NOTE: build runs during the current line (double buffer) so it has a
//  full ~line of clk48 cycles. If the on-line sprite workload exceeds the line
//  budget the tail is dropped - which is the natural per-line sprite limit of
//  the real 74S201 buffer. Flag for cycle-exact tuning against the board.
// ============================================================================
`default_nettype none

module mirax_sprite_engine
(
    input  wire        clk,          // 48 MHz
    input  wire        rst,
    input  wire        flip_x,
    input  wire        flip_y,

    // line context
    input  wire [8:0]  disp_line,    // line currently being displayed (0..255)
    input  wire        line_start,   // 1-cycle pulse at the very start of a line
    input  wire        build_gate,   // high during the window we may build in

    // sprite RAM read port (0x200 bytes)
    output reg  [8:0]  spr_addr,
    input  wire [7:0]  spr_data,

    // sprite ROM (3 planes, 15-bit each)
    output reg  [14:0] sprom_addr,
    input  wire [7:0]  sprom_p0,
    input  wire [7:0]  sprom_p1,
    input  wire [7:0]  sprom_p2,

    // display read: pen for the current pixel x on the displayed line
    input  wire [7:0]  disp_x,
    output wire [5:0]  pen,
    output wire        opaque
);
    // -------------------- double line buffers -------------------------------
    // each entry: {opaque, pen[5:0]}  (pen carries palette<<3? no: sprite uses
    // its own 3-bit palette 'color' + 3-bit pixel -> 6-bit pen index into PROM)
    reg [6:0] bufA [0:255];
    reg [6:0] bufB [0:255];
    reg       disp_sel;               // 0: display A / build B ; 1: swap

    // display read (combinational-ish, registered by consumer)
    wire [6:0] disp_word = disp_sel ? bufB[disp_x] : bufA[disp_x];
    assign opaque = disp_word[6];
    assign pen    = disp_word[5:0];

    // -------------------- build target = next line --------------------------
    wire [8:0] build_line = disp_line + 9'd1;

    // -------------------- build FSM -----------------------------------------
    localparam S_IDLE=0, S_CLR=1, S_R0=2, S_R1=3, S_R2=4, S_R3=5,
               S_TEST=6, S_PREP=7, S_FETCH=8, S_WAIT=9, S_WRITE=10, S_NEXT=11,
               S_R4=12;
    reg [3:0] st;
    reg [7:0] clr_i;
    reg [7:0] idx;                    // sprite index 0..127
    reg [7:0] b0,b1,b2,b3;
    reg [9:0] offs;
    reg [2:0] scolor;
    reg       sfx, sfy;
    reg [7:0] sy, sx;
    reg [3:0] row;                    // 0..15 within sprite (post-flip)
    reg [4:0] cc;                     // column 0..15 (+guard)
    reg [7:0] dst_x;

    // which buffer are we building into?
    wire build_is_B = ~disp_sel;      // display A -> build B

    task write_buf(input [7:0] xa, input [6:0] word);
        begin
            if (build_is_B) bufB[xa] <= word;
            else            bufA[xa] <= word;
        end
    endtask

    // sprite row hit test against build_line
    // y = flip_y ? b0 : 0x100 - b0 - 16 ; sprite spans [y, y+16)
    wire [8:0] y_top = flip_y ? {1'b0,b0} : (9'h100 - {1'b0,b0} - 9'd16);
    wire [8:0] rel   = build_line - y_top;
    wire       on_line = (rel < 9'd16);

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; disp_sel <= 1'b0; clr_i <= 8'd0; idx <= 8'd0;
        end else begin
            // swap buffers at each new line, then start a fresh build
            if (line_start) begin
                disp_sel <= ~disp_sel;
                st    <= S_CLR;
                clr_i <= 8'd0;
                idx   <= 8'd0;
            end else begin
                case (st)
                // ---- clear the build buffer to transparent ----------------
                S_CLR: begin
                    write_buf(clr_i, 7'd0);
                    if (clr_i == 8'd255) st <= S_R0;
                    clr_i <= clr_i + 8'd1;
                end
                // ---- read 4 sprite bytes -----------------------------------
                //  2-cycle read latency (spr_addr reg + RAM output reg): the
                //  byte for an address issued in state N is valid in state N+2.
                S_R0: begin spr_addr <= {idx,2'b00}; st <= S_R1; end   // issue byte0
                S_R1: begin spr_addr <= {idx,2'b01}; st <= S_R2; end   // issue byte1
                S_R2: begin b0 <= spr_data; spr_addr <= {idx,2'b10}; st <= S_R3; end // byte0 valid
                S_R3: begin b1 <= spr_data; spr_addr <= {idx,2'b11}; st <= S_R4; end // byte1 valid
                S_R4: begin b2 <= spr_data; st <= S_TEST; end          // byte2 valid
                S_TEST: begin
                    b3 <= spr_data;                                    // byte3 valid
                    // cull + on-line test (b0 valid since S_R2; b3 = spr_data now)
                    if (b0==8'd0 || spr_data==8'd0 || !on_line) st <= S_NEXT;
                    else st <= S_PREP;
                end
                // ---- decode geometry --------------------------------------
                S_PREP: begin
                    // offs = (b1&0x3f) + b2[7:5]*64 + b2[4]*512   (max 1023)
                    offs   <= {4'b0, b1[5:0]} + {1'b0, b2[7:5], 6'b0}
                                             + (b2[4] ? 10'd512 : 10'd0);
                    scolor <= b2[2:0];
                    sfx    <= flip_x ^ b1[6];
                    sfy    <= flip_y ^ b1[7];
                    sx     <= flip_x ? (8'd240 - b3) : b3;
                    row    <= (flip_y ^ b1[7]) ? (4'd15 - rel[3:0]) : rel[3:0];
                    cc     <= 5'd0;
                    st     <= S_FETCH;
                end
                // ---- per-column fetch + write -----------------------------
                S_FETCH: begin
                    // column after fx flip
                    // byte = offs*32 + rowbyte + (c>=8?8:0), rowbyte=(r<8)?r:r+8
                    // build a 15-bit plane byte address
                    st <= S_WAIT;
                end
                S_WAIT: st <= S_WRITE;   // 1-cycle ROM read latency
                S_WRITE: begin
                    // extract pixel bit 7-(c&7) from each plane
                    // (sprom_pX already reflect sprom_addr set in S_FETCH)
                    begin : do_write
                        reg [2:0] pix;
                        reg [7:0] xa;
                        reg [3:0] cflip;
                        cflip = sfx ? (4'd15 - cc[3:0]) : cc[3:0];
                        pix = { sprom_p2[7-(cflip[2:0])],
                                sprom_p1[7-(cflip[2:0])],
                                sprom_p0[7-(cflip[2:0])] };
                        xa  = sx + cc[3:0];
                        if (pix != 3'd0)
                            write_buf(xa, {1'b1, scolor, pix});
                    end
                    if (cc == 5'd15) st <= S_NEXT;
                    else begin cc <= cc + 5'd1; st <= S_FETCH; end
                end
                // ---- next sprite ------------------------------------------
                S_NEXT: begin
                    if (idx == 8'd127) st <= S_IDLE;
                    else begin idx <= idx + 8'd1; st <= S_R0; end
                end
                default: st <= S_IDLE;
                endcase
            end
        end
    end

    // sprite ROM address for the column being fetched (registered next edge)
    // rowbyte = (row<8)? row : row+8 ; +8 for right half (cflip>=8)
    wire [3:0] cflip_a = sfx ? (4'd15 - cc[3:0]) : cc[3:0];
    wire [7:0] rowbyte = (row < 4'd8) ? {4'd0,row} : ({4'd0,row} + 8'd8);
    // char*32 = {offs,5'b0}; + rowbyte + 8 for the right 8-column half
    wire [14:0] sbyte  = {offs, 5'b0} + {7'b0,rowbyte} + (cflip_a[3] ? 15'd8 : 15'd0);
    always @(posedge clk) sprom_addr <= sbyte;

endmodule

`default_nettype wire
