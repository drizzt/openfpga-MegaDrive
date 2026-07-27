// Pocket integration shell around md_board.v: PLL, reset, ROM download, pads, video, audio

`default_nettype none

module core_top (

    //
    // physical connections
    //

    ///////////////////////////////////////////////////
    // clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

    input wire clk_74a,  // mainclk1
    input wire clk_74b,  // mainclk1

    ///////////////////////////////////////////////////
    // cartridge interface
    // switches between 3.3v and 5v mechanically
    // output enable for multibit translators controlled by pic32

    // GBA AD[15:8]
    inout  wire [7:0] cart_tran_bank2,
    output wire       cart_tran_bank2_dir,

    // GBA AD[7:0]
    inout  wire [7:0] cart_tran_bank3,
    output wire       cart_tran_bank3_dir,

    // GBA A[23:16]
    inout  wire [7:0] cart_tran_bank1,
    output wire       cart_tran_bank1_dir,

    // GBA [7] PHI#
    // GBA [6] WR#
    // GBA [5] RD#
    // GBA [4] CS1#/CS#
    //     [3:0] unwired
    inout  wire [7:4] cart_tran_bank0,
    output wire       cart_tran_bank0_dir,

    // GBA CS2#/RES#
    inout  wire cart_tran_pin30,
    output wire cart_tran_pin30_dir,
    output wire cart_pin30_pwroff_reset,

    // GBA IRQ/DRQ
    inout  wire cart_tran_pin31,
    output wire cart_tran_pin31_dir,

    // infrared
    input  wire port_ir_rx,
    output wire port_ir_tx,
    output wire port_ir_rx_disable,

    // GBA link port
    inout  wire port_tran_si,
    output wire port_tran_si_dir,
    inout  wire port_tran_so,
    output wire port_tran_so_dir,
    inout  wire port_tran_sck,
    output wire port_tran_sck_dir,
    inout  wire port_tran_sd,
    output wire port_tran_sd_dir,

    ///////////////////////////////////////////////////
    // cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

    output wire [21:16] cram0_a,
    inout  wire [ 15:0] cram0_dq,
    input  wire         cram0_wait,
    output wire         cram0_clk,
    output wire         cram0_adv_n,
    output wire         cram0_cre,
    output wire         cram0_ce0_n,
    output wire         cram0_ce1_n,
    output wire         cram0_oe_n,
    output wire         cram0_we_n,
    output wire         cram0_ub_n,
    output wire         cram0_lb_n,

    output wire [21:16] cram1_a,
    inout  wire [ 15:0] cram1_dq,
    input  wire         cram1_wait,
    output wire         cram1_clk,
    output wire         cram1_adv_n,
    output wire         cram1_cre,
    output wire         cram1_ce0_n,
    output wire         cram1_ce1_n,
    output wire         cram1_oe_n,
    output wire         cram1_we_n,
    output wire         cram1_ub_n,
    output wire         cram1_lb_n,

    ///////////////////////////////////////////////////
    // sdram, 512mbit 16bit

    output wire [12:0] dram_a,
    output wire [ 1:0] dram_ba,
    inout  wire [15:0] dram_dq,
    output wire [ 1:0] dram_dqm,
    output wire        dram_clk,
    output wire        dram_cke,
    output wire        dram_ras_n,
    output wire        dram_cas_n,
    output wire        dram_we_n,

    ///////////////////////////////////////////////////
    // sram, 1mbit 16bit

    output wire [16:0] sram_a,
    inout  wire [15:0] sram_dq,
    output wire        sram_oe_n,
    output wire        sram_we_n,
    output wire        sram_ub_n,
    output wire        sram_lb_n,

    ///////////////////////////////////////////////////
    // vblank driven by dock for sync in a certain mode

    input wire vblank,

    ///////////////////////////////////////////////////
    // i/o to 6515D breakout usb uart

    output wire dbg_tx,
    input  wire dbg_rx,

    ///////////////////////////////////////////////////
    // i/o pads near jtag connector user can solder to

    output wire user1,
    input  wire user2,

    ///////////////////////////////////////////////////
    // RFU internal i2c bus

    inout  wire aux_sda,
    output wire aux_scl,

    ///////////////////////////////////////////////////
    // RFU, do not use
    output wire vpll_feed,


    //
    // logical connections
    //

    ///////////////////////////////////////////////////
    // video, audio output to scaler
    output wire [23:0] video_rgb,
    output wire        video_rgb_clock,
    output wire        video_rgb_clock_90,
    output wire        video_de,
    output wire        video_skip,
    output wire        video_vs,
    output wire        video_hs,

    output wire audio_mclk,
    input  wire audio_adc,
    output wire audio_dac,
    output wire audio_lrck,

    ///////////////////////////////////////////////////
    // bridge bus connection
    // synchronous to clk_74a
    output wire        bridge_endian_little,
    input  wire [31:0] bridge_addr,
    input  wire        bridge_rd,
    output reg  [31:0] bridge_rd_data,
    input  wire        bridge_wr,
    input  wire [31:0] bridge_wr_data,

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
    input wire [31:0] cont1_key,
    input wire [31:0] cont2_key,
    input wire [31:0] cont3_key,
    input wire [31:0] cont4_key,
    input wire [31:0] cont1_joy,
    input wire [31:0] cont2_joy,
    input wire [31:0] cont3_joy,
    input wire [31:0] cont4_joy,
    input wire [15:0] cont1_trig,
    input wire [15:0] cont2_trig,
    input wire [15:0] cont3_trig,
    input wire [15:0] cont4_trig

);

  // not using the IR port, so turn off both the LED, and
  // disable the receive circuit to save power
  assign port_ir_tx              = 0;
  assign port_ir_rx_disable      = 1;

  assign bridge_endian_little    = 0;

  // cart is unused, so set all level translators accordingly
  // directions are 0:IN, 1:OUT
  assign cart_tran_bank3         = 8'hzz;
  assign cart_tran_bank3_dir     = 1'b0;
  assign cart_tran_bank2         = 8'hzz;
  assign cart_tran_bank2_dir     = 1'b0;
  assign cart_tran_bank1         = 8'hzz;
  assign cart_tran_bank1_dir     = 1'b0;
  assign cart_tran_bank0         = 4'hf;
  assign cart_tran_bank0_dir     = 1'b1;
  assign cart_tran_pin30         = 1'b0;
  assign cart_tran_pin30_dir     = 1'bz;
  assign cart_pin30_pwroff_reset = 1'b0;
  assign cart_tran_pin31         = 1'bz;
  assign cart_tran_pin31_dir     = 1'b0;

  // link port unused, tristate everything
  assign port_tran_so            = 1'bz;
  assign port_tran_so_dir        = 1'b0;
  assign port_tran_si            = 1'bz;
  assign port_tran_si_dir        = 1'b0;
  assign port_tran_sck           = 1'bz;
  assign port_tran_sck_dir       = 1'b0;
  assign port_tran_sd            = 1'bz;
  assign port_tran_sd_dir        = 1'b0;

  // tie off PSRAM, unused (ROM lives in SDRAM)
  assign cram0_a                 = 'h0;
  assign cram0_dq                = {16{1'bZ}};
  assign cram0_clk               = 0;
  assign cram0_adv_n             = 1;
  assign cram0_cre               = 0;
  assign cram0_ce0_n             = 1;
  assign cram0_ce1_n             = 1;
  assign cram0_oe_n              = 1;
  assign cram0_we_n              = 1;
  assign cram0_ub_n              = 1;
  assign cram0_lb_n              = 1;

  assign cram1_a                 = 'h0;
  assign cram1_dq                = {16{1'bZ}};
  assign cram1_clk               = 0;
  assign cram1_adv_n             = 1;
  assign cram1_cre               = 0;
  assign cram1_ce0_n             = 1;
  assign cram1_ce1_n             = 1;
  assign cram1_oe_n              = 1;
  assign cram1_we_n              = 1;
  assign cram1_ub_n              = 1;
  assign cram1_lb_n              = 1;

  // tie off SRAM, unused
  assign sram_a                  = 'h0;
  assign sram_dq                 = {16{1'bZ}};
  assign sram_oe_n               = 1;
  assign sram_we_n               = 1;
  assign sram_ub_n               = 1;
  assign sram_lb_n               = 1;

  assign dbg_tx                  = 1'bZ;
  assign user1                   = 1'bZ;
  assign aux_scl                 = 1'bZ;
  assign vpll_feed               = 1'bZ;


  //
  // clocks
  //

  // VCO = 644.3181 MHz, every MD clock is an integer divide of it. The dot clock is
  // fixed at H40: H32 needs the dual-clock plus dcfifo scheme from openfpga-Genesis
  wire clk_sys_53_69;
  wire clk_md_107_39;
  wire clk_vid_6_71;
  wire clk_vid_6_71_90deg;
  wire pll_core_locked;
  wire pll_core_locked_s;

  synch_3 pll_lock_sync (
      .i  (pll_core_locked),
      .o  (pll_core_locked_s),
      .clk(clk_74a)
  );

  // Latched, so a later lock dip does not re-reset the core
  reg pll_ever_locked = 0;
  always @(posedge clk_74a) begin
    if (pll_core_locked_s) begin
      pll_ever_locked <= 1;
    end
  end

  mf_pllbase mp1 (
      .refclk(clk_74a),
      .rst   (0),

      .outclk_0(clk_sys_53_69),      // VCO/12, MD master clock
      .outclk_1(clk_md_107_39),      // VCO/6, md_board MCLK2 and SDRAM
      .outclk_2(clk_vid_6_71),       // VCO/96, H40 dot clock
      .outclk_3(clk_vid_6_71_90deg), // video DDR

      .locked(pll_core_locked),

      .reconfig_to_pll  (64'd0),
      .reconfig_from_pll()
  );

  // dram_clk is driven inside rtl/upstream/sdram.sv, by its own altddio_out on
  // clk_md_107_39 (datain_h=0/datain_l=1, so inverted)


  //
  // host/target command handler
  //

  wire        reset_n;
  wire [31:0] cmd_bridge_rd_data;

  wire        status_boot_done = pll_core_locked_s;
  wire        status_setup_done = pll_core_locked_s;
  wire        status_running = reset_n;

  wire        dataslot_requestread;
  wire [15:0] dataslot_requestread_id;
  wire        dataslot_requestread_ack = 1;
  wire        dataslot_requestread_ok = 1;

  wire        dataslot_requestwrite;
  wire [15:0] dataslot_requestwrite_id;
  wire [31:0] dataslot_requestwrite_size;
  wire        dataslot_requestwrite_ack = 1;
  wire        dataslot_requestwrite_ok = 1;

  wire        dataslot_update;
  wire [15:0] dataslot_update_id;
  wire [31:0] dataslot_update_size;

  wire        dataslot_allcomplete;

  wire [31:0] rtc_epoch_seconds;
  wire [31:0] rtc_date_bcd;
  wire [31:0] rtc_time_bcd;
  wire        rtc_valid;

  // No savestates, so tie the handshake off and keep framework.sleep_supported
  // false in core.json, or the OS will try to sleep this core
  wire        savestate_supported = 0;
  wire [31:0] savestate_addr = 0;
  wire [31:0] savestate_size = 0;
  wire [31:0] savestate_maxloadsize = 0;

  wire        savestate_start;
  wire        savestate_start_ack = 0;
  wire        savestate_start_busy = 0;
  wire        savestate_start_ok = 0;
  wire        savestate_start_err = 0;

  wire        savestate_load;
  wire        savestate_load_ack = 0;
  wire        savestate_load_busy = 0;
  wire        savestate_load_ok = 0;
  wire        savestate_load_err = 0;

  wire        osnotify_inmenu;

  // target dataslot commands unused (saves go through data_loader/unloader)
  wire        target_dataslot_read = 0;
  wire        target_dataslot_write = 0;
  wire        target_dataslot_getfile = 0;
  wire        target_dataslot_openfile = 0;

  wire        target_dataslot_ack;
  wire        target_dataslot_done;
  wire [ 2:0] target_dataslot_err;

  wire [15:0] target_dataslot_id = 0;
  wire [31:0] target_dataslot_slotoffset = 0;
  wire [31:0] target_dataslot_bridgeaddr = 0;
  wire [31:0] target_dataslot_length = 0;

  wire [31:0] target_buffer_param_struct = 0;
  wire [31:0] target_buffer_resp_struct = 0;

  // No battery saves, so the save datatable entry stays zero
  localparam [31:0] SAVE_SIZE = 32'd0;
  wire [ 9:0] datatable_addr = 10'd3;
  wire        datatable_wren = pll_core_locked_s;
  wire [31:0] datatable_data = SAVE_SIZE;
  wire [31:0] datatable_q;

  core_bridge_cmd icb (

      .clk    (clk_74a),
      .reset_n(reset_n),

      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_rd           (bridge_rd),
      .bridge_rd_data      (cmd_bridge_rd_data),
      .bridge_wr           (bridge_wr),
      .bridge_wr_data      (bridge_wr_data),

      .status_boot_done (status_boot_done),
      .status_setup_done(status_setup_done),
      .status_running   (status_running),

      .dataslot_requestread    (dataslot_requestread),
      .dataslot_requestread_id (dataslot_requestread_id),
      .dataslot_requestread_ack(dataslot_requestread_ack),
      .dataslot_requestread_ok (dataslot_requestread_ok),

      .dataslot_requestwrite     (dataslot_requestwrite),
      .dataslot_requestwrite_id  (dataslot_requestwrite_id),
      .dataslot_requestwrite_size(dataslot_requestwrite_size),
      .dataslot_requestwrite_ack (dataslot_requestwrite_ack),
      .dataslot_requestwrite_ok  (dataslot_requestwrite_ok),

      .dataslot_update     (dataslot_update),
      .dataslot_update_id  (dataslot_update_id),
      .dataslot_update_size(dataslot_update_size),

      .dataslot_allcomplete(dataslot_allcomplete),

      .rtc_epoch_seconds(rtc_epoch_seconds),
      .rtc_date_bcd     (rtc_date_bcd),
      .rtc_time_bcd     (rtc_time_bcd),
      .rtc_valid        (rtc_valid),

      .savestate_supported  (savestate_supported),
      .savestate_addr       (savestate_addr),
      .savestate_size       (savestate_size),
      .savestate_maxloadsize(savestate_maxloadsize),

      .savestate_start     (savestate_start),
      .savestate_start_ack (savestate_start_ack),
      .savestate_start_busy(savestate_start_busy),
      .savestate_start_ok  (savestate_start_ok),
      .savestate_start_err (savestate_start_err),

      .savestate_load     (savestate_load),
      .savestate_load_ack (savestate_load_ack),
      .savestate_load_busy(savestate_load_busy),
      .savestate_load_ok  (savestate_load_ok),
      .savestate_load_err (savestate_load_err),

      .osnotify_inmenu(osnotify_inmenu),

      .target_dataslot_read    (target_dataslot_read),
      .target_dataslot_write   (target_dataslot_write),
      .target_dataslot_getfile (target_dataslot_getfile),
      .target_dataslot_openfile(target_dataslot_openfile),

      .target_dataslot_ack (target_dataslot_ack),
      .target_dataslot_done(target_dataslot_done),
      .target_dataslot_err (target_dataslot_err),

      .target_dataslot_id        (target_dataslot_id),
      .target_dataslot_slotoffset(target_dataslot_slotoffset),
      .target_dataslot_bridgeaddr(target_dataslot_bridgeaddr),
      .target_dataslot_length    (target_dataslot_length),

      .target_buffer_param_struct(target_buffer_param_struct),
      .target_buffer_resp_struct (target_buffer_resp_struct),

      .datatable_addr(datatable_addr),
      .datatable_wren(datatable_wren),
      .datatable_data(datatable_data),
      .datatable_q   (datatable_q)

  );


  //
  // settings
  //

  always @(*) begin
    casex (bridge_addr)
      32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
      end
      default: begin
        bridge_rd_data <= 0;
      end
    endcase
  end

  // cfg_pal only changes the VDP's line and field counts. The PLL is fixed at the
  // NTSC master clock, so PAL runs at the wrong rate, but md_board wants the pin
  reg cfg_pal = 0;
  reg cfg_jap = 0;

  localparam [13:0] RESET_PULSE = 14'd8000;  // ~108 us at 74.25 MHz

  reg  [13:0] reset_counter = 0;
  wire        core_reset = (reset_counter != 0);

  always @(posedge clk_74a) begin
    if (reset_counter != 0) begin
      reset_counter <= reset_counter - 1;
    end

    if (bridge_wr) begin
      casex (bridge_addr)
        32'h00000008: begin
          cfg_pal <= bridge_wr_data[0];
        end
        32'h0000000C: begin
          cfg_jap <= bridge_wr_data[0];
        end
        32'hF0000000: begin
          reset_counter <= RESET_PULSE;
        end
      endcase
    end
  end

  wire reset_n_s;
  wire core_reset_s;
  wire dataslot_allcomplete_s;

  synch_3 #(
      .WIDTH(3)
  ) settings_sync (
      .i  ({reset_n, core_reset, dataslot_allcomplete}),
      .o  ({reset_n_s, core_reset_s, dataslot_allcomplete_s}),
      .clk(clk_sys_53_69)
  );


  //
  // reset
  //

  // dataslot_allcomplete is the load envelope on its own: APF clears it on the data
  // slot request write command, sets it on all complete, and reads 0 out of reset,
  // so the console stays down until the first cartridge has landed in SDRAM
  wire loading_74a = ~dataslot_allcomplete;
  wire reset_req_74a = ~reset_n | core_reset | ~pll_ever_locked;

  wire loading_s;
  wire md_reset_req_s;
  wire cfg_pal_s;
  wire cfg_jap_s;

  synch_3 #(
      .WIDTH(4)
  ) md_settings_sync (
      .i  ({loading_74a, reset_req_74a, cfg_pal, cfg_jap}),
      .o  ({loading_s, md_reset_req_s, cfg_pal_s, cfg_jap_s}),
      .clk(clk_md_107_39)
  );

  // md_board wants md_reset (ext_reset) held for the whole load and released 3 steps
  // after the last event, and btn_reset (reset_button) held long enough for the
  // console's own reset detector to see it
  reg        btn_reset = 0;
  reg        md_reset = 0;
  reg        shell_reset = 0;
  reg [15:1] ram_clear_addr = 0;
  reg [ 4:0] reset_delay_count = 0;
  reg        prev_md_reset_req = 0;

  always @(posedge clk_md_107_39) begin
    ram_clear_addr <= ram_clear_addr + 1'd1;
    if (&ram_clear_addr & ~&reset_delay_count) begin
      reset_delay_count <= reset_delay_count + 1'd1;
    end

    prev_md_reset_req <= md_reset_req_s;
    if (loading_s | (~prev_md_reset_req & md_reset_req_s)) begin
      reset_delay_count <= 0;
    end

    shell_reset <= (reset_delay_count < 3);

    if (loading_s) begin
      md_reset <= 1;
    end else if (reset_delay_count == 3) begin
      md_reset <= 0;
    end

    if (~prev_md_reset_req & md_reset_req_s) begin
      btn_reset <= 1;
    end else if (&reset_delay_count) begin
      btn_reset <= 0;
    end
  end

  reg       sys_reset = 0;
  reg [1:0] shell_reset_sync = 0;

  always @(posedge clk_sys_53_69) begin
    shell_reset_sync <= {shell_reset_sync[0], shell_reset};
    if (!shell_reset_sync) begin
      sys_reset <= 0;
    end
    if (&shell_reset_sync) begin
      sys_reset <= 1;
    end
  end


  //
  // ROM download
  //

  wire        ioctl_wr;
  wire [24:0] ioctl_addr;
  wire [15:0] ioctl_data;

  data_loader #(
      .ADDRESS_MASK_UPPER_4 (4'h1),
      .ADDRESS_SIZE         (25),
      .OUTPUT_WORD_SIZE     (2),
      .WRITE_MEM_CLOCK_DELAY(24)
  ) rom_data_loader (
      .clk_74a   (clk_74a),
      .clk_memory(clk_sys_53_69),

      .bridge_wr           (bridge_wr),
      .bridge_endian_little(bridge_endian_little),
      .bridge_addr         (bridge_addr),
      .bridge_wr_data      (bridge_wr_data),

      .write_en  (ioctl_wr),
      .write_addr(ioctl_addr),
      .write_data(ioctl_data)
  );

  // No back-pressure needed, APF delivers one word per ~54 clk_sys_53_69 and a port 0
  // SDRAM write takes ~4. All complete can still land while the last words drain out
  // of the data_loader, so hold cart_dl past the final write
  reg [11:0] cart_dl_hold = 0;

  always @(posedge clk_sys_53_69) begin
    if (ioctl_wr) begin
      cart_dl_hold <= 12'hFFF;
    end else if (cart_dl_hold) begin
      cart_dl_hold <= cart_dl_hold - 1'd1;
    end
  end

  wire        cart_dl = ~dataslot_allcomplete_s | (cart_dl_hold != 0);

  //
  // cartridge
  //

  wire [23:1] cart_addr;
  wire [15:0] cart_data;
  wire        cart_cs;
  wire        cart_oe;
  wire        cart_dma;
  wire        cart_data_en;
  wire        cart_dtack;

  cartridge cartridge (
      .clk        (clk_sys_53_69),
      .clk_ram    (clk_md_107_39),
      .reset      (sys_reset),
      .reset_sdram(~pll_core_locked),

      .SDRAM_CLK (dram_clk),
      .SDRAM_CKE (dram_cke),
      .SDRAM_A   (dram_a),
      .SDRAM_BA  (dram_ba),
      .SDRAM_DQ  (dram_dq),
      .SDRAM_DQML(dram_dqm[0]),
      .SDRAM_DQMH(dram_dqm[1]),
      .SDRAM_nCS (),             // Pocket SDRAM has no CS pin (always selected)
      .SDRAM_nCAS(dram_cas_n),
      .SDRAM_nRAS(dram_ras_n),
      .SDRAM_nWE (dram_we_n),

      .cart_dl     (cart_dl),
      .cart_dl_data(ioctl_data),
      .cart_dl_wr  (ioctl_wr),
      .cart_dl_wait(),

      .cart_addr   (cart_addr),
      .cart_data   (cart_data),
      .cart_cs     (cart_cs),
      .cart_oe     (cart_oe),
      .cart_data_en(cart_data_en),
      .cart_dtack  (cart_dtack)
  );


  //
  // work RAM
  //

  // 64 KB 68000 and 8 KB Z80, both cleared through port B while md_reset is asserted
  wire [14:0] ram_68k_address;
  wire [ 1:0] ram_68k_byteena;
  wire [15:0] ram_68k_data;
  wire        ram_68k_wren;
  wire [15:0] ram_68k_o;

  wire [12:0] ram_z80_address;
  wire [ 7:0] ram_z80_data;
  wire        ram_z80_wren;
  wire [ 7:0] ram_z80_o;

  dpram #(
      .addr_width(15),
      .data_width(16)
  ) ram_68k (
      .clock(clk_md_107_39),

      .address_a(ram_68k_address),
      .data_a   (ram_68k_data),
      .wren_a   (ram_68k_wren),
      .byteena_a(ram_68k_byteena),
      .q_a      (ram_68k_o),

      .address_b(ram_clear_addr),
      .wren_b   (md_reset)
  );

  dpram #(
      .addr_width(13),
      .data_width(8)
  ) ram_z80 (
      .clock(clk_md_107_39),

      .address_a(ram_z80_address),
      .data_a   (ram_z80_data),
      .wren_a   (ram_z80_wren),
      .q_a      (ram_z80_o),

      .address_b(ram_clear_addr),
      .wren_b   (md_reset),
      .data_b   (8'hC7)            // RET, works around the Titan 2 bug
  );


  //
  // pads
  //

  // Two pads straight onto the MD controller ports, no md_io.sv (multitap, keyboard,
  // lightgun, J-Cart muxing)
  wire [31:0] cont1_key_s;
  wire [31:0] cont2_key_s;

  synch_3 #(
      .WIDTH(32)
  ) cont1_sync (
      .i  (cont1_key),
      .o  (cont1_key_s),
      .clk(clk_sys_53_69)
  );

  synch_3 #(
      .WIDTH(32)
  ) cont2_sync (
      .i  (cont2_key),
      .o  (cont2_key_s),
      .clk(clk_sys_53_69)
  );

  wire [6:0] PA_i;
  wire [6:0] PA_o;
  wire [6:0] PA_d;
  wire [6:0] PB_i;
  wire [6:0] PB_o;
  wire [6:0] PB_d;
  wire [6:0] PC_i;
  wire [6:0] PC_o;
  wire [6:0] PC_d;

  // port_out drives the console's port input, so pad to MD
  pad_io pad1 (
      .clk  (clk_sys_53_69),
      .reset(sys_reset),

      .MODE(1'b1),  // 6-button pad
      .SMS (1'b0),

      .P_UP   (cont1_key_s[0]),
      .P_DOWN (cont1_key_s[1]),
      .P_LEFT (cont1_key_s[2]),
      .P_RIGHT(cont1_key_s[3]),
      // MD A-B-C lands on Y-B-A, as on the fpgagen Genesis core
      .P_C    (cont1_key_s[4]),
      .P_B    (cont1_key_s[5]),
      .P_A    (cont1_key_s[7]),
      .P_Y    (cont1_key_s[6]),
      .P_X    (cont1_key_s[8]),
      .P_Z    (cont1_key_s[9]),
      .P_MODE (cont1_key_s[14]),
      .P_START(cont1_key_s[15]),

      .GUN_EN    (1'b0),
      .GUN_TYPE  (1'b0),
      .GUN_SENSOR(1'b0),
      .GUN_A     (1'b0),
      .GUN_B     (1'b0),
      .GUN_C     (1'b0),
      .GUN_START (1'b0),

      .MOUSE_EN   (1'b0),
      .MOUSE_FLIPY(1'b0),
      .MOUSE      (25'd0),

      .port_out(PA_i),
      .port_in (PA_o),
      .port_dir(PA_d)
  );

  pad_io pad2 (
      .clk  (clk_sys_53_69),
      .reset(sys_reset),

      .MODE(1'b1),
      .SMS (1'b0),

      .P_UP   (cont2_key_s[0]),
      .P_DOWN (cont2_key_s[1]),
      .P_LEFT (cont2_key_s[2]),
      .P_RIGHT(cont2_key_s[3]),
      .P_C    (cont2_key_s[4]),
      .P_B    (cont2_key_s[5]),
      .P_A    (cont2_key_s[7]),
      .P_Y    (cont2_key_s[6]),
      .P_X    (cont2_key_s[8]),
      .P_Z    (cont2_key_s[9]),
      .P_MODE (cont2_key_s[14]),
      .P_START(cont2_key_s[15]),

      .GUN_EN    (1'b0),
      .GUN_TYPE  (1'b0),
      .GUN_SENSOR(1'b0),
      .GUN_A     (1'b0),
      .GUN_B     (1'b0),
      .GUN_C     (1'b0),
      .GUN_START (1'b0),

      .MOUSE_EN   (1'b0),
      .MOUSE_FLIPY(1'b0),
      .MOUSE      (25'd0),

      .port_out(PB_i),
      .port_in (PB_o),
      .port_dir(PB_d)
  );

  // EXT port has nothing plugged in, so read back whatever the console drives
  assign PC_i = PC_d | PC_o;

  //
  // console
  //

  wire [23:0] core_rgb;
  wire        core_hs;
  wire        core_vs;
  wire        core_hblank;
  wire        core_vblank;
  wire [15:0] audio_l;
  wire [15:0] audio_r;

  wire [ 7:0] vdp_r;
  wire [ 7:0] vdp_g;
  wire [ 7:0] vdp_b;
  wire        vdp_hs;
  wire        vdp_vs;
  wire        vdp_hclk1;
  wire        vdp_intfield;
  wire        vdp_de_h;
  wire        vdp_de_v;
  wire        vdp_m2;
  wire        vdp_m5;
  wire        vdp_rs1;

  md_board md_board (
      .MCLK2(clk_md_107_39),

      .ext_reset   (md_reset),
      .reset_button(btn_reset),
      // md_board.v reads these, MiSTer leaves them dangling
      .ext_vres    (1'b0),
      .ext_zres    (1'b0),

      .ram_68k_address(ram_68k_address),
      .ram_68k_byteena(ram_68k_byteena),
      .ram_68k_data   (ram_68k_data),
      .ram_68k_wren   (ram_68k_wren),
      .ram_68k_o      (ram_68k_o),
      .ram_z80_address(ram_z80_address),
      .ram_z80_data   (ram_z80_data),
      .ram_z80_wren   (ram_z80_wren),
      .ram_z80_o      (ram_z80_o),

      // TMSS ROM is not loaded, so the block stays bypassed, saving 20 ALM
      .tmss_enable (1'b0),
      .tmss_data   (16'd0),
      .tmss_address(),

      // cart_oe and cart_dma come off the VDP-side early signals, so the plain
      // outputs of the same name are left dangling
      .M3              (1'b1),          // MD mode, no Master System
      .cart_address    (cart_addr),
      .cart_data       (cart_data),
      .cart_data_en    (cart_data_en),
      .cart_data_wr    (),
      .cart_cs         (cart_cs),
      .cart_oe         (),
      .vdp_dma_oe_early(cart_oe),
      .cart_lwr        (),
      .cart_uwr        (),
      .cart_time       (),
      .cart_cas2       (),
      .cart_dma        (),
      .vdp_dma         (cart_dma),
      .cart_m3_pause   (1'b0),
      .ext_dtack       (cart_dtack),
      .pal             (cfg_pal_s),
      .jap             (cfg_jap_s),

      .V_R       (vdp_r),
      .V_G       (vdp_g),
      .V_B       (vdp_b),
      .V_HS      (vdp_hs),
      .V_VS      (),
      .V_CS      (),
      .vdp_vsync2(vdp_vs),

      // md_board already emits the signed 16-bit FM plus PSG mix
      .A_L         (audio_l),
      .A_R         (audio_r),
      .A_L_2612    (),
      .A_R_2612    (),
      .MOL         (),
      .MOR         (),
      .MOL_2612    (),
      .MOR_2612    (),
      .PSG         (),
      .DAC_ch_index(),
      .fm_sel23    (),
      .fm_clk1     (),

      .PA_i(PA_i),
      .PA_o(PA_o),
      .PA_d(PA_d),  // 1 = input, 0 = output
      .PB_i(PB_i),
      .PB_o(PB_o),
      .PB_d(PB_d),
      .PC_i(PC_i),
      .PC_o(PC_o),
      .PC_d(PC_d),

      .vdp_hclk1      (vdp_hclk1),
      .vdp_intfield   (vdp_intfield),
      .vdp_de_h       (vdp_de_h),
      .vdp_de_v       (vdp_de_v),
      .vdp_m5         (vdp_m5),
      .vdp_rs1        (vdp_rs1),
      .vdp_m2         (vdp_m2),
      .vdp_lcb        (),
      .vdp_psg_clk1   (),
      .vdp_cramdot_dis(1'b1),
      .vdp_hsync2     (),

      .ym2612_status_enable(1'b0),
      .dma_68k_req         (1'b0),
      .dma_z80_req         (1'b0),
      .dma_z80_ack         (),
      .res_z80             ()
  );


  //
  // video
  //

  assign video_rgb_clock    = clk_vid_6_71;
  assign video_rgb_clock_90 = clk_vid_6_71_90deg;

  // video_cond turns the VDP's raw sync and DE strobes into blanking windows, and
  // passes color straight through
  video_cond video_cond (
      .clk(clk_md_107_39),

      .vdp_hclk1   (vdp_hclk1),
      .vdp_de_h    (vdp_de_h),
      .vdp_de_v    (vdp_de_v),
      .vdp_intfield(vdp_intfield),
      .vdp_m2      (vdp_m2),
      .vdp_m5      (vdp_m5),
      .vdp_rs1     (vdp_rs1),

      .r_in (vdp_r),
      .g_in (vdp_g),
      .b_in (vdp_b),
      .hs_in(vdp_hs),
      .vs_in(vdp_vs),

      .pal      (cfg_pal_s),
      .border_en(1'b0),
      .h40corr  (1'b0),
      .blender  (1'b0),

      .arx(),  // MiSTer aspect ratio hints, unused on Pocket
      .ary(),

      .ce_pix   (),  // one clk_vid_6_71 edge already equals one H40 dot
      .interlace(),
      .f1       (),

      .r_out  (core_rgb[23:16]),
      .g_out  (core_rgb[15:8]),
      .b_out  (core_rgb[7:0]),
      .hs_out (core_hs),
      .vs_out (core_vs),
      .hbl_out(core_hblank),
      .vbl_out(core_vblank)
  );

  // The VDP DAC is already RGB888. This runs on clk_md_107_39, video_cond's domain,
  // and clk_vid_6_71 is that same VCO over 16, so one edge samples one held pixel
  video_core video_out (
      .clk_sys(clk_md_107_39),
      .clk_vid(clk_vid_6_71),

      .rgb        (core_rgb),
      // video_cond's syncs come straight off the VDP and are active low, while
      // video_core triggers on a rising edge
      .hs         (~core_hs),
      .vs         (~core_vs),
      .hblank     (core_hblank),
      .vblank     (core_vblank),
      .scaler_slot(3'd0),

      .video_rgb (video_rgb),
      .video_de  (video_de),
      .video_hs  (video_hs),
      .video_vs  (video_vs),
      .video_skip(video_skip)
  );


  //
  // audio
  //

  audio_mixer #(
      .DW    (16),
      .STEREO(1)
  ) audio_out (
      .clk_74b   (clk_74a),
      .clk_audio (clk_sys_53_69),
      .reset     (sys_reset),
      .vol_att   (4'd0),
      .mix       (2'd0),           // 0 = none, 1 = 25%, 2 = 50% L/R crossfeed
      .is_signed (1'b1),
      .core_l    (audio_l),
      .core_r    (audio_r),
      .audio_mclk(audio_mclk),
      .audio_lrck(audio_lrck),
      .audio_dac (audio_dac)
  );

endmodule
