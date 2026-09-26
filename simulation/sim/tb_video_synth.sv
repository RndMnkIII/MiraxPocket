// ============================================================================
//  tb_video_synth.sv  -  Module-level testbench for mirax_video (no CPU/ROMs)
// ----------------------------------------------------------------------------
//  Drives mirax_video with behavioral, pre-initialized memories (synthetic
//  tilemap + palette) to exercise the timing generator, the per-column scroll
//  tilemap pipeline and the resistor-ladder DAC end-to-end, then dumps one
//  active frame to a PPM. Proves the video datapath independently of the Z80
//  and the copyrighted ROMs.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_video_synth;
    reg clk=0; always #5 clk=~clk;          // 100 MHz sim clock (stands in for 48M)
    reg rst=1;

    // 6 MHz-ish pixel enable: 1 in every 8 clocks
    reg [2:0] ced=0; wire ce_pix = (ced==3'd0);
    always @(posedge clk) ced <= ced+3'd1;

    // DUT wires
    wire [9:0] vram_a; wire [7:0] vram_q;
    wire [5:0] cram_a; wire [7:0] cram_q;
    wire [8:0] spr_a;  wire [7:0] spr_q;
    wire [13:0] tile_a; wire [7:0] tp0,tp1,tp2;
    wire [14:0] spro_a; wire [7:0] sp0,sp1,sp2;
    wire [5:0] prom_a; wire [7:0] prom_q;
    wire [7:0] r,g,b; wire hs,vs,hb,vb,vbr;

    mirax_video dut(
        .clk(clk), .ce_pix(ce_pix), .rst(rst),
        .flip_x(1'b0), .flip_y(1'b0),
        .vram_addr(vram_a), .vram_data(vram_q),
        .cram_addr(cram_a), .cram_data(cram_q),
        .spr_addr(spr_a),   .spr_data(spr_q),
        .tile_addr(tile_a), .tile_p0(tp0), .tile_p1(tp1), .tile_p2(tp2),
        .sprom_addr(spro_a),.sprom_p0(sp0), .sprom_p1(sp1), .sprom_p2(sp2),
        .prom_addr(prom_a), .prom_data(prom_q),
        .red(r), .green(g), .blue(b),
        .hsync(hs), .vsync(vs), .hblank(hb), .vblank(vb), .vblank_rise(vbr)
    );

    // ---- behavioral memories (registered read, 1-cycle latency) ------------
    reg [7:0] vram[0:1023];
    reg [7:0] cram[0:63];
    reg [7:0] spr [0:511];
    reg [7:0] trom0[0:16383], trom1[0:16383], trom2[0:16383];
    reg [7:0] prom[0:63];
    reg [7:0] vq,cq,sq,t0,t1,t2,pq;
    always @(posedge clk) begin
        vq<=vram[vram_a]; cq<=cram[cram_a]; sq<=spr[spr_a];
        t0<=trom0[tile_a]; t1<=trom1[tile_a]; t2<=trom2[tile_a];
        pq<=prom[prom_a];
    end
    assign vram_q=vq; assign cram_q=cq; assign spr_q=sq;
    assign tp0=t0; assign tp1=t1; assign tp2=t2; assign prom_q=pq;
    assign sp0=8'h0; assign sp1=8'h0; assign sp2=8'h0; // sprites off in this TB

    integer i, tx, ty, row, cbit;
    reg [2:0] pv;
    initial begin
        // --- tilemap: tile code = row+col; palette ramps by column; scroll wave
        for (i=0;i<1024;i=i+1) vram[i] = (( (i/32) + (i%32) ) & 8'hFF);
        for (i=0;i<32;i=i+1) begin
            cram[i*2]   = (i*4) & 8'hFF;          // per-column scroll (visible wave)
            cram[i*2+1] = (i & 3'h7);             // palette 0..7, bank 0
        end
        for (i=0;i<512;i=i+1) spr[i]=8'h0;

        // --- tile gfx: build a recognizable 8x8 glyph per tile: a border box +
        //     intensity = low 3 bits of tile index, so tiles show as colored cells
        for (i=0;i<16384;i=i+1) begin
            trom0[i]=8'h00; trom1[i]=8'h00; trom2[i]=8'h00;
        end
        // tile index t (0..2047), line l (0..7): byte addr = t*8 + l
        for (tx=0; tx<2048; tx=tx+1) begin
            for (row=0; row<8; row=row+1) begin
                // pixel value pv = (edge of cell)?7:(t&7)
                for (cbit=0; cbit<8; cbit=cbit+1) begin
                    if (row==0 || row==7 || cbit==0 || cbit==7) pv = 3'd7;
                    else pv = tx[2:0];
                    // set plane bits at position (7-cbit)
                    trom0[tx*8+row][7-cbit] = pv[0];
                    trom1[tx*8+row][7-cbit] = pv[1];
                    trom2[tx*8+row][7-cbit] = pv[2];
                end
            end
        end

        // --- palette PROM: pen = {pal[2:0], pix[2:0]} -> spread RGB
        for (i=0;i<64;i=i+1) begin
            // R from pix bits, G from pal bits, B a mix -> distinct per pen
            prom[i] = { (i[1:0]) ,                 // B[7:6]
                        (i[5:3]) ,                 // G[5:3]
                        (i[2:0]) };                // R[2:0]
        end

        repeat(20) @(posedge clk);
        rst=0;
    end

    // ---- frame capture to PPM ----------------------------------------------
    integer fd, x, y, framecnt=0;
    reg [7:0] fb_r[0:256*240-1], fb_g[0:256*240-1], fb_b[0:256*240-1];
    reg hb_d;
    initial begin x=0; y=0; end

    always @(posedge clk) if (!rst && ce_pix) begin
        hb_d <= hb;
        if (!hb && !vb) begin
            if (x<256 && y<240) begin
                fb_r[y*256+x]<=r; fb_g[y*256+x]<=g; fb_b[y*256+x]<=b;
            end
            x <= x+1;
        end
        if (hb && !hb_d) begin x<=0; if (y<240) y<=y+1; end   // end of line
        if (vbr) begin
            // write frame
            fd=$fopen("frame.ppm","w");
            $fwrite(fd,"P3\n256 240\n255\n");
            for (y=0;y<240;y=y+1) for (x=0;x<256;x=x+1)
                $fwrite(fd,"%0d %0d %0d\n", fb_r[y*256+x], fb_g[y*256+x], fb_b[y*256+x]);
            $fclose(fd);
            $display("frame written: frame.ppm");
            $finish;
        end
    end

    // safety timeout
    initial begin #40000000; $display("timeout"); $finish; end
endmodule

`default_nettype wire
