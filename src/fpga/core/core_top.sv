//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//
`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

//Analogizer settings
localparam [7:0] ADDRESS_ANALOGIZER_CONFIG = 8'hF7;

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
// [PS2MOUSE-TEST] cart_tran_* los gobierna la instancia openFPGA_Pocket_Analogizer (mas abajo)

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign dram_a = 'h0;
assign dram_ba = 'h0;
assign dram_dq = {16{1'bZ}};
assign dram_dqm = 'h0;
assign dram_clk = 'h0;
assign dram_cke = 'h0;
assign dram_ras_n = 'h1;
assign dram_cas_n = 'h1;
assign dram_we_n = 'h1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;

logic [31:0] int_bridge_rd_data = 32'h0;

always @(*) begin
    casex(bridge_addr)
    32'hF0000000: begin
        bridge_rd_data <= int_bridge_rd_data;   // reset status readback
    end
    32'h20000000: begin
        bridge_rd_data <= int_bridge_rd_data;
    end
    32'h20000004: begin
        bridge_rd_data <= int_bridge_rd_data;
    end
    32'h20000008: begin
        bridge_rd_data <= int_bridge_rd_data;
    end
    {ADDRESS_ANALOGIZER_CONFIG,24'h0}: begin
        bridge_rd_data <= analogizer_bridge_rd_data;
    end // Analogizer
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    default: begin
        bridge_rd_data <= 0;
    end
    endcase
end

//!-------------------------------------------------------------------------
//! Reset Handler
//!-------------------------------------------------------------------------
reg [31:0] reset_counter;
reg        reset_timer;
reg        core_reset_n = 1'b1;
reg        core_reset_r = 1'b1;

always_ff @(posedge clk_74a) begin
    if(reset_timer) begin
        reset_counter <= 32'd8000;
        core_reset_n  <= 1'b0;
    end
    else begin
        if (reset_counter == 32'h0) begin
            core_reset_n <= 1'b1;
        end
        else begin
            reset_counter <= reset_counter - 32'h1;
            core_reset_n  <= 1'b0;
        end
    end
end

reg [5:0] dsw_1   = 6'h00;   // interact.json defaults (all 0x00)
reg [5:0] dsw_2   = 6'h0C;   // interact.json defaults: Demo Sounds On (0x04) + Allow Continue Yes (0x08)
reg [5:0] dsw_1_d = 6'h00;   // delayed copies, for change detection
reg [5:0] dsw_2_d = 6'h0C;
reg       turbo_r = 1'b0;    // 0x20000008 bit0: main-CPU 2x turbo (live, no reset)

    always_ff @(posedge clk_74a) begin
        // interact.json is NOT writeonly (so the Pocket can read the DIP back
        // and persist it, and restore it on boot). Consequently APF read-modify-
        // writes 0x20000000/4 EVERY frame with the same value, so we must reset
        // ONLY when a DIP value actually CHANGES -- a menu edit, or the persisted
        // values being applied just before Reset Exit on boot -- never on every
        // identical re-write (that would hold the core in a permanent reset).
        if(bridge_wr) begin
            case(bridge_addr)
                32'h20000000: dsw_1   <= bridge_wr_data[5:0];
                32'h20000004: dsw_2   <= bridge_wr_data[5:0];
                32'h20000008: turbo_r <= bridge_wr_data[0]; // turbo toggles live (no reset)
            endcase
        end

        dsw_1_d <= dsw_1;
        dsw_2_d <= dsw_2;

        // One-cycle reset pulse on a real DIP change or the explicit reset cmd.
        // A DIP change re-runs the Z80 boot code, which re-latches Cabinet/Flip
        // into the LS259 -- so flip/cocktail also take effect from persisted DIPs.
        reset_timer <= (bridge_wr && bridge_addr == 32'hF0000000)
                    || (dsw_1 != dsw_1_d) || (dsw_2 != dsw_2_d);

        if(bridge_rd) begin
            case(bridge_addr)
                32'hF0000000: begin int_bridge_rd_data <= core_reset_r;      end
                32'h20000000: begin int_bridge_rd_data <= {26'h0, dsw_1s};   end
                32'h20000004: begin int_bridge_rd_data <= {26'h0, dsw_2s};   end
                32'h20000008: begin int_bridge_rd_data <= {31'h0, turbo_r};  end
                // El Analogizer NO se rutea aqui: bridge_rd_data lo conduce el
                // bloque combinacional de arriba (evita el doble-driver 10028).
            endcase
        end
    end

wire [5:0] dsw_reg1 = dsw_1;
wire [5:0] dsw_reg2 = dsw_2;
wire [5:0] dsw_1s;
wire [5:0] dsw_2s;
wire core_reset_s;

synch_3 #(.WIDTH(6)) s_dsw1 (dsw_reg1, dsw_1s, clk_sys48);
synch_3 #(.WIDTH(6)) s_dsw2 (dsw_reg2, dsw_2s, clk_sys48);
synch_3 #(.WIDTH(1)) s_reset (core_reset_n, core_reset_s, clk_sys48);

wire turbo_s;
synch_3 #(.WIDTH(1)) s_turbo (turbo_r, turbo_s, clk_sys48);

// Pause when the Pocket OSD/menu is open (osnotify_inmenu), synchronized into
// the 48 MHz core domain. Freezes CPU + audio; video keeps scanning the frozen
// frame so the LCD stays locked.
wire pause_s;
synch_3 #(.WIDTH(1)) s_pause (osnotify_inmenu, pause_s, clk_sys48);

// Keyboard PAUSE key (kb_pause, decoded by u_kbd below, same clk_sys48 domain)
// toggles a pause latch on each press. Final pause = Pocket menu OR kbd toggle.
reg kb_pause_d   = 1'b0;
reg kb_pause_tgl = 1'b0;
always @(posedge clk_sys48) begin
    if (core_rst) begin
        kb_pause_d   <= 1'b0;
        kb_pause_tgl <= 1'b0;
    end else begin
        kb_pause_d <= kb_pause;
        if (kb_pause & ~kb_pause_d) kb_pause_tgl <= ~kb_pause_tgl; // rising edge -> toggle
    end
end
wire pause_core = pause_s | kb_pause_tgl;




//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked_s; 
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;
    
    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported;
    wire    [31:0]  savestate_addr;
    wire    [31:0]  savestate_size;
    wire    [31:0]  savestate_maxloadsize;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
    
    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    wire            target_dataslot_read    = 1'b0;
    wire            target_dataslot_write;      // [PS2MOUSE-TEST] <- dataslot_saver
    wire            target_dataslot_getfile = 1'b0;
    wire            target_dataslot_openfile;   // [PS2MOUSE-TEST] <- dataslot_saver
    
    wire            target_dataslot_ack;        
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    wire    [15:0]  target_dataslot_id;         // [PS2MOUSE-TEST] <- dataslot_saver
    wire    [31:0]  target_dataslot_slotoffset;
    wire    [31:0]  target_dataslot_bridgeaddr;
    wire    [31:0]  target_dataslot_length;
    
// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire            datatable_wren;
    wire    [31:0]  datatable_data;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),
    
    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),
    
    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),
    
    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct (),
    .target_buffer_resp_struct  (),
    
    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);



////////////////////////////////////////////////////////////////////////////////////////



// video generation
// ~12,288,000 hz pixel clock
//
// we want our video mode of 320x240 @ 60hz, this results in 204800 clocks per frame
// we need to add hblank and vblank times to this, so there will be a nondisplay area. 
// it can be thought of as a border around the visible area.
// to make numbers simple, we can have 400 total clocks per line, and 320 visible.
// dividing 204800 by 400 results in 512 total lines per frame, and 240 visible.
// this pixel clock is fairly high for the relatively low resolution, but that's fine.
// PLL output has a minimum output frequency anyway.


//============================ MIRAX VIDEO + APF ============================
// Reloj de pixel = clk_vid (PLL a 6.000 MHz), NO negociable.
// OJO: video_rgb_clock / video_rgb_clock_90 los CONDUCE el video_mixer (abajo),
// que ya les asigna clk_vid / clk_vid_90 internamente. Los antiguos 'assign'
// aqui creaban doble-driver sobre las mismas nets -> se han eliminado.

// Nets de video del core (dominio clk_sys48, avanzadas con ce_pix alineado a clk_vid)
wire [7:0] core_r, core_g, core_b;
wire       core_hsync, core_vsync, core_hsync_n, core_vsync_n, core_de, core_hb, core_vb;

// ===================== SINCRONISMO APF SINTETICO (desde blanking) ==========
//  "sync internal" = el escalador de la Pocket NO engancha: no ve un VS/HS
//  valido. El video_mixer emite HS solo en el FLANCO DE SUBIDA de core_hs y
//  ADEMAS lo SUPRIME el ciclo siguiente a la caida de DE (hs_enable_dly). Si el
//  hsync de mirax cae justo en el borde de hblank (borde de DE), el mixer mata
//  el HS en CADA linea -> nunca cuenta lineas -> sync interno.
//
//  Como hblank/vblank del core SI son correctos (el juego corre, la IRQ de
//  vblank funciona), generamos aqui HS/VS limpios y DESPLAZADOS unos ciclos
//  dentro del blanking, de modo que su flanco de subida nunca coincide con los
//  guardas DE<->HS del mixer. Dominio clk_vid (donde muestrea el mixer); hb/vb
//  ya vienen alineados a clk_vid por el ce_pix del core.
localparam [3:0] HS_OFFSET = 4'd4;   // ciclos tras iniciar hblank
localparam [3:0] VS_OFFSET = 4'd4;   // ciclos tras iniciar vblank
reg        hb_q, vb_q;
reg  [3:0] hs_cnt, vs_cnt;
reg        core_hs_apf, core_vs_apf;
always @(posedge clk_vid) begin
    if (core_rst) begin
        hb_q<=1'b0; vb_q<=1'b0; hs_cnt<=4'd0; vs_cnt<=4'd0;
        core_hs_apf<=1'b0; core_vs_apf<=1'b0;
    end else begin
        hb_q <= core_hb;
        vb_q <= core_vb;
        core_hs_apf <= 1'b0;
        core_vs_apf <= 1'b0;
        // HSYNC: cuenta HS_OFFSET ciclos tras el flanco de subida de hblank,
        // luego emite un pulso de 1 ciclo (flanco limpio lejos de la caida de DE)
        if (~hb_q & core_hb)      hs_cnt <= HS_OFFSET;      // hblank acaba de empezar
        else if (hs_cnt != 4'd0) begin
            hs_cnt <= hs_cnt - 4'd1;
            if (hs_cnt == 4'd1)   core_hs_apf <= 1'b1;
        end
        // VSYNC: idem desde el flanco de subida de vblank
        if (~vb_q & core_vb)      vs_cnt <= VS_OFFSET;
        else if (vs_cnt != 4'd0) begin
            vs_cnt <= vs_cnt - 4'd1;
            if (vs_cnt == 4'd1)   core_vs_apf <= 1'b1;
        end
    end
end
// ===================== SALIDA DE VIDEO APF (inline) =========================

pocket_video_out u_vmix (
    .clk_vid(clk_vid), .clk_vid_90deg(clk_vid_90), .reset(core_rst),
    .core_r(video_rgb_mirax[23:16]), .core_g(video_rgb_mirax[15:8]), .core_b(video_rgb_mirax[7:0]),
    .core_hs(core_hs_apf), .core_vs(core_vs_apf),   // sincronismo sintetico desde blanking
    .core_hb(core_hb),     .core_vb(core_vb),
    .video_rgb(video_rgb), .video_hs(video_hs), .video_vs(video_vs),
    .video_de(video_de), .video_skip(video_skip),
    .video_rgb_clock(video_rgb_clock), .video_rgb_clock_90(video_rgb_clock_90)
);
// ============================================================================

// Reset del core activo-alto.
//  ~reset_n      : reset del host/APF (arranque, carga)
//  ~core_reset_s : pulso de reset al cambiar un DSW o el comando reset (0xF0000000),
//                  para que el juego RE-LEA Flip Screen/Cabinet al vuelo.
wire core_rst = ~reset_n | ~core_reset_s;

wire core_ce;
wire [15:0] core_audio_l, core_audio_r;
// reg [7:0] DSW1 = 8'h00;
// reg [7:0] DSW2 = 8'h04; //Demo sounds on


// ============================ CARGA DE ROM (single-slot) ====================
//  El .mra genera UN unico .rom (0x32040 bytes) que la APF vuelca en el
//  data-slot id=1 (address 0x00000000 en data.json). data_loader_8bit captura
//  esos bytes del bridge y los entrega como stream (write_en/addr/data) ya en
//  el dominio clk_sys48, listo para el router por offsets de mirax_pocket.
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0]  ioctl_data;

data_loader #(
    .ADDRESS_MASK_UPPER_4 (4'h0),   // slot en 0x0xxxxxxx (= address de data.json)
    .ADDRESS_SIZE         (25)
) rom_loader (
    .clk_74a             (clk_74a),
    .clk_memory          (clk_sys48),
    .bridge_wr           (bridge_wr),
    .bridge_endian_little (bridge_endian_little),
    .bridge_addr         (bridge_addr),
    .bridge_wr_data      (bridge_wr_data),
    .write_en            (ioctl_wr),
    .write_addr          (ioctl_addr),
    .write_data          (ioctl_data)
);

//  "descargando" = mantener el core en reset hasta que el slot requerido este
//  cargado. dataslot_allcomplete lo da core_bridge_cmd; lo sincronizo al core.
wire dataslot_allcomplete_s;
synch_3 s_dlc (dataslot_allcomplete, dataslot_allcomplete_s, clk_sys48);
wire ioctl_download = ~dataslot_allcomplete_s;

mirax_pocket u_mirax (
    .clk_sys   (clk_sys48),        // 48 MHz from APF PLL (render + sprite FSM)
    .clk_vid   (clk_vid),          // 6 MHz from APF PLL (pixel clock / sample domain)
    .reset     (core_rst),
    .pause     (pause_core),       // Pocket menu open OR keyboard PAUSE toggle
    .turbo     (turbo_s),          // 1 = main Z80 2x (from interact 0x20000008)

    // carga externa de ROM (single-slot, offset-routed)
    .ioctl_download (ioctl_download),
    .ioctl_wr       (ioctl_wr),
    .ioctl_addr     (ioctl_addr),
    .ioctl_data     (ioctl_data),

    .cont1_key (p1_controls[15:0]),  // Analogizer/Pocket Muxed controls P1
    .cont2_key (p2_controls[15:0]),  // Analogizer/Pocket Muxed controls P2
    .dsw1      ({2'b00, dsw_1s}),             // from interact/DIP menu (see below)
    .dsw2      ({2'b00, dsw_2s}),

    .video_r   (core_r),  .video_g (core_g), .video_b (core_b),
    .video_hs  (core_hsync), .video_vs(core_vsync),
    .video_hb(core_hb), .video_vb(core_vb),
    .video_de  (core_de), .video_ce(core_ce),  // 6 MHz pixel enable

    .audio_l   (core_audio_l),     // signed 16-bit -> APF i2s serializer
    .audio_r   (core_audio_r)
);

// Analogizer settings
/*[ANALOGIZER_HOOK_BEGIN]*/
    localparam GC_PS2_NES         = 5'hC; //12 PS/2 K&M + NES 1P
    localparam GC_PS2_SNES        = 5'hD; //13 PS/2 K&M + SNES 1P
    localparam GC_PS2_DB15        = 5'hE; //14 PS/2 K&M + DB15 2P
    localparam GC_PS2_NONE        = 5'hF; //15 PS/2 K&M + sin mando SNAC
    
    //reg analogizer_ena;
    wire [3:0] analogizer_video_type;
    wire [4:0] snac_game_cont_type;
    wire [3:0] snac_cont_assignment;
    wire       pocket_blank_screen;
    wire analogizer_ena;

    //create aditional switch to blank Pocket screen.
    wire [23:0] video_rgb_mirax;
    assign video_rgb_mirax = (pocket_blank_screen && analogizer_ena) ? 24'h000000: {core_r,core_g,core_b};
    //assign video_rgb_xain = (pocket_blank_screen && analogizer_ena) ? 24'h000000: {video_r_core,video_g_core,video_b_core};

    //switch between Analogizer SNAC and Pocket Controls for P1-P4 (P3,P4 when uses PCEngine Multitap)
    wire [15:0] p1_btn, p2_btn, p3_btn, p4_btn;
    wire [31:0] p1_joy, p2_joy;
    reg [31:0] p1_joystick, p2_joystick;
    reg  [15:0] p1_controls, p2_controls;

    wire snac_is_analog = (snac_game_cont_type == 5'h12) || (snac_game_cont_type == 5'h13);


   // Are in PS/2 K&M mode?
    wire ps2_mode = analogizer_ena &&
        ((snac_game_cont_type == GC_PS2_NES)  ||
        (snac_game_cont_type == GC_PS2_SNES) ||
        (snac_game_cont_type == GC_PS2_DB15) ||
        (snac_game_cont_type == GC_PS2_NONE));

    // ---- Pad SNAC en formato Pocket (igual que en tu lógica existente) ----
    wire [15:0] snac_p1_word = {p1_btn[15:4], p1_right, p1_left, p1_down, p1_up};
    wire [15:0] snac_p2_word = {p2_btn[15:4], p2_right, p2_left, p2_down, p2_up};

    // ---- Teclado -> palabra de control en formato Pocket ----
    // AJUSTA las posiciones de bit de botones/coin/start si tu core decodifica
    // cont1_key de otra forma. Layout estándar del Pocket:
    //   [3:0]=up/down/left/right, [4]=A, [5]=B, [14]=select, [15]=start
    wire [15:0] kbd_p1_word = {
        kb_start1,        // 15  start
        kb_coin1,         // 14  select/coin  (PULSADO)
        2'b00,            // 13:12  R3/L3
        2'b00,            // 11:8   R2/L2/R1/L1, also map P2 start to L1 
		kb_pause,
		kb_coin2, 
        2'b00,            // 7:6    Y/X
        kb_p1_b2,         // 5   B -> salto
        kb_p1_b1,         // 4   A -> disparo
        kb_p1_right,      // 3
        kb_p1_left,       // 2
        kb_p1_down,       // 1
        kb_p1_up          // 0
    };
    wire [15:0] kbd_p2_word = {
        kb_start2, kb_coin2, 2'b00, 2'b00, kb_pause, 3'b000,
        kb_p2_b2, kb_p2_b1, kb_p2_right, kb_p2_left, kb_p2_down, kb_p2_up
    };

    //! Player 1 ---------------------------------------------------------------------------
    reg p1_up, p1_down, p1_left, p1_right;
    wire p1_up_analog, p1_down_analog, p1_left_analog, p1_right_analog;
    //using left analog joypad
    assign p1_up_analog    = (p1_joy[15:8] < 8'h40) ? 1'b1 : 1'b0; //analog range UP 0x00 Idle 0x7F DOWN 0xFF, DEADZONE +- 0x15
    assign p1_down_analog  = (p1_joy[15:8] > 8'hC0) ? 1'b1 : 1'b0; 
    assign p1_left_analog  = (p1_joy[7:0]  < 8'h40) ? 1'b1 : 1'b0; //analog range LEFT 0x00 Idle 0x7F RIGHT 0xFF, DEADZONE +- 0x15
    assign p1_right_analog = (p1_joy[7:0]  > 8'hC0) ? 1'b1 : 1'b0;

    always @(posedge clk_74a) begin
        p1_up    <= (snac_is_analog) ? p1_up_analog    : p1_btn[0];
        p1_down  <= (snac_is_analog) ? p1_down_analog  : p1_btn[1];
        p1_left  <= (snac_is_analog) ? p1_left_analog  : p1_btn[2];
        p1_right <= (snac_is_analog) ? p1_right_analog : p1_btn[3];
    end
    //! Player 2 ---------------------------------------------------------------------------
    reg p2_up, p2_down, p2_left, p2_right;
    wire p2_up_analog, p2_down_analog, p2_left_analog, p2_right_analog;
    //using left analog joypad
    assign p2_up_analog    = (p2_joy[15:8] < 8'h40) ? 1'b1 : 1'b0; //analog range UP 0x00 Idle 0x7F DOWN 0xFF, DEADZONE +- 0x15
    assign p2_down_analog  = (p2_joy[15:8] > 8'hC0) ? 1'b1 : 1'b0; 
    assign p2_left_analog  = (p2_joy[7:0]  < 8'h40) ? 1'b1 : 1'b0; //analog range LEFT 0x00 Idle 0x7F RIGHT 0xFF, DEADZONE +- 0x15
    assign p2_right_analog = (p2_joy[7:0]  > 8'hC0) ? 1'b1 : 1'b0;

    always @(posedge clk_74a) begin
        p2_up    <= (snac_is_analog) ? p2_up_analog    : p2_btn[0];
        p2_down  <= (snac_is_analog) ? p2_down_analog  : p2_btn[1];
        p2_left  <= (snac_is_analog) ? p2_left_analog  : p2_btn[2];
        p2_right <= (snac_is_analog) ? p2_right_analog : p2_btn[3];
    end

    always @(posedge clk_74a) begin
        reg [31:0] p1_pocket_btn, p1_pocket_joy;
        reg [31:0] p2_pocket_btn, p2_pocket_joy;

        if((snac_game_cont_type == 5'h0) || !analogizer_ena) begin //SNAC deshabilitado
            p1_controls <= cont1_key;
            p2_controls <= cont2_key;
        end
        else if(ps2_mode) begin //Modos PS/2: inyectar teclado (+ pad SNAC donde exista)
            case(snac_game_cont_type)
            GC_PS2_NONE: begin //0xF: solo teclado
                p1_controls <= kbd_p1_word;
                p2_controls <= kbd_p2_word;
                end
            GC_PS2_NES,
            GC_PS2_SNES: begin //0xC/0xD: teclado + pad 1P -> P1
                p1_controls <= kbd_p1_word | snac_p1_word;
                p2_controls <= kbd_p2_word;
                end
            GC_PS2_DB15: begin //0xE: teclado + 2 pads
                p1_controls <= kbd_p1_word | snac_p1_word;
                p2_controls <= kbd_p2_word | snac_p2_word;
                end
            default: begin
                p1_controls <= kbd_p1_word;
                p2_controls <= kbd_p2_word;
                end
            endcase
        end
        else begin //SNAC habilitado (sin PS/2): tu lógica de asignación original
        case(snac_cont_assignment[1:0])
        2'h0:    begin  //SNAC P1 -> Pocket P1
            p1_controls <= {p1_btn[15:4],p1_right,p1_left,p1_down,p1_up};
            p2_controls <= cont1_key;
            end
        2'h1: begin  //SNAC P1 -> Pocket P2
            p1_controls <= cont1_key;
            p2_controls <= p1_btn;
            end
        2'h2: begin //SNAC P1 -> Pocket P1, SNAC P2 -> Pocket P2
            p1_controls <= {p1_btn[15:4],p1_right,p1_left,p1_down,p1_up};
            p2_controls <= {p2_btn[15:4],p2_right,p2_left,p2_down,p2_up};
            end
        2'h3: begin //SNAC P1 -> Pocket P2, SNAC P2 -> Pocket P1
            p1_controls <= {p2_btn[15:4],p2_right,p2_left,p2_down,p2_up};
            p2_controls <= {p1_btn[15:4],p1_right,p1_left,p1_down,p1_up};
            end
        default: begin 
            p1_controls <= cont1_key;
            p2_controls <= cont2_key;
            end
        endcase
        end
    end

    wire [15:0] p1_btn_CK, p2_btn_CK;
    wire [31:0] p1_joy_CK, p2_joy_CK;
    synch_3 #(
    .WIDTH(16)
    ) p1b_s (
        p1_btn_CK,
        p1_btn,
        clk_74a
    );

    synch_3 #(
        .WIDTH(16)
    ) p2b_s (
        p2_btn_CK,
        p2_btn,
        clk_74a
    );

    synch_3 #(
    .WIDTH(32)
    ) p3b_s (
        p1_joy_CK,
        p1_joy,
        clk_74a
    );
        
    synch_3 #(
        .WIDTH(32)
    ) p4b_s (
        p2_joy_CK,
        p2_joy,
        clk_74a
    );

    wire [39:0] CHROMA_PHASE_INC;
    wire [26:0] COLORBURST_RANGE;
    wire PALFLAG;

    parameter NTSC_REF = 3.579545;   
    parameter PAL_REF = 4.43361875;

    // Parameters to be modifed
    parameter CLK_VIDEO_NTSC = 48.0; // Must be filled E.g XX.X Hz - CLK_VIDEO
    parameter CLK_VIDEO_PAL  = 48.0; // Must be filled E.g XX.X Hz - CLK_VIDEO

    //PAL CLOCK FREQUENCY SHOULD BE 42.56274
    localparam [39:0] NTSC_PHASE_INC1 = 40'd81994819784; // ((NTSC_REF * 2^40) / CLK_VIDEO_NTSC)
    localparam [39:0] PAL_PHASE_INC1  = 40'd101558653516; // ((PAL_REF * 2^40) / CLK_VIDEO_PAL)
  
	localparam [6:0] COLORBURST_START1 = (3.7 * (CLK_VIDEO_NTSC/NTSC_REF));
	localparam [9:0] COLORBURST_NTSC_END1 = (9 * (CLK_VIDEO_NTSC/NTSC_REF)) + COLORBURST_START1;
	localparam [9:0] COLORBURST_PAL_END1 = (10 * (CLK_VIDEO_PAL/PAL_REF)) + COLORBURST_START1;

    assign PALFLAG = (analogizer_video_type == 4'h4); 
    assign CHROMA_PHASE_INC = PALFLAG ? PAL_PHASE_INC1 : NTSC_PHASE_INC1; 
    assign COLORBURST_RANGE = {COLORBURST_START1, COLORBURST_NTSC_END1, COLORBURST_PAL_END1};

    wire [31:0] analogizer_bridge_rd_data;

    openFPGA_Pocket_Analogizer #(
        .MASTER_CLK_FREQ(48_000_000), .LINE_LENGTH(384),
        .ADDRESS_ANALOGIZER_CONFIG(ADDRESS_ANALOGIZER_CONFIG)
    ) analogizer (
        .clk_74a(clk_74a),
        .i_clk(clk_sys48), .i_rst_apf(core_rst), .i_rst_core(core_rst),
        // Video in
        .video_clk(clk_sys48),
        .R(core_r), .G(core_g), .B(core_b),
        .Hblank(core_hb), .Vblank(core_vb),
        .Hsync(~core_hsync), .Vsync(~core_vsync),
        // Bridge / config
        .bridge_endian_little(bridge_endian_little),
        .bridge_addr(bridge_addr), 
        .bridge_rd(bridge_rd),
        .analogizer_bridge_rd_data(analogizer_bridge_rd_data),
        .bridge_wr(bridge_wr), 
        .bridge_wr_data(bridge_wr_data),
        // Config out (sin uso)
        .analogizer_ena_out(analogizer_ena), 
        .analogizer_video_type_out(analogizer_video_type),
        .snac_game_cont_type_out(snac_game_cont_type),
        .snac_cont_assignment_out(snac_cont_assignment),
        .SC_fx_out(), 
        .pocket_blank_screen_out(), 
        .analogizer_osd_out(),
        // Y/C encoder
        .CHROMA_PHASE_INC(CHROMA_PHASE_INC), 
        .COLORBURST_RANGE(COLORBURST_RANGE),
        .CHROMA_ADD(5'd0), 
        .CHROMA_MUL(5'd0), 
        .PALFLAG(PALFLAG),
        // Scandoubler
        .ce_pix(core_ce), 
        .scandoubler(1'b1),

        .p1_btn_state(p1_btn_CK),
        .p1_joy_state(p1_joy_CK),
        .p2_btn_state(p2_btn_CK),  
        .p2_joy_state(p2_joy_CK),
        .p3_btn_state(), 
        .p4_btn_state(),
        .i_VIB_SW1(2'b0),
        .i_VIB_DAT1(8'h0), 
        .i_VIB_SW2(2'b0), 
        .i_VIB_DAT2(8'h0),
        .busy(),
        // Cartucho Pocket
        .cart_tran_bank2(cart_tran_bank2), 
        .cart_tran_bank2_dir(cart_tran_bank2_dir),
        .cart_tran_bank3(cart_tran_bank3), 
        .cart_tran_bank3_dir(cart_tran_bank3_dir),
        .cart_tran_bank1(cart_tran_bank1), 
        .cart_tran_bank1_dir(cart_tran_bank1_dir),
        .cart_tran_bank0(cart_tran_bank0), 
        .cart_tran_bank0_dir(cart_tran_bank0_dir),
        .cart_tran_pin30(cart_tran_pin30), 
        .cart_tran_pin30_dir(cart_tran_pin30_dir),
        .cart_pin30_pwroff_reset(cart_pin30_pwroff_reset),
        .cart_tran_pin31(cart_tran_pin31), 
        .cart_tran_pin31_dir(cart_tran_pin31_dir),
        .DBG_TX(), 
        .o_stb(), 
        .o_ps2_code_new(snac_ps2_code_new),
        .o_ps2_code(snac_ps2_code),
        .o_mouse_valid(),
        .o_mouse_btn  (),
        .o_mouse_dx   (),
        .o_mouse_dy   (),
        .o_mouse_dz   (),
        .o_mouse_ready()
    );

    logic [7:0]  snac_ps2_code;
    logic        snac_ps2_code_new;

    // ---- Controles finales hacia el core ------------------------------------
    logic       kb_p1_up;
    logic       kb_p1_down;
    logic       kb_p1_left;
    logic       kb_p1_right;
    logic       kb_p1_b1;        
    logic       kb_p1_b2;        
    logic       kb_p2_up;
    logic       kb_p2_down;
    logic       kb_p2_left;
    logic       kb_p2_right;
    logic       kb_p2_b1;
    logic       kb_p2_b2;
    logic       kb_coin1;        
    logic       kb_coin2;        
    logic       kb_start1;
    logic       kb_start2;
    logic       kb_pause;

    kbd_to_controls u_kbd (
    .clk       (clk_sys48),
    .reset     (core_rst),
    .code_valid(snac_ps2_code_new),
    .scancode  (snac_ps2_code),

    .p1_up     (kb_p1_up),
    .p1_down   (kb_p1_down),
    .p1_left   (kb_p1_left),
    .p1_right  (kb_p1_right),
    .p1_b1     (kb_p1_b1),
    .p1_b2     (kb_p1_b2),

    .p2_up     (kb_p2_up),
    .p2_down   (kb_p2_down),
    .p2_left   (kb_p2_left),
    .p2_right  (kb_p2_right),
    .p2_b1     (kb_p2_b1),
    .p2_b2     (kb_p2_b2),

    .coin1     (kb_coin1), 
    .coin2     (kb_coin2),
    .start1    (kb_start1),
    .start2    (kb_start2),
    .pause     (kb_pause)
    );
    /*[ANALOGIZER_HOOK_END]*/
//======================================================================================


assign audio_mclk = audgen_mclk;
assign audio_dac  = audgen_dac;
assign audio_lrck = audgen_lrck;

// --- MCLK = 12.288 MHz (sin cambios) ---
reg  [21:0] audgen_accum;
reg         audgen_mclk;
parameter [20:0] CYCLE_48KHZ = 21'd122880 * 2;
always @(posedge clk_74a) begin
    audgen_accum <= audgen_accum + CYCLE_48KHZ;
    if (audgen_accum >= 21'd742500) begin
        audgen_mclk  <= ~audgen_mclk;
        audgen_accum <= audgen_accum - 21'd742500 + CYCLE_48KHZ;
    end
end

// --- SCLK = MCLK/4 = 3.072 MHz (sin cambios) ---
reg  [1:0] aud_mclk_divider;
wire       audgen_sclk = aud_mclk_divider[1] /* synthesis keep */;
always @(posedge audgen_mclk) aud_mclk_divider <= aud_mclk_divider + 1'b1;

// --- Muestra del core al dominio de audio (CDC de 2 FF) ---
reg [15:0] aud_sync0, aud_sync1;
always @(posedge audgen_sclk) begin
    aud_sync0 <= core_audio_l;   // mono: L == R
    aud_sync1 <= aud_sync0;
end

// --- Serializador I2S: 16 bits MSB-first + 16 de relleno por canal ---
reg [4:0]  audgen_lrck_cnt;
reg        audgen_lrck;
reg        audgen_dac;
reg [15:0] audgen_shift;
always @(negedge audgen_sclk) begin
    // saca el bit actual (MSB primero) durante los 16 bits activos, luego 0
    audgen_dac <= (audgen_lrck_cnt < 16) ? audgen_shift[15] : 1'b0;

    audgen_lrck_cnt <= audgen_lrck_cnt + 1'b1;

    if (audgen_lrck_cnt < 16)
        audgen_shift <= {audgen_shift[14:0], 1'b0};   // desplaza durante 16 ciclos

    if (audgen_lrck_cnt == 31) begin
        audgen_lrck  <= ~audgen_lrck;                 // cambia de canal cada 32
        audgen_shift <= aud_sync1;                    // recarga la muestra (mono: misma en ambos)
    end
end

///////////////////////////////////////////////

    wire    clk_sys;       // PLL outclk_2 -> 24.000 MHz
    wire    clk_vid;       // PLL outclk_0 ->  6.000 MHz 
    wire    clk_vid_90;    // PLL outclk_1 ->  6.000 MHz @90 (DDR video APF)
    wire    clk_sys48;     // PLL outclk_3 ->  48.000 MHz
	 wire    clk_sys48_90;
    wire    pll_core_locked;
    wire    pll_core_locked_s;
synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( 0 ),
    
    .outclk_0       ( clk_vid ),
    .outclk_1       ( clk_vid_90 ),
    .outclk_2       ( clk_sys ),
    .outclk_3       ( clk_sys48 ),
    .outclk_4       ( clk_sys48_90 ),
    
    .locked         ( pll_core_locked )
);
endmodule