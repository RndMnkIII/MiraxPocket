// ============================================================================
//  tb_questa.sv  -  Continuous frame-dumping testbench for QuestaSim / ModelSim
// ----------------------------------------------------------------------------
//  Runs the full Mirax core (vendored tv80 + jt49) forever, writing every
//  active frame to a numbered binary PPM (P6): <dir>/frame_00000.ppm, ...
//
//  Frames are sampled on the core's real pixel enable (ce_pix, exposed by
//  mirax_top) so each pixel is captured exactly once.
//
//  Plusargs (all optional):
//    +DIR=frames        output directory (must already exist)
//    +FRAMES=0          stop after N frames (0 = run until you stop it)
//    +STRIDE=1          write every Nth frame (e.g. +STRIDE=6 ~ 10 fps)
//    +COIN_FRAME=60     frame at which to auto-insert a coin (0 = never)
//    +START_FRAME=90    frame at which to auto-press start (0 = never)
//    +DSW1=0x00 +DSW2=0x04   DIP switch bytes
//
//  Run (batch):
//    vsim -c -do run_questa.do
//  or interactively:
//    vsim work.tb_questa +FRAMES=0 +STRIDE=3 +DIR=frames -do "run -all"
//
//  Convert to PNG afterwards:   python3 ppm2png.py   (or feed frame_compare.py)
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_questa;

    // -------------------- clock / reset -------------------------------------
    reg clk48 = 0;
    always #10 clk48 = ~clk48;              // 50 MHz sim clock (functional)
    reg reset = 1;

    // -------------------- plusargs ------------------------------------------
    integer FRAMES, STRIDE, COIN_F, START_F, AUDIO_DIV;
    reg [7:0] DSW1, DSW2;
    reg [1023:0] DIR;
    reg AUDIO_EN;
    initial begin
        if (!$value$plusargs("DIR=%s",   DIR))     DIR     = "frames";
        if (!$value$plusargs("FRAMES=%d",FRAMES))  FRAMES  = 0;      // 0 = forever
        if (!$value$plusargs("STRIDE=%d",STRIDE))  STRIDE  = 1;
        if (!$value$plusargs("COIN_FRAME=%d",COIN_F))  COIN_F  = 60;
        if (!$value$plusargs("START_FRAME=%d",START_F))START_F = 90;
        if (!$value$plusargs("DSW1=%h",  DSW1))     DSW1    = 8'h00;
        if (!$value$plusargs("DSW2=%h",  DSW2))     DSW2    = 8'h04; // demo sounds on
        // audio: sample every AUDIO_DIV design-clocks. WAV rate = 48e6/AUDIO_DIV.
        //   1000 -> 48 kHz.  0 disables audio capture.
        if (!$value$plusargs("AUDIO_DIV=%d",AUDIO_DIV)) AUDIO_DIV = 1000;
        AUDIO_EN = (AUDIO_DIV != 0);
        if (STRIDE < 1) STRIDE = 1;
    end

    // -------------------- inputs (active-high, P1 bit order) ----------------
    //  P1: b0 DOWN, b1 START1, b2 LEFT, b3 RIGHT, b4 BUTTON1, b5 UP, b6 COIN1, b7 COIN2
    reg [7:0] p1 = 8'h00, p2 = 8'h00;

    // -------------------- DUT -----------------------------------------------
    wire [7:0] r,g,b; wire hs,vs,hb,vb,ce_pix; wire [9:0] audio;

    mirax_top dut(
        .clk48(clk48), .reset(reset),
        .p1_in(p1), .p2_in(p2), .dsw1(DSW1), .dsw2(DSW2),
        .vga_r(r), .vga_g(g), .vga_b(b),
        .hsync(hs), .vsync(vs), .hblank(hb), .vblank(vb), .ce_pix(ce_pix),
        .audio(audio),
        .ioctl_download(1'b0), .ioctl_index(8'h0),
        .ioctl_wr(1'b0), .ioctl_addr(25'h0), .ioctl_data(8'h0)
    );

    // -------------------- ROM preload (hierarchical $readmemh) --------------
    initial begin
        #1;
        $readmemh("rom/prog.hex",       dut.u_prog.mem);
        $readmemh("rom/audio.hex",      dut.u_srom.mem);
        $readmemh("rom/tiles_p0.hex",   dut.u_tiles.m0);
        $readmemh("rom/tiles_p1.hex",   dut.u_tiles.m1);
        $readmemh("rom/tiles_p2.hex",   dut.u_tiles.m2);
        $readmemh("rom/sprites_p0.hex", dut.u_sprom.m0);
        $readmemh("rom/sprites_p1.hex", dut.u_sprom.m1);
        $readmemh("rom/sprites_p2.hex", dut.u_sprom.m2);
        $readmemh("rom/proms.hex",      dut.u_prom.mem);
        $display("[tb_questa] ROMs preloaded. DIR=%0s FRAMES=%0d STRIDE=%0d",
                 DIR, FRAMES, STRIDE);
        repeat (64) @(posedge clk48);
        reset = 0;
        $display("[tb_questa] reset released");
    end

    // -------------------- frame buffer + capture ----------------------------
    localparam W = 256, H = 240;
    reg [7:0] fbr [0:W*H-1], fbg [0:W*H-1], fbb [0:W*H-1];
    integer x=0, y=0, frame=0, written=0;
    reg vb_d;

    // auto coin/start injection (a few-frame pulse each)
    always @(posedge clk48) if (ce_pix && vb && !vb_d) begin      // once per frame
        p1[6] <= (COIN_F  != 0) && (frame >= COIN_F)  && (frame < COIN_F+3);
        p1[1] <= (START_F != 0) && (frame >= START_F) && (frame < START_F+3);
    end

    // pixel capture: sample on ce_pix, one write per active pixel
    always @(posedge clk48) begin
        if (reset) begin x<=0; y<=0; end
        else if (ce_pix) begin
            vb_d <= vb;
            if (!hb && !vb) begin
                if (x < W && y < H) begin
                    fbr[y*W+x] <= r; fbg[y*W+x] <= g; fbb[y*W+x] <= b;
                end
                x <= x + 1;
            end
            // end of visible line: hblank rising while not in vblank
            if (hb && !vb && x != 0) begin x <= 0; if (y < H) y <= y + 1; end
            // start of vblank -> frame complete
            if (vb && !vb_d) begin
                dump_frame(frame);
                frame <= frame + 1;
                x <= 0; y <= 0;
                if (FRAMES != 0 && frame+1 >= FRAMES) begin
                    $display("[tb_questa] reached %0d frames, finishing", FRAMES);
                    $finish;
                end
            end
        end
    end

    // -------------------- audio capture -> raw s16le PCM --------------------
    //  Streams to <DIR>/audio.pcm.  Convert to WAV afterwards:
    //     python3 pcm2wav.py frames/audio.pcm          (rate 48000 default)
    //   or:  ffmpeg -f s16le -ar 48000 -ac 1 -i audio.pcm audio.wav
    //  The 10-bit unsigned core output (DC ~512) is centered and scaled to s16.
    integer fd_pcm = 0, acnt = 0;
    reg signed [15:0] asample;
    initial begin
        #2;
        if (AUDIO_EN) begin
            fd_pcm = $fopen({DIR, "/audio.pcm"}, "wb");
            if (fd_pcm == 0) $display("[tb_questa] WARNING: cannot open audio.pcm");
            else $display("[tb_questa] audio -> %0s/audio.pcm @ %0d Hz",
                          DIR, 48000000/AUDIO_DIV);
        end
    end
    always @(posedge clk48) if (!reset && AUDIO_EN && fd_pcm != 0) begin
        if (acnt == AUDIO_DIV-1) begin
            acnt <= 0;
            // (audio - 512) << 6  -> signed 16-bit
            asample = $signed({1'b0, audio} - 11'sd512) <<< 6;
            $fwrite(fd_pcm, "%c%c", asample[7:0], asample[15:8]);  // little-endian
        end else acnt <= acnt + 1;
    end

    // -------------------- binary PPM writer ---------------------------------
    task dump_frame(input integer fn);
        integer fd, i; reg [8*256:1] path;
        begin
            if (fn % STRIDE != 0) disable dump_frame;   // honor stride
            $sformat(path, "%0s/frame_%05d.ppm", DIR, fn);
            fd = $fopen(path, "wb");
            if (fd == 0) begin $display("cannot open %0s", path); disable dump_frame; end
            $fwrite(fd, "P6\n%0d %0d\n255\n", W, H);
            for (i = 0; i < W*H; i = i + 1)
                $fwrite(fd, "%c%c%c", fbr[i], fbg[i], fbb[i]);
            $fclose(fd);
            written = written + 1;
            if (written % 30 == 0)
                $display("[tb_questa] frame %0d written (%0d total)", fn, written);
        end
    endtask

    // flush/close the PCM stream on finish
    final begin
        if (fd_pcm != 0) $fclose(fd_pcm);
    end

endmodule

`default_nettype wire
