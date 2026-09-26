// ============================================================================
//  dpram.sv  -  generic synchronous dual-port RAM (block-RAM inferred)
//  Models the many discrete SRAMs (2114/2148/58725/6116/74S201) as BRAM with
//  a CPU port and a video port. Byte-wide.
// ============================================================================
`default_nettype none

module dpram #(parameter AW=10, parameter DW=8) (
    input  wire            clk,
    // port A (CPU)
    input  wire [AW-1:0]   a_addr,
    input  wire [DW-1:0]   a_din,
    input  wire            a_we,
    output reg  [DW-1:0]   a_dout,
    // port B (video, read-mostly)
    input  wire [AW-1:0]   b_addr,
    input  wire [DW-1:0]   b_din,
    input  wire            b_we,
    output reg  [DW-1:0]   b_dout
);
    reg [DW-1:0] mem [0:(1<<AW)-1];
    always @(posedge clk) begin
        if (a_we) mem[a_addr] <= a_din;
        a_dout <= mem[a_addr];
    end
    always @(posedge clk) begin
        if (b_we) mem[b_addr] <= b_din;
        b_dout <= mem[b_addr];
    end
endmodule

`default_nettype wire
