#==============================================================================
# bsg_link_test_zcu102.xdc
#
# ZCU102 constraints for bsg_link_test_top (CHANNEL_WIDTH_P=16).
# Timing/electrical structure follows:
#   - basejump_stl/hard/ultrascale_plus/bsg_link/tcl/bsg_link_ddr.sample_constraints.xdc
#   - mini_dice_zcu102/constraints/zcu102_pins.xdc
#
# Link pin PACKAGE_PINs are sourced directly from zcu102_pins.xdc
# (link_*_o -> upstream_io_*; link_*_i -> downstream_io_*).
# Control signal pins (clocks, resets) are still TODO — see section 1.
#==============================================================================

#------------------------------------------------------------------------------
# 1. System/control clocks and I/O standards
#    PACKAGE_PINs for these signals depend on ZCU102 clock routing (clk_wiz
#    outputs or SI570 direct) — fill in once the clocking plan is final.
#------------------------------------------------------------------------------

set bsg_core_period 10.000
set bsg_io_period   40.000

create_clock -period $bsg_core_period -name core_clk [get_ports core_clk_i]


set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets token_clk_i_IBUF[0]_inst/O]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets downstream_io_clk_i_IBUF[0]_inst/O]
# TODO: replace TODO_* with package pins from the board/cable map.
# set_property PACKAGE_PIN TODO_CORE_CLK [get_ports core_clk_i]
# set_property PACKAGE_PIN TODO_RST      [get_ports rst_i]

set_property IOSTANDARD LVCMOS18 [get_ports { \
  core_clk_i \
  rst_i \
}]

#------------------------------------------------------------------------------
# 2. bsg_link DDR pin map: FPGA upstream output side (FPGA → ASIC)
#    PACKAGE_PINs from zcu102_pins.xdc link_clk_o / link_valid_o /
#    link_data_o[0][0..15] / link_token_i[0].
#------------------------------------------------------------------------------

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

set bsg_up_out_ports [get_ports { \
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
set bsg_token_in_ports [get_ports {token_clk_i[0]}]

set_property IOSTANDARD        SSTL18_I   $bsg_up_out_ports
set_property SLEW              FAST       $bsg_up_out_ports
set_property OUTPUT_IMPEDANCE  RDRV_48_48 $bsg_up_out_ports

set_property IOSTANDARD SSTL18_I $bsg_token_in_ports
set_property ODT        RTT_48   $bsg_token_in_ports

#------------------------------------------------------------------------------
# 3. bsg_link DDR pin map: FPGA downstream input side (ASIC → FPGA)
#    PACKAGE_PINs from zcu102_pins.xdc link_clk_i / link_valid_i /
#    link_data_i[0][0..15] / link_token_o[0].
#------------------------------------------------------------------------------

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

set bsg_down_in_ports [get_ports { \
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
set bsg_token_out_ports [get_ports {downstream_core_token_r_o[0]}]

set_property IOSTANDARD SSTL18_I   $bsg_down_in_ports
set_property ODT        RTT_48     $bsg_down_in_ports

set_property IOSTANDARD        SSTL18_I   $bsg_token_out_ports
set_property SLEW              FAST       $bsg_token_out_ports
set_property OUTPUT_IMPEDANCE  RDRV_48_48 $bsg_token_out_ports

#------------------------------------------------------------------------------
# 4. Source-synchronous bsg_link DDR timing (all 16 data bits)
#------------------------------------------------------------------------------

create_clock -period $bsg_io_period -name downstream_io_clk_0 [get_ports {downstream_io_clk_i[0]}]
create_clock -period $bsg_io_period -name token_clk_0 [get_ports {token_clk_i[0]}]

set bsg_input_delay_max   2.0
set bsg_input_delay_min   0.5
set bsg_output_delay_max  2.0
set bsg_output_delay_min -0.5

set bsg_input_data_ports [get_ports { \
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

set_input_delay -clock downstream_io_clk_0 -max $bsg_input_delay_max $bsg_input_data_ports
set_input_delay -clock downstream_io_clk_0 -min $bsg_input_delay_min $bsg_input_data_ports
set_input_delay -clock downstream_io_clk_0 -max $bsg_input_delay_max $bsg_input_data_ports -clock_fall -add_delay
set_input_delay -clock downstream_io_clk_0 -min $bsg_input_delay_min $bsg_input_data_ports -clock_fall -add_delay

set bsg_output_clk_port [get_ports {upstream_io_clk_r_o[0]}]

# Behavioral oddr_phy (no ODDRE1): forwarded clock runs at io_master_clk rate.
# Declared as a primary clock; grouped with io_master_clk below.
create_clock -period $bsg_io_period -name upstream_io_clk_0 $bsg_output_clk_port

set bsg_output_data_ports [get_ports { \
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

set_output_delay -clock upstream_io_clk_0 -max $bsg_output_delay_max $bsg_output_data_ports
set_output_delay -clock upstream_io_clk_0 -min $bsg_output_delay_min $bsg_output_data_ports
set_output_delay -clock upstream_io_clk_0 -max $bsg_output_delay_max $bsg_output_data_ports -clock_fall -add_delay
set_output_delay -clock upstream_io_clk_0 -min $bsg_output_delay_min $bsg_output_data_ports -clock_fall -add_delay

#------------------------------------------------------------------------------
# 5. Clock groups
#    bsg_link crosses these domains with async FIFOs/synchronizers.
#------------------------------------------------------------------------------
set_clock_groups -asynchronous \
  -group [get_clocks {core_clk upstream_io_clk_0}] \
  -group [get_clocks downstream_io_clk_0] \
  -group [get_clocks token_clk_0]
