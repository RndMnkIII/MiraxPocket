// ============================================================================
//  ttl_ls259.sv  -  74LS259 8-bit addressable latch  (board ref R10, "mainlatch")
// ----------------------------------------------------------------------------
//  Faithful model of the addressable latch the CT805-3 uses at 0xF500-0xF507.
//  Writing to address offset A[2:0] with data bit D0 sets latch bit A to D0.
//  On the real chip /CLR is asynchronous; here we reset synchronously.
//
//  Bit map (from MAME + board R10):
//    Q0 -> coin counter 0
//    Q1 -> NMI mask (enables vblank NMI to main Z80)
//    Q2 -> coin counter 1  (only used by miraxa/miraxb)
//    Q6 -> flip screen X
//    Q7 -> flip screen Y
//    Q3..Q5 -> unused on this board
// ============================================================================
`default_nettype none

module ttl_ls259
(
    input  wire        clk,
    input  wire        rst,       // async /CLR modelled synchronous
    input  wire        g_n,       // enable (active low): assert during the write strobe
    input  wire [2:0]  a,         // address lines (= CPU A2..A0 of 0xF500 block)
    input  wire        d,         // data (= CPU D0)
    output reg  [7:0]  q
);
    always @(posedge clk) begin
        if (rst)
            q <= 8'h00;
        else if (!g_n)
            q[a] <= d;
    end
endmodule