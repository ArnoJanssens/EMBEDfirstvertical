# Pynq-Z2 audio codec I2S pin constraints
# Check the Pynq-Z2 schematic for your specific board revision

set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { sys_clk }]; #IO_L13P_T2_MRCC_35 Sch=sysclk
create_clock -add -name sys_clk_pin -period 8.00 -waveform {0 4} [get_ports { sys_clk }];

set_property PACKAGE_PIN D19 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

# SW0: input-source select ('0' = ADAU line-in, '1' = Pmod line-in)
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports { sw_src }];

set_property PACKAGE_PIN U5  [get_ports mclk_out]
set_property PACKAGE_PIN R18 [get_ports bclk_out]
set_property PACKAGE_PIN T17 [get_ports lrclk_out]

set_property PACKAGE_PIN F17 [get_ports sdata_in] 
set_property PACKAGE_PIN G18 [get_ports sdata_out]

set_property IOSTANDARD LVCMOS33 [get_ports mclk_out]
set_property IOSTANDARD LVCMOS33 [get_ports bclk_out]
set_property IOSTANDARD LVCMOS33 [get_ports lrclk_out]
set_property IOSTANDARD LVCMOS33 [get_ports sdata_in]
set_property IOSTANDARD LVCMOS33 [get_ports sdata_out]

# ADAU1761 Shared I2C Control Bus Pins
set_property -dict { PACKAGE_PIN U9   IOSTANDARD LVCMOS33 } [get_ports { audio_scl }];
set_property -dict { PACKAGE_PIN T9   IOSTANDARD LVCMOS33 } [get_ports { audio_sda }];
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports { cfg_ok }];    # LD0
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { led_pllen }]; # LD1
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { led_lock }];  # LD2

# =============================================================================
# AD2 debug mirror -> Pmod JA (clip the Analog Discovery 2 here)
#   JA pinout (top row): JA1 JA2 JA3 JA4  GND VCC
#               (bot row): JA7 JA8 JA9 JA10 GND VCC
# Connect an AD2 DGND wire to a JA GND pin (JA pin 5 or 11).
# =============================================================================
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports { dbg_scl }];       # JA1
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports { dbg_sda }];       # JA2
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports { dbg_mclk }];      # JA3
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports { dbg_bclk }];      # JA4
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { dbg_lrclk }];     # JA7
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports { dbg_sdata_in }];  # JA8
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports { dbg_sdata_out }]; # JA9
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports { dbg_pmod_sdout }]; # JA10

# =============================================================================
# Pmod JB: Digilent Pmod I2S2
#   Top row    (JB1-4) : CS4344 DAC, line-out (green) jack
#   Bottom row (JB7-10): CS5343 ADC, line-in (blue) jack
# Pin functions per Digilent Pmod-I2S2 demo constraints.
# =============================================================================
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports { pmod_tx_mclk }];  # JB1
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports { pmod_tx_lrck }];  # JB2
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { pmod_tx_sclk }];  # JB3
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { pmod_tx_sdin }];  # JB4
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports { pmod_rx_mclk }];  # JB7
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports { pmod_rx_lrck }];  # JB8
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { pmod_rx_sclk }];  # JB9
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports { pmod_rx_sdout }]; # JB10

