// ============================================================================
//  tv80_adapter.sv  -  provides module `T80pa` on top of the Verilog tv80 core
// ----------------------------------------------------------------------------
//  The Mirax core instantiates `T80pa` (the MiSTer VHDL Z80) with a clock-enable
//  interface. iverilog is Verilog-only, so this adapter presents the SAME port
//  list backed by `tv80_core` (hutch31/tv80), which has a real `cen` input.
//
//  The bus-control decode (mreq_n/rd_n/wr_n/iorq_n + di latch) is the tv80s
//  logic, but here every control register is gated by `cen` so exactly one Z80
//  clock advances per enable tick - matching how the core clocks its RAMs.
//
//  Simplifications vs the VHDL T80pa (fine for functional bring-up; revisit
//  T-state-exact timing on hardware):
//    * single-phase enable: CEN_p used, CEN_n ignored
//    * no DRAM refresh strobe (TV80_REFRESH undefined) - Mirax doesn't need it
//
//  Compile with: extern/tv80/rtl/core/{tv80_core,tv80_alu,tv80_mcode,tv80_reg}.v
// ============================================================================
`default_nettype none
`ifndef TV80DELAY
 `define TV80DELAY
`endif

module T80pa
(
    input  wire        RESET_n,
    input  wire        CLK,
    input  wire        CEN_p,
    input  wire        CEN_n,   // ignored (single-phase enable model)
    input  wire        WAIT_n,
    input  wire        INT_n,
    input  wire        NMI_n,
    input  wire        BUSRQ_n,
    output wire        M1_n,
    output reg         MREQ_n,
    output reg         IORQ_n,
    output reg         RD_n,
    output reg         WR_n,
    output wire [15:0] A,
    input  wire [ 7:0] DI,
    output wire [ 7:0] DO
);
    localparam Mode = 0;   // full Z80
    localparam IOWait = 1; // standard I/O cycle
    localparam T2Write = 1;

    wire        cen = CEN_p;
    wire        intcycle_n, no_read, write, iorq;
    wire [6:0]  mcycle, tstate;
    reg  [7:0]  di_reg;

    tv80_core #(.Mode(Mode), .IOWait(IOWait)) i_core (
        .cen        (cen),
        .m1_n       (M1_n),
        .iorq       (iorq),
        .no_read    (no_read),
        .write      (write),
        .rfsh_n     (),
        .halt_n     (),
        .wait_n     (WAIT_n),
        .int_n      (INT_n),
        .nmi_n      (NMI_n),
        .reset_n    (RESET_n),
        .busrq_n    (BUSRQ_n),
        .busak_n    (),
        .clk        (CLK),
        .IntE       (),
        .stop       (),
        .A          (A),
        .dinst      (DI),
        .di         (di_reg),
        .dout       (DO),
        .mc         (mcycle),
        .ts         (tstate),
        .intcycle_n (intcycle_n)
    );

    // bus-control decode (tv80s logic, cen-gated)
    always @(posedge CLK or negedge RESET_n) begin
        if (!RESET_n) begin
            RD_n<=1'b1; WR_n<=1'b1; IORQ_n<=1'b1; MREQ_n<=1'b1; di_reg<=8'h0;
        end else if (cen) begin
            RD_n<=1'b1; WR_n<=1'b1; IORQ_n<=1'b1; MREQ_n<=1'b1;
            if (mcycle[0]) begin
                if (tstate[1] || (tstate[2] && WAIT_n==1'b0)) begin
                    RD_n   <= ~intcycle_n;
                    MREQ_n <= ~intcycle_n;
                    IORQ_n <=  intcycle_n;
                end
            end else begin
                if ((tstate[1] || (tstate[2] && WAIT_n==1'b0)) && !no_read && !write) begin
                    RD_n   <= 1'b0;
                    IORQ_n <= ~iorq;
                    MREQ_n <=  iorq;
                end
                if ((tstate[1] || (tstate[2] && WAIT_n==1'b0)) && write) begin
                    WR_n   <= 1'b0;
                    IORQ_n <= ~iorq;
                    MREQ_n <=  iorq;
                end
            end
            if (tstate[2] && WAIT_n==1'b1 && !write && !no_read)
                di_reg <= DI;
        end
    end
endmodule

`default_nettype wire
