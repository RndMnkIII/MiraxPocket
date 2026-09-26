// ============================================================================
//  tb_top.sv  -  Full-system testbench: load ROMs via $readmemh, run frames.
// ----------------------------------------------------------------------------
//  Preloads the core's ROMs directly (bypassing the ioctl download stream by
//  forcing region memories through $readmemh into rom_sp/rom_planes3 instances)
//  and runs the machine for N frames, dumping each active frame to PPM.
//
//  Requires a Verilog Z80 + jt49. The core instantiates T80pa (VHDL) and
//  jt49_bus (Verilog). For an iverilog-only flow, swap T80pa for a Verilog Z80
//  (e.g. tv80) via a thin adapter, or drive the mixed-language flow with GHDL +
//  Verilator. See sim/README.md. This TB focuses on the load + frame-dump
//  plumbing so it is ready the moment a Z80 is wired.
//
//  ROM hex files expected in ./rom/ (produced by rom_build.py):
//    prog.hex audio.hex tiles.hex sprites.hex proms.hex
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_top;
    reg clk48=0; always #10 clk48=~clk48;   // ~50 MHz sim
    reg reset=1;

    // controls: active-high; idle = all zero (no coin/inputs)
    reg [7:0] p1=8'h00, p2=8'h00;
    reg [7:0] dsw1=8'h00, dsw2=8'h04;        // demo sounds on, 3 lives, etc.

    wire [7:0] r,g,b; wire hs,vs,hb,vb; wire [9:0] audio;

    mirax_top dut(
        .clk48(clk48), .reset(reset),
        .p1_in(p1), .p2_in(p2), .dsw1(dsw1), .dsw2(dsw2),
        .vga_r(r), .vga_g(g), .vga_b(b),
        .hsync(hs), .vsync(vs), .hblank(hb), .vblank(vb),
        .audio(audio),
        .ioctl_download(1'b0), .ioctl_index(8'h0),
        .ioctl_wr(1'b0), .ioctl_addr(25'h0), .ioctl_data(8'h0)
    );

    // --- direct ROM preload (hierarchical $readmemh into the core memories) --
    // Adjust the hierarchical paths if you rename instances.
    initial begin
        $readmemh("rom/prog.hex",     dut.u_prog.mem);
        $readmemh("rom/audio.hex",    dut.u_srom.mem);
        // per-plane hex (produced by rom_build.py) load straight into the arrays
        $readmemh("rom/tiles_p0.hex", dut.u_tiles.m0);
        $readmemh("rom/tiles_p1.hex", dut.u_tiles.m1);
        $readmemh("rom/tiles_p2.hex", dut.u_tiles.m2);
        $readmemh("rom/sprites_p0.hex", dut.u_sprom.m0);
        $readmemh("rom/sprites_p1.hex", dut.u_sprom.m1);
        $readmemh("rom/sprites_p2.hex", dut.u_sprom.m2);
        $readmemh("rom/proms.hex",    dut.u_prom.mem);
        $display("ROMs preloaded.");
    end

    // --- reset release ------------------------------------------------------
    initial begin repeat(50) @(posedge clk48); reset=0; $display("reset released"); end

    // --- frame dumper -------------------------------------------------------
    integer x=0,y=0,frame=0,fd; reg hb_d;
    reg [7:0] R[0:256*240-1],G[0:256*240-1],B[0:256*240-1];
    always @(posedge clk48) begin
        hb_d<=hb;
        if(!reset && !hb && !vb) begin
            if(x<256 && y<240) begin R[y*256+x]<=r;G[y*256+x]<=g;B[y*256+x]<=b; end
            x<=x+1;
        end
        if(hb && !hb_d) begin x<=0; if(y<240) y<=y+1; end
        if(vb && !hb_d && y>=239) begin
            fd=$fopen($sformatf("frame_%0d.ppm",frame),"w");
            $fwrite(fd,"P3\n256 240\n255\n");
            for(y=0;y<240;y=y+1) for(x=0;x<256;x=x+1)
                $fwrite(fd,"%0d %0d %0d\n",R[y*256+x],G[y*256+x],B[y*256+x]);
            $fclose(fd); $display("wrote frame_%0d.ppm",frame);
            frame=frame+1; x=0; y=0;
            if(frame>=4) $finish;
        end
    end

    initial begin #200000000; $display("timeout"); $finish; end
endmodule

`default_nettype wire
