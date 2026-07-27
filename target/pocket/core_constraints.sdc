#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# SDRAM
# dram_clk is DDR-forwarded from PLL outclk_1 by the altddio_out inside
# rtl/upstream/sdram.sv with datain_h=0 / datain_l=1, hence -invert here. Must be
# defined before set_clock_groups, so the fitter sees it while optimizing
create_generated_clock -name sdram_clk -invert \
  -source [get_pins {ic|mp1|mf_pllbase_inst|sys_pll_i|cyclonev_pll|counter[1].output_counter|divclk}] \
  [get_ports {dram_clk}]

# All four sys_pll outputs come off the same VCO and are phase-related, so they
# share one group. The raster output samples the counter[1] domain from
# counter[2] directly, so that crossing has to stay timed
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|sys_pll_i|cyclonev_pll|counter[0].output_counter|divclk \
          ic|mp1|mf_pllbase_inst|sys_pll_i|cyclonev_pll|counter[1].output_counter|divclk \
          sdram_clk \
          ic|mp1|mf_pllbase_inst|sys_pll_i|cyclonev_pll|counter[2].output_counter|divclk \
          ic|mp1|mf_pllbase_inst|sys_pll_i|cyclonev_pll|counter[3].output_counter|divclk } \
 -group { ic|audio_out|audio_pll|mf_audio_pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|audio_out|audio_pll|mf_audio_pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk }

derive_clock_uncertainty

# Write path: tDS 1.5 ns setup, tDH 0.8 ns hold
set_output_delay -clock sdram_clk -max 1.5 \
  [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]
set_output_delay -clock sdram_clk -min -0.8 \
  [get_ports {dram_a[*] dram_ba[*] dram_dq[*] dram_dqm[*] dram_ras_n dram_cas_n dram_we_n dram_cke}]

# Read path, CAS latency 2: tAC 6.0 ns access from CLK, tOH 2.5 ns output hold
set_input_delay -clock sdram_clk -max 6.0 [get_ports {dram_dq[*]}]
set_input_delay -clock sdram_clk -min 2.5 [get_ports {dram_dq[*]}]

# The controller latches read data a fixed number of cycles after the READ, so the
# single-cycle 9.3 ns launch to capture that STA assumes never happens
set_multicycle_path -setup -from [get_clocks {sdram_clk}] \
  -to [get_clocks {ic|mp1|mf_pllbase_inst|sys_pll_i|cyclonev_pll|counter[1].output_counter|divclk}] 2
set_multicycle_path -hold -from [get_clocks {sdram_clk}] \
  -to [get_clocks {ic|mp1|mf_pllbase_inst|sys_pll_i|cyclonev_pll|counter[1].output_counter|divclk}] 1

# APF and platform I/O, either protocol timed or handled by the bridge logic
set_false_path -from [get_ports { \
  bridge_1wire bridge_spimiso bridge_spimosi bridge_spiss \
  cram0_dq[*] \
  port_tran_sck port_tran_sd port_tran_si \
}]

set_false_path -to [get_ports { \
  bridge_1wire bridge_spimiso bridge_spimosi \
  cram0_a[*] cram0_adv_n cram0_ce0_n cram0_ce1_n cram0_clk cram0_cre \
  cram0_dq[*] cram0_lb_n cram0_oe_n cram0_ub_n cram0_we_n \
  port_tran_sck port_tran_sck_dir port_tran_sd port_tran_sd_dir port_tran_so \
  scal_auddac scal_audlrck scal_audmclk scal_clk scal_de scal_hs scal_skip \
  scal_vid[*] scal_vs \
}]
