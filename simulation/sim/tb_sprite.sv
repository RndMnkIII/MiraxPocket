// tb_sprite.sv - place ONE known sprite, dump frame, so we can measure where it
// lands and whether its shape is intact vs MAME's decode. No game ROMs needed.
`timescale 1ns/1ps
`default_nettype none
module tb_sprite;
    reg clk=0; always #5 clk=~clk;
    reg rst=1;
    reg [2:0] ced=0; wire ce_pix=(ced==0); always @(posedge clk) ced<=ced+1;

    wire [9:0] vram_a; wire [7:0] vram_q;
    wire [5:0] cram_a; wire [7:0] cram_q;
    wire [8:0] spr_a;  wire [7:0] spr_q;
    wire [13:0] tile_a; wire [7:0] tp0,tp1,tp2;
    wire [14:0] spro_a; wire [7:0] sp0,sp1,sp2;
    wire [5:0] prom_a; wire [7:0] prom_q;
    wire [7:0] r,g,b; wire hs,vs,hb,vb,vbr;

    mirax_video dut(.clk(clk),.ce_pix(ce_pix),.rst(rst),.flip_x(1'b0),.flip_y(1'b0),
        .vram_addr(vram_a),.vram_data(vram_q),.cram_addr(cram_a),.cram_data(cram_q),
        .spr_addr(spr_a),.spr_data(spr_q),
        .tile_addr(tile_a),.tile_p0(tp0),.tile_p1(tp1),.tile_p2(tp2),
        .sprom_addr(spro_a),.sprom_p0(sp0),.sprom_p1(sp1),.sprom_p2(sp2),
        .prom_addr(prom_a),.prom_data(prom_q),
        .red(r),.green(g),.blue(b),.hsync(hs),.vsync(vs),.hblank(hb),.vblank(vb),.vblank_rise(vbr));

    reg [7:0] vram[0:1023], cram[0:63], spr[0:511], prom[0:63];
    reg [7:0] trom0[0:16383],trom1[0:16383],trom2[0:16383];
    reg [7:0] srom0[0:32767],srom1[0:32767],srom2[0:32767];
    reg [7:0] vq,cq,sq,t0,t1,t2,s0,s1,s2,pq;
    always @(posedge clk) begin
        vq<=vram[vram_a]; cq<=cram[cram_a]; sq<=spr[spr_a];
        t0<=trom0[tile_a]; t1<=trom1[tile_a]; t2<=trom2[tile_a];
        s0<=srom0[spro_a]; s1<=srom1[spro_a]; s2<=srom2[spro_a];
        pq<=prom[prom_a];
    end
    assign vram_q=vq;assign cram_q=cq;assign spr_q=sq;
    assign tp0=t0;assign tp1=t1;assign tp2=t2;
    assign sp0=s0;assign sp1=s1;assign sp2=s2;assign prom_q=pq;

    integer i,rr,cc; reg [2:0] pv; integer by;
    // known sprite image: an "F" so orientation/flips are unambiguous
    // rows 0..15, cols 0..15 ; value 7 = F strokes, 0 = transparent
    reg [2:0] img [0:15][0:15];
    initial begin
        // background: tilemap all -> pen 0 ; make prom[0]=black, sprite pens bright
        for(i=0;i<1024;i=i+1) vram[i]=0;
        for(i=0;i<64;i=i+1) begin cram[i]=0; end
        for(i=0;i<16384;i=i+1) begin trom0[i]=0;trom1[i]=0;trom2[i]=0; end
        for(i=0;i<32768;i=i+1) begin srom0[i]=0;srom1[i]=0;srom2[i]=0; end
        // palette: pen index = {color[2:0],pix[2:0]} ; make color1/pix7 = white
        for(i=0;i<64;i=i+1) prom[i]=0;
        prom[6'b001_111]=8'b00_111_111; // color1 pix7 -> bright
        prom[6'b001_010]=8'b00_010_010; // color1 pix2 -> dim

        // build the "F" image (value 7 strokes)
        for(rr=0;rr<16;rr=rr+1) for(cc=0;cc<16;cc=cc+1) img[rr][cc]=0;
        for(rr=2;rr<14;rr=rr+1) img[rr][3]=3'd7;         // vertical stroke
        for(cc=3;cc<12;cc=cc+1) img[2][cc]=3'd7;         // top bar
        for(cc=3;cc<9;cc=cc+1)  img[7][cc]=3'd7;         // middle bar

        // encode img into srom planes using layout16 addressing
        for(rr=0;rr<16;rr=rr+1) for(cc=0;cc<16;cc=cc+1) begin
            by = ((rr<8)?rr:rr+8) + ((cc>=8)?8:0);   // byte within 32-byte char (tile 0)
            srom0[by][7-(cc%8)] = img[rr][cc][0];
            srom1[by][7-(cc%8)] = img[rr][cc][1];
            srom2[by][7-(cc%8)] = img[rr][cc][2];
        end

        // ONE sprite: b0=Y, b1=tile+flip, b2=color/bank, b3=X
        for(i=0;i<512;i=i+1) spr[i]=0;
        spr[0]=8'h80;  // b0 Y=128  -> screen y = 256-128-16 = 112
        spr[1]=8'h00;  // b1 tile low 0, fx=0, fy=0
        spr[2]=8'h01;  // b2 color=1, bank=0  -> offs=0
        spr[3]=8'h60;  // b3 X=96   -> screen x = 96

        repeat(20) @(posedge clk); rst=0;
    end

    // capture one frame
    integer x=0,y=0,fd; reg hbd;
    reg [7:0] R[0:256*239],G[0:256*239],B[0:256*239];
    always @(posedge clk) if(!rst && ce_pix) begin
        hbd<=hb;
        if(!hb&&!vb) begin if(x<256&&y<240) begin R[y*256+x]<=r;G[y*256+x]<=g;B[y*256+x]<=b; end x<=x+1; end
        if(hb&&!hbd) begin x<=0; if(y<240) y<=y+1; end
        if(vbr) begin
            fd=$fopen("sprite.ppm","w"); $fwrite(fd,"P3\n256 240\n255\n");
            for(y=0;y<240;y=y+1) for(x=0;x<256;x=x+1) $fwrite(fd,"%0d %0d %0d\n",R[y*256+x],G[y*256+x],B[y*256+x]);
            $fclose(fd); $display("sprite.ppm written"); $finish;
        end
    end
    initial begin #50000000; $display("timeout"); $finish; end
endmodule
`default_nettype wire
