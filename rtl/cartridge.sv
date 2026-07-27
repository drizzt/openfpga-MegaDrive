//============================================================================
//  Megadrive/Master Cartridge implementation
//  Copyright (c) 2023 Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

// Pocket port of the above: linear ROM only, no mappers, save SRAM, SVP or EEPROMs

module cartridge (
    input wire clk,
    input wire clk_ram,
    input wire reset,
    input wire reset_sdram,

    output wire        SDRAM_CLK,
    output wire        SDRAM_CKE,
    output wire [12:0] SDRAM_A,
    output wire [ 1:0] SDRAM_BA,
    inout  wire [15:0] SDRAM_DQ,
    output wire        SDRAM_DQML,
    output wire        SDRAM_DQMH,
    output wire        SDRAM_nCS,
    output wire        SDRAM_nCAS,
    output wire        SDRAM_nRAS,
    output wire        SDRAM_nWE,

    input  wire        cart_dl,
    input  wire [15:0] cart_dl_data,
    input  wire        cart_dl_wr,
    output reg         cart_dl_wait = 0,

    input  wire [23:1] cart_addr,
    output reg  [15:0] cart_data = 0,
    input  wire        cart_cs,
    input  wire        cart_oe,
    output wire        cart_data_en,
    output wire        cart_dtack
);

  reg         rom_wr = 0;
  wire        rom_wrack;
  reg  [24:1] rom_mask = 0;
  reg  [25:1] rom_size = 0;
  reg  [24:1] cart_wr_addr = 0;

  reg  [24:1] rom_addr = 0;
  reg         rom_req = 0;
  wire        rom_ack;
  wire [15:0] rom_data;
  reg         rom_rd = 0;

  sdram sdram (
      .init(reset_sdram),
      .clk (clk_ram),

      .SDRAM_CLK (SDRAM_CLK),
      .SDRAM_CKE (SDRAM_CKE),
      .SDRAM_A   (SDRAM_A),
      .SDRAM_BA  (SDRAM_BA),
      .SDRAM_DQ  (SDRAM_DQ),
      .SDRAM_DQML(SDRAM_DQML),
      .SDRAM_DQMH(SDRAM_DQMH),
      .SDRAM_nCS (SDRAM_nCS),
      .SDRAM_nCAS(SDRAM_nCAS),
      .SDRAM_nRAS(SDRAM_nRAS),
      .SDRAM_nWE (SDRAM_nWE),

      // MD ROMs arrive little-endian from the loader, so swap to big-endian here
      .addr0(cart_wr_addr),
      .din0 ({cart_dl_data[7:0], cart_dl_data[15:8]}),
      .dout0(),
      .wrl0 (1'b1),
      .wrh0 (1'b1),
      .req0 (rom_wr),
      .ack0 (rom_wrack),

      .addr1(rom_addr),
      .din1 (16'd0),
      .dout1(rom_data),
      .wrl1 (1'b0),
      .wrh1 (1'b0),
      .req1 (rom_req),
      .ack1 (rom_ack),

      // Port 2 was the SVP's, tie it off so it never arbitrates
      .addr2(24'd0),
      .din2 (16'd0),
      .dout2(),
      .wrl2 (1'b0),
      .wrh2 (1'b0),
      .req2 (1'b0),
      .ack2 ()
  );

  // ROM download

  reg prev_dl = 0;
  reg prev_reset = 0;

  always @(posedge clk) begin
    prev_reset <= reset;
    if (~prev_reset && reset) begin
      cart_dl_wait <= 0;
    end

    prev_dl <= cart_dl;
    if (~prev_dl & cart_dl) begin
      rom_mask <= 0;
      cart_wr_addr <= 0;
      rom_size <= 0;
    end

    if (cart_dl & cart_dl_wr) begin
      cart_dl_wait <= 1;
      rom_wr <= ~rom_wr;
      cart_wr_addr <= rom_size;
      rom_mask <= rom_mask | rom_size[24:1];
      rom_size <= rom_size + 1'd1;
    end else if (rom_wr == rom_wrack) begin
      cart_dl_wait <= 0;
    end
  end

  // ROM read

  assign cart_dtack   = 1'b0;
  assign cart_data_en = cart_oe & cart_cs;

  reg prev_rd = 0;

  always @(posedge clk_ram) begin
    if (rom_req == rom_ack) begin
      if (rom_rd) begin
        cart_data <= rom_data;
      end
      rom_rd <= 0;
    end

    prev_rd <= cart_oe & cart_cs;
    if (~prev_rd & cart_oe & cart_cs) begin
      rom_addr <= cart_addr & rom_mask[24:1];
      rom_req  <= ~rom_req;
      rom_rd   <= 1;
    end
  end

endmodule
