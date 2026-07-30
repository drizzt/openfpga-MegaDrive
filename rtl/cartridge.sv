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

// Adapted from rtl/upstream/cartridge.sv. A 5CEBA4 fits 18480 ALMs and 308 M10Ks
// and this design uses 99% of the first and 93% of the second, so everything that
// does not fit, or that has no consumer on the Pocket, is gone: the SVP, Pier
// Solar, the Sega Channel, the Master System cart path with its boot ROM and OPLL,
// the J-Cart and the lightgun. Every difference sits inside a marker pair below.
module cartridge
(
	input             clk,
	input             clk_ram,
	input             reset,
	input             reset_sdram,

	output            SDRAM_CLK,
	output            SDRAM_CKE,
	output     [12:0] SDRAM_A,
	output      [1:0] SDRAM_BA,
	inout      [15:0] SDRAM_DQ,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output            SDRAM_nCS,
	output            SDRAM_nCAS,
	output            SDRAM_nRAS,
	output            SDRAM_nWE,

	input             cart_dl,
	input      [24:0] cart_dl_addr,
	input      [15:0] cart_dl_data,
	input             cart_dl_wr,
	output reg        cart_dl_wait,

// pocket: APF reads the save size out of the data table before it will write a
// save file back, so the core has to say whether the cart has battery RAM at all.
// An EEPROM cart carries no battery-RAM marker in its header, hence two flags
	output reg        sram_present,
	output            eeprom_present,
// pocket-end

	input             cart_ms,
	input      [23:1] cart_addr,
	output reg [15:0] cart_data,
	input      [15:0] cart_data_wr,
	input             cart_cs,
	input             cart_oe,
	input             cart_lwr,
	input             cart_uwr,
	input             cart_time,
	output            cart_data_en,
	output            cart_dtack,
	input             cart_dma,

// pocket: the APF save slot is a byte-addressed 64 KB file served by
// data_loader/data_unloader, and a word-wide port on the save RAM costs 578 ALMs
// of read-during-write bypass. The fill window needs a flag of its own because
// cart_dl stays high until every data slot is in, the save file included, so
// filling on cart_dl would erase the file it had just loaded
	input      [15:0] save_addr,
	input       [7:0] save_di,
	output      [7:0] save_do,
	input             save_wr,
	input             save_clear,
	output            save_change,
// pocket-end

	output            ym2612_quirk,

	output     [23:0] md_addr
);

sdram sdram
(
	.*,
	.init(reset_sdram),
	.clk(clk_ram),

	.addr0(cart_wr_addr),
	.din0({cart_dl_data[7:0], cart_wr_addr0 ? cart_dl_data[7:0] : cart_dl_data[15:8]}),
	.dout0(),
	.wrl0(1),
	.wrh0(1),
	.req0(rom_wr),
	.ack0(rom_wrack),

	.addr1(rom_addr),
	.dout1(rom_data),
// pocket: port 1 never writes. Upstream drives these for the Sega Channel, whose
// rom_we is 0 here, so req1 can never fire with rom_rd low and the strobes are never
// sampled asserted. Leaving them connected measured +1.9 ns of worst slack: it is
// 16 bits of data and two strobes into the arbiter on the 107 MHz clock, and at 98%
// fill the fitter pays for that in the 68000, which is where all the slack already is
	.din1(0),
	.wrl1(0),
	.wrh1(0),
// pocket-end
	.req1(rom_req),
	.ack1(rom_ack),

// pocket: port 2 fetched the SVP's ROM. Tied off so it never wins arbitration
	.addr2(0),
	.din2(0),
	.dout2(),
	.wrl2(0),
	.wrh2(0),
	.req2(0),
	.ack2()
// pocket-end
);

reg        cart_wr_addr0;
reg        rom_wr = 0;
wire       rom_wrack;
reg [24:1] rom_mask;
reg [25:1] rom_sz;
reg [26:0] cart_wr_addr;

always @(posedge clk) begin
	reg old_dl, old_reset;

	old_reset <= reset;
	if(~old_reset && reset) cart_dl_wait <= 0;
	
	old_dl <= cart_dl;
	if(~old_dl & cart_dl) begin
		rom_mask <= 0;
		cart_wr_addr <= 0;
		rom_sz <= 0;
	end

	if (cart_dl & cart_dl_wr) begin
		cart_dl_wait <= 1;
		cart_wr_addr0 <= cart_ms;
		rom_wr <= ~rom_wr;
		cart_wr_addr <= rom_sz;
		rom_mask <= rom_mask | rom_sz[24:1];
		rom_sz <= rom_sz + 1'd1;
	end
	else if(rom_wr == rom_wrack) begin
		if(cart_wr_addr0) begin
			cart_wr_addr0 <= 0;
			rom_wr <= ~rom_wr;
			cart_wr_addr <= rom_sz;
			rom_mask <= rom_mask | rom_sz[24:1];
			rom_sz <= rom_sz + 1'd1;
		end
		else begin
			cart_dl_wait <= 0;
		end
	end
end


//--------------------- all carts --------------------------------------

assign cart_dtack   = svp_cs | dtack_ext;
assign cart_data_en = cart_oe & (cart_cs | svp_cs | data_en);

reg data_en;
always @(posedge clk_ram) data_en <= ms_rom_cs | ms_ram_cs | fm_det_cs | pier_eeprom_cs | cart_cs_ext | sf_cs | chk_cs;

wire rom_data_req = cart_cs | ms_rom_cs | cart_cs_ext;
wire sdram_rd     = cart_oe;

reg  [24:1] rom_addr;
reg         rom_req;
wire        rom_ack;
wire [15:0] rom_data;
reg         rom_rd;
reg         dtack_ext;

always @(posedge clk_ram) begin
	reg rd_old, we_old;
	
	if(~sdram_rd) dtack_ext <= 0;

	if(rom_req == rom_ack) begin
		if(rom_rd) begin
			cart_data <= rom_data;
			if(cart_cs_ext) dtack_ext <= 1;
		end
		rom_rd <= 0;
	end

	we_old <= rom_we;
	rd_old <= sdram_rd & rom_data_req;
	if((~rd_old & sdram_rd & rom_data_req) || (~we_old & rom_we)) begin
		rom_addr <= (cart_ms ? ms_cart_addr : md_cart_addr) & rom_mask[24:1];
		rom_req <= ~rom_req;
		rom_rd <= sdram_rd;
	end

// pocket: three deletions in one region. The reads whose source is gone: Master
// System boot ROM and work RAM, the FM detect register, Pier Solar's protection and
// SPI EEPROM, the J-Cart pad and the SVP. Port A is 64 KB, the size of the APF save
// slot, not upstream's 128 KB. And nothing shares the port any more, so the mux
// starts at the EEPROM branch
	if(md_sram_cs)     cart_data <= {sram_q,sram_q};
	if(md_eeprom_cs)   cart_data <= md_eeprom_data;
	if(sf_cs)          cart_data <= sf_data;
	if(chk_cs)         cart_data <= chk_data;
end

wire [15:0] sram_addr;
wire  [7:0] sram_di;
wire  [7:0] sram_q;
wire        sram_wren;

always_comb begin
	if(eeprom_quirk) begin
// pocket-end
		sram_addr = eeprom_ram_a;
		sram_di   = eeprom_ram_d;
		sram_wren = eeprom_ram_we;
	end
	else if(sf_quirk) begin
		sram_addr = cart_addr[15:1];
		sram_di   = cart_data_wr[7:0];
		sram_wren = sf_sram_wr;
	end
	else begin
		sram_addr = cart_addr[16:1];
		sram_di   = cart_data_wr[7:0];
		sram_wren = md_sram_cs & cart_lwr;
	end
end

reg [16:1] ram_rst_a;
always @(posedge clk) ram_rst_a <= ram_rst_a + 1'd1;

// pocket: byte wide, and the fill runs off save_clear rather than cart_dl. There
// is no SVP DRAM to share the port with. A word-wide port B needs 64 more M10Ks
// than this device has left, plus the bypass logic that comes with a mixed width
wire [15:0] sram2_addr;
wire  [7:0] sram2_di;
wire  [7:0] sram2_q;
wire        sram2_wren;

always_comb begin
	if(save_clear) begin
		sram2_addr = ram_rst_a;
		sram2_di   = sram00_quirk ? 8'h00 : 8'hFF;
		sram2_wren = 1;
	end
	else begin
		sram2_addr = save_addr;
		sram2_di   = save_di;
		sram2_wren = save_wr;
	end
end

dpram #(16,8) ram
(
	.clock(clk),
	.address_a(sram_addr),
	.data_a(sram_di),
	.wren_a(sram_wren),
	.q_a(sram_q),

	.address_b(sram2_addr),
	.data_b(sram2_di),
	.wren_b(sram2_wren),
	.q_b(sram2_q)
);
// pocket-end

assign save_do     = sram2_q;
assign save_change = sram_wren;

//---------------------- MD cart ---------------------------------------

assign    md_addr = {cart_addr,1'b0};

reg [5:0] md_bank[8] = '{0,1,2,3,4,5,6,7};
reg       md_bank_sram = 0;
reg       md_bank_use = 0;

always @(posedge clk) begin
	if(reset) begin
		md_bank <= '{0,1,2,3,4,5,6,7};
		md_bank_sram <= 0;
		md_bank_use <= 0;
	end
	else if (cart_lwr && cart_time) begin
		if(rom_mask[24:22]) begin
			if(cart_addr[3:1]) begin
				md_bank_use <= 1;
				if(~pier_quirk) md_bank[cart_addr[3:1]] <= cart_data_wr[5:0]; //SSF2 banks
				else if(cart_addr[3:1] == 4) {ep_cs, ep_hold , ep_sck, ep_si} <= cart_data_wr[3:0]; // Pier EEPROM
				else if(~cart_addr[3]) md_bank[{1'b1,cart_addr[2:1]}] <= cart_data_wr[3:0]; // Pier Banks
			end
			else if(~pier_quirk) md_bank_sram <= cart_data_wr[0];
		end
		else if(~schan_quirk) md_bank_sram <= cart_data_wr[0];
	end
end

wire [24:1] md_cart_addr = realtec_quirk ? realtec_addr       :
                           sf_quirk      ? sf_rom_addr        :
                           md_bank_use   ? {md_bank[cart_addr[21:19]], cart_addr[18:1]} :
                                           cart_addr - svp_dma;


// pocket: the SVP is a second DSP core and a second SDRAM port, for one game. The
// stubs keep the reads and the address arithmetic below verbatim: with svp_quirk 0
// they fold away. svp_dma was the only reader of the cart_dma input, so that port is
// dead now, kept connected so reviving any DMA-aware mapper needs no port change
wire        svp_dma = 0;
wire        svp_cs  = 0;
wire        svp_quirk = 0;
// pocket-end

// SRAM
wire md_sram_cs = ~cart_ms && (cart_addr[23:21] == 1) && (md_bank_sram || (cart_addr >= rom_sz && ~&cart_addr[20:19])) && ~noram_quirk;

// EEPROM
wire        md_eeprom_cs   = (eeprom_quirk[3:2] == 2'b01) ? (cart_addr[23:19] == 5'b00111) : (eeprom_quirk[2:0] && ((eeprom_bank & ~cart_addr[20]) || !eeprom_quirk[3]) && cart_addr[23:21] == 3'b001);
wire [15:0] md_eeprom_data;

always_comb begin
	md_eeprom_data = 0;
	casex(eeprom_quirk)
		4'b0001: md_eeprom_data[7] = eeprom_sda;
		4'b0010: md_eeprom_data[0] = eeprom_sda;
		4'b0011: md_eeprom_data[1] = eeprom_sda;
		4'b01xx: md_eeprom_data[7] = eeprom_sda;
		4'b1xxx: md_eeprom_data[0] = eeprom_sda;
		default:;
	endcase
end

reg         eeprom_sdai;
wire        eeprom_sdao;
reg         eeprom_scl;
wire [14:0] eeprom_ram_a;
wire  [7:0] eeprom_ram_d;
wire        eeprom_ram_we;
wire  [7:0] eeprom_ram_q;
reg         eeprom_bank;
always @(posedge clk) begin
	if(reset || !eeprom_quirk) begin
		eeprom_bank <= 0;
		eeprom_sdai <= 1;
		eeprom_scl  <= 1;
	end
	else if(cart_addr[23:21] == 3'b001 && cart_cs && (cart_lwr | cart_uwr)) begin
		casex (eeprom_quirk)
			4'b0001: if(cart_lwr) {eeprom_sdai,eeprom_scl} <= cart_data_wr[7:6];
			4'b0010: if(cart_lwr) {eeprom_scl,eeprom_sdai} <= cart_data_wr[1:0];
			4'b0011: if(cart_lwr) {eeprom_scl,eeprom_sdai} <= cart_data_wr[1:0];
			4'b01xx: if(cart_addr[20:19] == 2'b10) {eeprom_scl,eeprom_sdai} <= cart_data_wr[1:0];
			4'b1xxx:      if (~cart_addr[20] &  cart_lwr & ~cart_uwr) eeprom_sdai <= cart_data_wr[0];
						else if (~cart_addr[20] & ~cart_lwr &  cart_uwr) eeprom_scl  <= cart_data_wr[8];
						else if (~cart_addr[20] &  cart_lwr &  cart_uwr) eeprom_bank <= ~cart_data_wr[0];
		endcase
	end
end

wire eeprom_sda = {eeprom_sdao & eeprom_sdai};

//                                        C01     C01     C02     C16      C65       C08      C04
wire [12:0] eeprom_mask[8] = '{13'h00, 13'h7f, 13'h7f, 13'hff, 13'h7ff, 13'h1fff, 13'h3ff, 13'h1ff};

EPPROM_24CXX e24cxx
(
	.clk(clk),
	.rst(reset),
	.en(1),

	.mode((eeprom_quirk[2:0] <= 3'b010) ? 2'd0 : (eeprom_quirk[2:0] == 3'b101) ? 2'd2 : 2'd1),
	.mask(eeprom_mask[eeprom_quirk[2:0]]),

	.sda_i(eeprom_sdai),
	.sda_o(eeprom_sdao),
	.scl(eeprom_scl),

	.ram_addr(eeprom_ram_a),
	.ram_d(eeprom_ram_d),
	.ram_wr(eeprom_ram_we),
	.ram_q(sram_q)
);


// pocket: Pier Solar's SPI EEPROM and its protection reads cost ALMs this fit does
// not have. ep_si/ep_sck/ep_hold/ep_cs keep their names so the SSF2 bank block
// above needs no edit; pier_quirk is 0, so the branch that writes them is dead
reg         ep_si, ep_sck, ep_hold, ep_cs;
wire        pier_quirk = 0;
wire        pier_eeprom_cs = 0;

// The Sega Channel is 4 MB of writable ROM in SDRAM for one Japanese download
// service, and the J-Cart is a second controller port the Pocket does not have.
// rom_we staying 0 is what keeps the sdram port 1 write strobes from ever being
// sampled asserted, so do not revive it without giving them a gate of their own
wire        rom_we = 0;
wire        schan_quirk = 0;
// pocket-end

// MK3U Trilogy 10MB version (13MB isn't compatible with real HW!)
wire cart_cs_ext = ~cart_ms && (cart_addr[23:22] && cart_addr[23:20]<'hA) && (cart_addr < rom_sz);

// Realtec
reg [21:17] realtec_bank;
reg   [4:0] realtec_mask;
reg         realtec_boot;
always @(posedge clk) begin
	if (reset | ~realtec_quirk) begin
		realtec_bank <= 0;
		realtec_mask <= 0;
		realtec_boot <= 1;
	end
	else begin
		if (cart_addr[23:16] == 8'h40 && !cart_addr[11:1] && cart_uwr) begin
			case(cart_addr[15:12])
				4'h0: begin realtec_bank[21:20] <= cart_data_wr[2:1]; realtec_boot <= ~cart_data_wr[0]; end
				4'h2: begin 
					case (cart_data_wr[5:0])
						6'd0,6'd1:                                      realtec_mask <= 5'b00000;
						6'd2:                                           realtec_mask <= 5'b00001;
						6'd3,6'd4:                                      realtec_mask <= 5'b00011;
						6'd5,6'd6,6'd7,6'd8:                            realtec_mask <= 5'b00111;
						6'd9,6'd10,6'd11,6'd12,6'd13,6'd14,6'd15,6'd16: realtec_mask <= 5'b01111;
						default:                                        realtec_mask <= 5'b11111;
					endcase
				end
				4'h4: begin realtec_bank[19:17] <= cart_data_wr[2:0]; end
			endcase
		end
	end
end

wire [23:1] realtec_addr = realtec_boot ? {11'b00000111111,cart_addr[12:1]} : {2'b00,(cart_addr[21:17] & realtec_mask) + realtec_bank,cart_addr[16:1]};

//SF-001,SF-002,SF-004 mappers
wire        sf_cs     = sf_quirk && (sf_sram_en | cart_time);
wire [15:0] sf_data   = cart_time ? (sf_quirk[1:0] == 2'd3 ? sf004_do : 16'h0000) : {8'hff,sram_q};

reg   [7:0] sf001_bank_reg;
reg   [7:0] sf002_bank_reg;
reg         sf004_sram_reg;
reg   [7:0] sf004_bank_reg;
reg   [2:0] sf004_first_page;

always @(posedge clk) begin
	if(reset || !sf_quirk) begin
		sf001_bank_reg <= 8'h00;
		sf002_bank_reg <= 8'h00;
		sf004_sram_reg <= 0;
		sf004_bank_reg <= 8'h80;
		sf004_first_page <= '0;
	end
	else if(cart_lwr && !cart_addr[23:16]) begin
		
		case(sf_quirk[1:0])

			//sf-001 new rev
			1: if(sf_quirk[2] && !sf001_bank_reg[5] && cart_addr[11:8] == 4'he) sf001_bank_reg <= cart_data_wr[7:0];

			//sf-002
			2: sf002_bank_reg <= cart_data_wr[7:0];

			//sf-004
			3: if (sf004_bank_reg[7]) begin
					case (cart_addr[11:8])
						4'hd: sf004_sram_reg <= cart_data_wr[7];
						4'he: sf004_bank_reg <= cart_data_wr[7:0];
						4'hf: sf004_first_page <= cart_data_wr[6:4];
					endcase
				end
		endcase
	end
end

wire [23:1] sf001_rom_a   = (sf001_bank_reg[7] && !cart_addr[21:18]) ? {6'b001110,cart_addr[17:1]} : {2'b00,cart_addr[21:1]};
wire        sf001_sram_en = (cart_addr[23:20] == 4 && !sf_quirk[2]) || (cart_addr[23:18] == 6'b001111 && sf001_bank_reg[7]);

wire [23:1] sf002_rom_a   = {2'b00,cart_addr[21] & ~sf002_bank_reg[7],cart_addr[20:1]};
wire        sf002_sram_en = (cart_addr[23:18] == 6'b001111);
						
wire [23:1] sf004_rom_a   = (cart_addr[23:16] < 8'h14 && sf004_bank_reg[6]) ? {3'b000,sf004_first_page + cart_addr[20:18],cart_addr[17:1]} : {3'b000,sf004_first_page,cart_addr[17:1]};
wire        sf004_sram_en = (cart_addr[23:20] == 2 && sf004_sram_reg);
wire [15:0] sf004_do      = {8'hff,1'b0,sf004_first_page,4'b0000};

wire        sf_sram_en    = sf_quirk[1:0] == 1 ? sf001_sram_en :
                            sf_quirk[1:0] == 2 ? sf002_sram_en : 
                                                 sf004_sram_en;

wire [23:1] sf_rom_addr   = sf_quirk[1:0] == 1 ? sf001_rom_a : 
                            sf_quirk[1:0] == 2 ? sf002_rom_a : 
                                                 sf004_rom_a;

wire        sf_sram_wr    = sf_sram_en & cart_lwr;

//Simple check
reg         chk_cs;
reg  [15:0] chk_data;

always @(posedge clk) begin
	chk_cs <= 0;
	case(chk_quirk)
		1: if(md_addr == 'h400000) begin
				chk_data <= 'h9000;
				chk_cs <= 1;
			end
			else if(md_addr == 'h401000) begin
				chk_data <= 'hd300;
				chk_cs <= 1;
			end

		2: if(md_addr == 'hA13000) begin
				chk_data <= 'h0a;
				chk_cs <= 1;
			end

		3: if(md_addr == 'hA13000) begin
				chk_data <= 'h1c;
				chk_cs <= 1;
			end
	endcase
end

// pocket: a Master System cart needs a 16 KB boot ROM, the Z80 bus decode and four
// more mappers, and its FM needs the OPLL. The boot ROM alone is 13 of the 21 M10Ks
// left, the Pocket has its own Master System core, and cart_ms is tied low here
wire [21:0] ms_cart_addr = 0;
wire        ms_rom_cs = 0;
wire        ms_ram_cs = 0;
wire        fm_det_cs = 0;
// pocket-end

//---------------------- Cart detect ---------------------------------------

// pocket: pier_quirk, svp_quirk and schan_quirk are constants at their deletion
// sites above, so they are gone from here
reg       sram00_quirk, fmbusy_quirk, noram_quirk;
// pocket-end
reg [3:0] eeprom_quirk;
reg       realtec_quirk;
reg [2:0] sf_quirk;
reg [3:0] chk_quirk;

always @(posedge clk) begin
	reg [87:0] cart_id;
	reg [15:0] crc = 0;
	reg [15:0] crc_real = 0;
	reg [31:0] realtec_id = 0;
	reg [31:0] sp = 0;
	reg old_dl;
	old_dl <= cart_dl;

	if(~old_dl && cart_dl) begin
// pocket: the quirks whose logic is gone are constants now, there is no lightgun to
// pick a type or a sensor delay for, and the battery-RAM flag clears with the rest
		{sram00_quirk,fmbusy_quirk,noram_quirk,eeprom_quirk,realtec_quirk,sf_quirk,chk_quirk} <= '0;
		sram_present <= 0;
// pocket-end
		crc_real <= 0;
		crc <= 0;
	end

	if(cart_dl_wr & cart_dl & ~cart_ms) begin
		if(cart_dl_addr == 'h000) sp[31:16] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h002) sp[15:00] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h180) cart_id[87:72] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h182) cart_id[71:56] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h184) cart_id[55:40] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h186) cart_id[39:24] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h188) cart_id[23:08] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h18A) cart_id[07:00] <= cart_dl_data[7:0];
		if(cart_dl_addr == 'h18E) crc <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h190) begin
			     if(cart_id[63:0] == "T-50446 ") eeprom_quirk <= 4'b0001;  // X24C01 John Madden Football 93
			else if(cart_id[63:0] == "T-50516 ") eeprom_quirk <= 4'b0001;  // X24C01 John Madden Football 93 Championship Edition
			else if(cart_id[63:0] == "T-50396 ") eeprom_quirk <= 4'b0001;  // X24C01 NHLPA Hockey 93
			else if(cart_id[63:0] == "T-50176 ") eeprom_quirk <= 4'b0001;  // X24C01 Rings of Power
			else if(cart_id[63:0] == "T-50606 ") eeprom_quirk <= 4'b0001;  // X24C01 Bill Walsh College Football
			else if(cart_id[63:0] == "MK-1215 ") eeprom_quirk <= 4'b0010;  // X24C01 Evander Real Deal Holyfield's Boxing
			else if(cart_id[63:0] == "G-4060  ") eeprom_quirk <= 4'b0010;  // X24C01 Wonder Boy
			else if(cart_id[63:0] == "00001211") eeprom_quirk <= 4'b0010;  // X24C01 Sports Talk Baseball
			else if(cart_id[63:0] == "MK-1228 ") eeprom_quirk <= 4'b0010;  // X24C01 Greatest Heavyweights
			else if(cart_id[63:0] == "G-5538  ") eeprom_quirk <= 4'b0010;  // X24C01 Greatest Heavyweights JP
			else if(cart_id[63:0] == "PR-1993 ") eeprom_quirk <= 4'b0010;  // X24C01 Greatest Heavyweights (prototype)
			else if(cart_id[63:0] == "00004076") eeprom_quirk <= 4'b0010;  // X24C01 Honoo no Toukyuuji Dodge Danpei
			else if(cart_id[63:0] == "T-12046 ") eeprom_quirk <= 4'b0010;  // X24C01 Mega Man - The Wily Wars 
			else if(cart_id[63:0] == "T-12053 ") eeprom_quirk <= 4'b0010;  // X24C01 Rockman Mega World 
			else if(cart_id[63:0] == "G-4524  ") eeprom_quirk <= 4'b0010;  // X24C01 Ninja Burai Densetsu
			else if(cart_id[63:0] == "00054503") eeprom_quirk <= 4'b0010;  // X24C01 Game Toshokan
			else if(cart_id[63:0] == "T-81033 ") eeprom_quirk <= 4'b0011;  // 24C02 NBA Jam (J)
			else if(cart_id[63:0] == "T-081326") eeprom_quirk <= 4'b0011;  // 24C02 NBA Jam (U)(E)
			else if(cart_id[63:0] == "T-081276") eeprom_quirk <= 4'b1011;  // 24C02 NFL Quarterback Club
			else if(cart_id[63:0] == "T-81406 ") eeprom_quirk <= 4'b1111;  // 24C04 NBA Jam TE
			else if(cart_id[63:0] == "T-081586") eeprom_quirk <= 4'b1100;  // 24C16 NFL Quarterback Club '96
			else if(cart_id[63:0] == "T-81576 ") eeprom_quirk <= 4'b1101;  // 24C65 College Slam
			else if(cart_id[63:0] == "T-81476 ") eeprom_quirk <= 4'b1101;  // 24C65 Frank Thomas Big Hurt Baseball
			else if(cart_id[63:0] == "T-120106") eeprom_quirk <= 4'b0110;  // 24C08 Brian Lara Cricket
			else if(sp=="DNLD" && crc == 'h168B) eeprom_quirk <= 4'b0110;  // 24C08 JCART Micro Machines Military
			else if(sp=="DNLD" && crc == 'h165E) eeprom_quirk <= 4'b0100;  // 24C16 JCART Micro Machines Turbo Tournament 96
			else if(cart_id[63:0] == "T-120096") eeprom_quirk <= 4'b0100;  // 24C16 JCART Micro Machines 2 - Turbo Tournament
			else if(cart_id[63:0] == "T-120146") eeprom_quirk <= 4'b0101;  // 24C65 Brian Lara Cricket 96 / Shane Warne Cricket

// pocket: pier_quirk, svp_quirk and schan_quirk are tied off at their deletion
// sites above and the lightgun ports are gone, so the rows that set them (Pier
// Solar, Virtua Racing, Game no Kanzume Otokuyou) and the sensor-delay block that
// closed the upstream chain are dropped
			else if(cart_id[63:0] == "T-113016") noram_quirk  <= 1;        // Puggsy fake ram check
			else if(cart_id[63:0] == "T-35036 ") fmbusy_quirk <= 1;        // Hellfire US
			else if(cart_id[63:0] == "T-25073 ") fmbusy_quirk <= 1;        // Hellfire JP
			else if(cart_id[63:0] == "MK-1137-") fmbusy_quirk <= 1;        // Hellfire EU
			else if(cart_id[63:0] == "G-4034  ") fmbusy_quirk <= 1;        // DAISENPU/TWIN HAWK JP/EU
			else if(cart_id[63:0] == "T-44016 ") fmbusy_quirk <= 1;        // Tecmo World Cup
			else if(cart_id[63:0] == "T-44023 ") fmbusy_quirk <= 1;        // Tecmo World Cup JP
			else if(cart_id[63:0] == " GM 0000") sram00_quirk <= 1;        // Sonic 1 Remastered
			else if(cart_id[87:40] == "SF-001")  sf_quirk     <= {crc == 16'h3E08,2'b01}; // Beggar Prince (Unl), Beggar Prince rev 1 (Unl)
			else if(cart_id[87:40] == "SF-002")  sf_quirk     <= {1'b1,2'b10}; // Legend of Wukong (Unl)
			else if(cart_id[87:40] == "SF-004")  sf_quirk     <= {1'b1,2'b11}; // Star Odyssey (Unl)
// pocket-end
		end

// pocket: "RA" at $1B0 is the header's battery-RAM marker, and APF wants the save
// size in the data table before it will write a save file back
		if(cart_dl_addr == 'h1B0 && {cart_dl_data[7:0],cart_dl_data[15:8]} == "RA") sram_present <= 1;
// pocket-end

		if(cart_dl_addr == 'h7E100) realtec_id[31:16] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h7E102) realtec_id[15: 0] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h7E104 && realtec_id == "SEGA") realtec_quirk <= 1; // Earth Defend, Funny World & Balloon Boy, Whac-a-Critter
		
		if(cart_dl_addr[24:9]) crc_real <= crc_real + {cart_dl_data[7:0],cart_dl_data[15:8]};
		
		if(sf_quirk || svp_quirk || eeprom_quirk || pier_quirk) noram_quirk <= 1;
	end
	
	if(~cart_dl) begin
		if(crc == 'h0000 && crc_real == 'h7037) chk_quirk <= 1; // Ma Jiang Qing Ren - Ji Ma Jiang Zhi
		if(crc == 'h0000 && crc_real == 'h3b95) chk_quirk <= 1; // Super Majon Club
		if(crc == 'hffff && crc_real == 'h0474) chk_quirk <= 2; // Super Mario 2 1998
		if(crc == 'h2020 && crc_real == 'hb4eb) chk_quirk <= 3; // Super Mario World
	end
end

assign ym2612_quirk = fmbusy_quirk;

// pocket: an EEPROM cart carries no battery-RAM marker in its header, so APF's save
// size has to come from the quirk instead
assign eeprom_present = |eeprom_quirk;
// pocket-end

endmodule
