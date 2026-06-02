#==============================================================================
# placement_constraints.xdc
#
# Based on:
#   constraints/bsg_link_sample/example_placement_constraints.xdc
#
# The sample is kept as the visual/reference structure. Lines that do not map
# to this ZCU102 design are commented out, with translated lines nearby when the
# intent still applies.
#
# This file is the active BSG Link physical-interface constraint file.
#==============================================================================

# This is an example for placing only one pin / one bank
# User should copy-n-paste these constraints for all pins / banks in the design

# Internal Vref for Conn
# User should modify bank numbers
#
# Sample:
# set_property INTERNAL_VREF 0.900 [get_iobanks 64]
#
# This design's SSTL18 BSG Link inputs are in HP banks 66 and 67.
set_property INTERNAL_VREF 0.900 [get_iobanks {66 67}]

# DCI Cascade
# The 240 ohm resistor can be cascaded to other banks if needed
#
# Sample:
set_property DCI_CASCADE {64} [get_iobanks 65]
#
# This design has not verified a ZCU102 DCI cascade requirement yet. Leave the
# sample constraint commented until the bank/reference-resistor plan is known.
# Example shape if bank 66 should cascade to bank 67:
# set_property DCI_CASCADE {66} [get_iobanks 67]

# Output Channel
# User should modify package_pins and port names
#
# Sample PACKAGE_PIN lines. The active lines below use this design's translated
# ZCU102 port/pin mapping.
# set_property PACKAGE_PIN B11      [get_ports { fmc_clk_o    }];
# set_property PACKAGE_PIN A14      [get_ports {   fmc_v_o    }];
# set_property PACKAGE_PIN F14      [get_ports { fmc_tkn_i    }]; # (GC)
# set_property PACKAGE_PIN G13      [get_ports {fmc_data_o[0] }];
#
# Translated:
set_property PACKAGE_PIN AF10 [get_ports {upstream_io_clk_r_o[0]}]
set_property PACKAGE_PIN AG11 [get_ports {upstream_io_valid_r_o[0]}]

set_property PACKAGE_PIN AE3  [get_ports {upstream_io_data_r_o[0][0]}]
set_property PACKAGE_PIN AH1  [get_ports {upstream_io_data_r_o[0][1]}]
set_property PACKAGE_PIN AH2  [get_ports {upstream_io_data_r_o[0][2]}]
set_property PACKAGE_PIN AH4  [get_ports {upstream_io_data_r_o[0][3]}]
set_property PACKAGE_PIN AG10 [get_ports {upstream_io_data_r_o[0][4]}]
set_property PACKAGE_PIN AH7  [get_ports {upstream_io_data_r_o[0][5]}]
set_property PACKAGE_PIN AB11 [get_ports {upstream_io_data_r_o[0][6]}]
set_property PACKAGE_PIN AF11 [get_ports {upstream_io_data_r_o[0][7]}]
set_property PACKAGE_PIN AE10 [get_ports {upstream_io_data_r_o[0][8]}]
set_property PACKAGE_PIN U10  [get_ports {upstream_io_data_r_o[0][9]}]
set_property PACKAGE_PIN W12  [get_ports {upstream_io_data_r_o[0][10]}]
set_property PACKAGE_PIN AF3  [get_ports {upstream_io_data_r_o[0][11]}]
set_property PACKAGE_PIN AJ1  [get_ports {upstream_io_data_r_o[0][12]}]
set_property PACKAGE_PIN AJ4  [get_ports {upstream_io_data_r_o[0][13]}]
set_property PACKAGE_PIN AG9  [get_ports {upstream_io_data_r_o[0][14]}]
set_property PACKAGE_PIN AH6  [get_ports {upstream_io_data_r_o[0][15]}]

set_property PACKAGE_PIN AB10 [get_ports {token_clk_i[0]}]

set placement_bsg_up_out_ports [get_ports { \
  upstream_io_clk_r_o[0] \
  upstream_io_valid_r_o[0] \
  upstream_io_data_r_o[0][0] \
  upstream_io_data_r_o[0][1] \
  upstream_io_data_r_o[0][2] \
  upstream_io_data_r_o[0][3] \
  upstream_io_data_r_o[0][4] \
  upstream_io_data_r_o[0][5] \
  upstream_io_data_r_o[0][6] \
  upstream_io_data_r_o[0][7] \
  upstream_io_data_r_o[0][8] \
  upstream_io_data_r_o[0][9] \
  upstream_io_data_r_o[0][10] \
  upstream_io_data_r_o[0][11] \
  upstream_io_data_r_o[0][12] \
  upstream_io_data_r_o[0][13] \
  upstream_io_data_r_o[0][14] \
  upstream_io_data_r_o[0][15] \
}]
set placement_bsg_token_in_ports [get_ports {token_clk_i[0]}]

# Sample:
# set_property IOSTANDARD  SSTL18_I  [get_ports {fmc_clk_o fmc_v_o fmc_data_o[*] fmc_tkn_i}];
# Alternaticely, replace SSTL18_I with SSTL18_I_DCI to enable DCI
# set_property SLEW        FAST      [get_ports {fmc_clk_o fmc_v_o fmc_data_o[*]}];
# set_property ODT         RTT_48    [get_ports {fmc_tkn_i}];
# set_property OUTPUT_IMPEDANCE RDRV_48_48 [get_ports {fmc_clk_o fmc_v_o fmc_data_o[*]}];
#
# Translated:
set_property IOSTANDARD        SSTL18_I   $placement_bsg_up_out_ports;
# Alternaticely, replace SSTL18_I with SSTL18_I_DCI to enable DCI
set_property SLEW              FAST       $placement_bsg_up_out_ports;
set_property ODT               RTT_48     $placement_bsg_token_in_ports;
set_property OUTPUT_IMPEDANCE  RDRV_48_48 $placement_bsg_up_out_ports;
set_property IOSTANDARD        SSTL18_I   $placement_bsg_token_in_ports;

# Input Channel
# User should modify package_pins and port names
#
# Sample PACKAGE_PIN lines. The active lines below use this design's translated
# ZCU102 port/pin mapping.
# set_property PACKAGE_PIN BJ4      [get_ports { fmc_clk_i    }]; # (GC)
# set_property PACKAGE_PIN BN6      [get_ports {   fmc_v_i    }];
# set_property PACKAGE_PIN BN5      [get_ports { fmc_tkn_o    }];
# set_property PACKAGE_PIN BF7      [get_ports {fmc_data_i[0] }];
#
# Translated:
set_property PACKAGE_PIN AC6  [get_ports {downstream_io_clk_i[0]}]
set_property PACKAGE_PIN AA12 [get_ports {downstream_io_valid_i[0]}]

set_property PACKAGE_PIN V4   [get_ports {downstream_io_data_i[0][0]}]
set_property PACKAGE_PIN Y2   [get_ports {downstream_io_data_i[0][1]}]
set_property PACKAGE_PIN AC2  [get_ports {downstream_io_data_i[0][2]}]
set_property PACKAGE_PIN W5   [get_ports {downstream_io_data_i[0][3]}]
set_property PACKAGE_PIN Y12  [get_ports {downstream_io_data_i[0][4]}]
set_property PACKAGE_PIN AC7  [get_ports {downstream_io_data_i[0][5]}]
set_property PACKAGE_PIN N13  [get_ports {downstream_io_data_i[0][6]}]
set_property PACKAGE_PIN M15  [get_ports {downstream_io_data_i[0][7]}]
set_property PACKAGE_PIN M11  [get_ports {downstream_io_data_i[0][8]}]
set_property PACKAGE_PIN M10  [get_ports {downstream_io_data_i[0][9]}]
set_property PACKAGE_PIN V9   [get_ports {downstream_io_data_i[0][10]}]
set_property PACKAGE_PIN V8   [get_ports {downstream_io_data_i[0][11]}]
set_property PACKAGE_PIN V12  [get_ports {downstream_io_data_i[0][12]}]
set_property PACKAGE_PIN V3   [get_ports {downstream_io_data_i[0][13]}]
set_property PACKAGE_PIN Y1   [get_ports {downstream_io_data_i[0][14]}]
set_property PACKAGE_PIN AC1  [get_ports {downstream_io_data_i[0][15]}]

set_property PACKAGE_PIN W4   [get_ports {downstream_core_token_r_o[0]}]

set placement_bsg_down_in_ports [get_ports { \
  downstream_io_clk_i[0] \
  downstream_io_valid_i[0] \
  downstream_io_data_i[0][0] \
  downstream_io_data_i[0][1] \
  downstream_io_data_i[0][2] \
  downstream_io_data_i[0][3] \
  downstream_io_data_i[0][4] \
  downstream_io_data_i[0][5] \
  downstream_io_data_i[0][6] \
  downstream_io_data_i[0][7] \
  downstream_io_data_i[0][8] \
  downstream_io_data_i[0][9] \
  downstream_io_data_i[0][10] \
  downstream_io_data_i[0][11] \
  downstream_io_data_i[0][12] \
  downstream_io_data_i[0][13] \
  downstream_io_data_i[0][14] \
  downstream_io_data_i[0][15] \
}]
set placement_bsg_token_out_ports [get_ports {downstream_core_token_r_o[0]}]

# Sample:
# set_property IOSTANDARD  SSTL18_I  [get_ports {fmc_clk_i fmc_v_i fmc_data_i[*] fmc_tkn_o}];
# Alternaticely, replace SSTL18_I with SSTL18_I_DCI to enable DCI
# set_property ODT         RTT_48    [get_ports {fmc_clk_i fmc_v_i fmc_data_i[*]}];
# set_property SLEW        FAST      [get_ports {fmc_tkn_o}];
# set_property OUTPUT_IMPEDANCE RDRV_48_48 [get_ports {fmc_tkn_o}];
#
# Translated:
set_property IOSTANDARD        SSTL18_I   $placement_bsg_down_in_ports;
# Alternaticely, replace SSTL18_I with SSTL18_I_DCI to enable DCI
set_property ODT               RTT_48     $placement_bsg_down_in_ports;
set_property SLEW              FAST       $placement_bsg_token_out_ports;
set_property OUTPUT_IMPEDANCE  RDRV_48_48 $placement_bsg_token_out_ports;
set_property IOSTANDARD        SSTL18_I   $placement_bsg_token_out_ports;

# placement constraints
# User should modify the clockregions and get_cells list
#
# Sample pblocks. These do not map directly: this design uses link_tx_i and
# link_rx_i, not uplink/upstream_node and downlink/downstream_node. The sample
# CLOCKREGION_X4Y6/X4Y5 regions also need to be re-derived for this ZCU102 pin
# map before active pblocks are added.
#
# create_pblock                    pblock_up01
# add_cells_to_pblock [get_pblocks pblock_up01] [get_cells -quiet [list uplink upstream_node]]
# resize_pblock       [get_pblocks pblock_up01] -add {CLOCKREGION_X4Y6:CLOCKREGION_X4Y6}
#
# create_pblock                    pblock_down01
# add_cells_to_pblock [get_pblocks pblock_down01] [get_cells -quiet [list downlink downstream_node]]
# resize_pblock       [get_pblocks pblock_down01] -add {CLOCKREGION_X4Y5:CLOCKREGION_X4Y5}

# Derived inactive template for this design:
# create_pblock                    pblock_up01
# add_cells_to_pblock [get_pblocks pblock_up01] [get_cells -quiet [list link_tx_i]]
# resize_pblock       [get_pblocks pblock_up01] -add {CLOCKREGION_X?Y?:CLOCKREGION_X?Y?}
#
# create_pblock                    pblock_down01
# add_cells_to_pblock [get_pblocks pblock_down01] [get_cells -quiet [list link_rx_i]]
# resize_pblock       [get_pblocks pblock_down01] -add {CLOCKREGION_X?Y?:CLOCKREGION_X?Y?}
