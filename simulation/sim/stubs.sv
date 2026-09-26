// stubs.sv - minimal T80pa / jt49_bus stubs so `make elab` can check the tree
`default_nettype none
module T80pa(input RESET_n,input CLK,input CEN_p,input CEN_n,input WAIT_n,
 input INT_n,input NMI_n,input BUSRQ_n,output M1_n,output MREQ_n,output IORQ_n,
 output RD_n,output WR_n,output [15:0] A,input [7:0] DI,output [7:0] DO);
 assign M1_n=1;assign MREQ_n=1;assign IORQ_n=1;assign RD_n=1;assign WR_n=1;
 assign A=16'h0;assign DO=8'h0;
endmodule
module jt49_bus(input rst_n,input clk,input clk_en,input bdir,input bc1,
 input [7:0] din,input sel,output [7:0] dout,output [9:0] sound,
 output [7:0] A,output [7:0] B,output [7:0] C,
 input [7:0] IOA_in,output [7:0] IOA_out,input [7:0] IOB_in,output [7:0] IOB_out);
 assign dout=8'h0;assign sound=10'h0;assign A=0;assign B=0;assign C=0;
 assign IOA_out=0;assign IOB_out=0;
endmodule
`default_nettype wire
