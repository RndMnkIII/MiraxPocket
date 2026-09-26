// ============================================================================
//  mirax_clocks.sv  -  Clock-enable generation from a single 48 MHz domain
// ----------------------------------------------------------------------------
//  The board runs off a 12.000 MHz crystal (ref L2). Everything is a clean
//  divide of it, so on FPGA we run one fast clock and gate with enables:
//     main/sound Z80 : 12/4 = 3.00 MHz
//     AY-3-8912      : 12/4 = 3.00 MHz  (see open item: possibly /6 = 2 MHz)
//     pixel clock    : ~6 MHz (dot clock; tune HTOTAL to match the monitor)
//  Feed this a 48 MHz clock (12 MHz x4) for exact integer division.
// ============================================================================
`default_nettype none

module mirax_clocks
(
    input  wire clk48,
    input  wire rst,
    output reg  ce_12m,
    output reg  ce_6m,     // pixel
    output reg  ce_3m,     // cpu / ay
    output reg  ce_240hz   // sound periodic irq tick (4*60)
);
    reg [3:0] div;
    always @(posedge clk48) begin
        if (rst) begin div<=0; ce_12m<=0; ce_6m<=0; ce_3m<=0; end
        else begin
            div <= div + 4'd1;
            ce_12m <= (div[1:0]==2'b00);       // 48/4
            ce_6m  <= (div[2:0]==3'b000);      // 48/8
            ce_3m  <= (div[3:0]==4'b0000);     // 48/16
        end
    end

    // 240 Hz tick: divide 48 MHz by 200000
    reg [17:0] t;
    always @(posedge clk48) begin
        if (rst) begin t<=0; ce_240hz<=0; end
        else begin
            ce_240hz <= 1'b0;
            if (t==18'd199999) begin t<=0; ce_240hz<=1'b1; end
            else t<=t+18'd1;
        end
    end
endmodule

`default_nettype wire
