//============================================================================
// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Javier (RndMnkIII)
//
// Project  : Mirax (Current Technology, 1985) - arcade core for Analogue Pocket
// Module   : mirax_sound.sv
// Summary  : Sound CPU subsystem (NEC D780C-1 Z80 + 2x AY-3-8912)
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
//     H-002 [HYP]     AY-3-8912 clock = 12/4 = 3 MHz (MAME). Some CTI boards use /6 = 2 MHz.
//     H-008 [HYP:AI]  Sound work RAM = HM6116 at P2 (chosen by proximity to S2).
//     H-009 [HYP:AI]  Sound command latch = 74LS273 (P3) + 74LS245 (O4) buffer.
//     H-010 [HYP]     Both AY-3-8912 are mixed through identical 1K resistors (equal
//                     weight). Resistors identified in photos; wiring not traced.
//   Sources:
//     [SRC:MAME] sound memory map, AY ports, NMI on command, IRQ 4x60 Hz
//     [SRC:PCB S2,R2,R4,S4] D780C-1, 2764 sound EPROM, 2x AY-3-8912 (silkscreen)
//   Known issues / notes:
//     Description says the 1K mix was 'verified from PCB'; it was identified in
//     photos only (see H-010). Wording kept, status downgraded here.
//----------------------------------------------------------------------------
// Status: UNDER VALIDATION . Confidence: MEDIUM
// Open hypotheses: H-002, H-008, H-009, H-010
//============================================================================
// DESCRIPTION
//  Board: D780C-1 (S2), HM6116LP-3 2Kx8 (P2), 2x GI AY-3-8912 (R4/S4),
//         M5L2764 8Kx8 sound EPROM (R2, = mxr2).
//
//  Sound map (MAME misc/mirax.cpp):
//    0000-1FFF  R   sound ROM (8K)
//    8000-8FFF  RW  work RAM (HM6116, only 2K used)
//    A000       R   sound latch (command from main CPU)
//    E003       W   AY1 data     |  the '3' selects BDIR+BC1 on the board decode;
//    E403       W   AY2 data     |  E000/E001/E400/E401 are the inactive combos
//    F900-F9FF  W   AY register-address latch (offset = register number)
//
//  Two AY-3-8912 = AY-3-8910 with only I/O port A bonded out (unused here).
//  Clock: MAME uses 12MHz/4 = 3 MHz. (Open item: confirm the real divider off
//  the 12 MHz xtal against the board; some CTI boards run the AY at /6 = 2 MHz.)
//  IRQ: periodic /IRQ at 4*60 Hz (set_periodic_int); /NMI pulsed on each command.
//
//  Mixing (verified from PCB CT805-3): the two AY outputs use identical 1K
//  resistors -> equal-weight mix. `sound_sum` exposes the full 11-bit ay1+ay2
//  (no premature /2) for the output-stage model in mirax_audio_out.
//============================================================================
`default_nettype none

module mirax_sound
(
    input  wire        clk,
    input  wire        cen,          // 3 MHz enable (12MHz/4)
    input  wire        cen_3m180,    // 3 MHz enable (12MHz/4, 180 deg phase)
    input  wire        cen_ay,       // AY enable (see note above; default = cen)
    input  wire        rst,

    input  wire [ 7:0] sound_cmd,
    input  wire        sound_cmd_wr, // strobe from main side -> /NMI pulse
    input  wire        irq_tick,     // 240 Hz periodic tick -> /IRQ hold

    // sound ROM
    output wire [12:0] rom_addr,
    input  wire [ 7:0] rom_data,

    output wire [ 9:0] sound_out,    // mixed unsigned/centered PCM (legacy, /2)
    output wire [10:0] sound_sum     // full 11-bit equal-weight mix (ay1+ay2)
);

    // -------------------- Z80 core ------------------------------------------
    wire [15:0] addr;
    wire [ 7:0] din, dout;
    wire        mreq_n, iorq_n, rd_n, wr_n, m1_n;
    reg         nmi_n, irq_n;

    T80pa u_cpu (
        .RESET_n (~rst),
        .CLK     (clk),
        .CEN_p   (cen),
        .CEN_n   (cen_3m180),
        .WAIT_n  (1'b1),
        .INT_n   (irq_n),
        .NMI_n   (nmi_n),
        .BUSRQ_n (1'b1),
        .M1_n    (m1_n),
        .MREQ_n  (mreq_n),
        .IORQ_n  (iorq_n),
        .RD_n    (rd_n),
        .WR_n    (wr_n),
        .A       (addr),
        .DI      (din),
        .DO      (dout)
    );

    wire wr = ~wr_n & ~mreq_n;
    wire rd = ~rd_n & ~mreq_n;

    // -------------------- decode --------------------------------------------
    wire cs_rom  = (addr <= 16'h1FFF);
    wire cs_ram  = (addr[15:12] == 4'h8);          // 8000-8FFF (2K used)
    wire cs_lat  = (addr == 16'hA000);
    wire cs_ay1d = (addr == 16'hE003);
    wire cs_ay2d = (addr == 16'hE403);
    wire cs_ayad = (addr[15:8] == 8'hF9);          // F900-F9FF addr latch

    assign rom_addr = addr[12:0];

    // -------------------- work RAM (2Kx8) -----------------------------------
    reg [7:0] ram [0:2047];
    reg [7:0] ram_dout;
    always @(posedge clk) if (cen) begin
        if (cs_ram & wr) ram[addr[10:0]] <= dout;
        ram_dout <= ram[addr[10:0]];
    end

    assign din = cs_rom ? rom_data :
                 cs_ram ? ram_dout :
                 cs_lat ? sound_cmd :
                 8'hFF;

    // -------------------- AY address latch ----------------------------------
    reg [7:0] ay_addr_latch;
    always @(posedge clk) if (cen) begin
        if (cs_ayad & wr) ay_addr_latch <= addr[7:0]; // offset carries register #
    end

    // -------------------- two AY-3-8912 (jt49) ------------------------------
    // Driven in "address then data" style: on a data write we first present the
    // latched register number with BDIR/BC1=address, then the data. jt49 exposes
    // a combined bus; we emulate the two-phase access with a tiny sequencer.
    wire [9:0] ay1_snd, ay2_snd;

    ay_writeport u_ay1 (
        .clk(clk), .cen(cen_ay), .rst(rst),
        .reg_num(ay_addr_latch), .data(dout),
        .wr(cs_ay1d & wr & cen), .sound(ay1_snd)
    );
    ay_writeport u_ay2 (
        .clk(clk), .cen(cen_ay), .rst(rst),
        .reg_num(ay_addr_latch), .data(dout),
        .wr(cs_ay2d & wr & cen), .sound(ay2_snd)
    );

    // equal-weight sum of the two chips (matches identical 1K mix resistors).
    // sound_sum = full 11-bit (0..2046) for mirax_audio_out; sound_out keeps the
    // legacy /2 10-bit for any consumer that still expects it.
    // [HYP H-010] equal-weight mix (identical 1K resistors)  [VERIFY]
    wire [10:0] mix = {1'b0, ay1_snd} + {1'b0, ay2_snd};
    assign sound_out = mix[10:1];   // /2 to keep 10-bit range (legacy)
    assign sound_sum = mix;         // 11-bit, no premature /2 -> mirax_audio_out

    // -------------------- interrupts ----------------------------------------
    always @(posedge clk) begin
        if (rst) nmi_n <= 1'b1;
        else if (sound_cmd_wr) nmi_n <= 1'b0;      // pulse asserted
        else if (cen) nmi_n <= 1'b1;               // released next cycle (edge NMI)
    end

    always @(posedge clk) begin
        if (rst) irq_n <= 1'b1;
        else if (irq_tick) irq_n <= 1'b0;
        else if (cen & ~iorq_n & ~m1_n) irq_n <= 1'b1; // acked on interrupt ack
    end

endmodule


// ----------------------------------------------------------------------------
//  ay_writeport : wraps jt49 with the two-phase (addr latch already captured)
//  write interface Mirax uses. Instantiate your verified jt49 core here.
// ----------------------------------------------------------------------------
module ay_writeport
(
    input  wire       clk,
    input  wire       cen,
    input  wire       rst,
    input  wire [7:0] reg_num,
    input  wire [7:0] data,
    input  wire       wr,         // data-write strobe
    output wire [9:0] sound
);
    // Two-phase sequencer: latch address, then data, into jt49.
    reg [1:0] ph;
    reg       jt_addr, jt_wr;
    always @(posedge clk) begin
        if (rst) begin ph<=0; jt_addr<=0; jt_wr<=0; end
        else begin
            jt_wr <= 1'b0; jt_addr <= 1'b0;
            case (ph)
                2'd0: if (wr) begin jt_addr<=1'b1; ph<=2'd1; end // present register#
                2'd1: begin jt_wr<=1'b1; ph<=2'd0; end           // present data
                default: ph<=2'd0;
            endcase
        end
    end

    wire [7:0] bus = jt_addr ? reg_num : data;

    jt49_bus u_jt49 (
        .rst_n  (~rst),
        .clk    (clk),
        .clk_en (cen),
        .bdir   (jt_addr | jt_wr),
        .bc1    (jt_addr),
        .din    (bus),
        .sel    (1'b1),           // /2 clock select per jt49 convention
        .dout   (),
        .sound  (sound),
        .A(), .B(), .C(),
        .IOA_in(8'h0), .IOA_out(),
        .IOB_in(8'h0), .IOB_out()
    );
endmodule

`default_nettype wire