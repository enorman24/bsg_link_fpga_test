#==============================================================================
# bsg_link_ddr_constraints.xdc
#
# Based on:
#   constraints/bsg_link_sample/bsg_link_ddr.sample_constraints.xdc
#
# The sample lines are kept commented where they do not directly map to this
# ZCU102/generic-PHY design. Active translated lines sit immediately below.
#
# Active timing structure and margins below come from the official BSG Link
# sample XDC where they map to this design.
#==============================================================================

# User should re-define periods / names / ports / pins / margins
# Then add the following lines into the .xdc constraint file

# create input clock
#
# Sample:
# set fmc_input_clk_period         2.000
# set fmc_input_clk_name           fmc_clk_in
# set fmc_input_clk_port           [get_ports fmc_clk_i]
# create_clock -name $fmc_input_clk_name -period $fmc_input_clk_period $fmc_input_clk_port
#
# Translated:
# Generic bsg_link_oddr_phy forwards clk_i divided by 2. In bsg_link_test_top,
# link_tx_i.io_clk_i is core_clk_i, currently constrained at 10 ns in
# system_constraints.xdc, so the expected forwarded BSG Link clock is 20 ns.
# If the peer drives downstream_io_clk_i at a different rate, update this value.
set fmc_input_clk_period         20.000
set fmc_input_clk_name           downstream_io_clk_0
set fmc_input_clk_port           [get_ports {downstream_io_clk_i[0]}]
create_clock -name $fmc_input_clk_name -period $fmc_input_clk_period $fmc_input_clk_port

# create output clock
#
# Sample:
# set fmc_output_clk_name          fmc_clk_out
# set fmc_output_clk_pin           [get_pins uplink/ch[0].oddr_phy/ODDRE1_clk/C]
# set fmc_output_clk_port          [get_ports fmc_clk_o]
# create_generated_clock -name $fmc_output_clk_name -source $fmc_output_clk_pin -edges {1 2 3} -edge_shift {0 0 0} $fmc_output_clk_port
#
# The sample generated-clock source is for the UltraScale+ hard PHY. This design
# currently uses the generic BaseJump PHY, so there is no ODDRE1_clk/C pin.
#
# Translated:
set fmc_output_clk_name          upstream_io_clk_0
# set fmc_output_clk_pin         [get_pins link_tx_i/ch[0].oddr_phy/ODDRE1_clk/C]
set fmc_output_clk_pin           [get_ports core_clk_i]
set fmc_output_clk_port          [get_ports {upstream_io_clk_r_o[0]}]
create_generated_clock -name $fmc_output_clk_name -source $fmc_output_clk_pin -divide_by 2 $fmc_output_clk_port

# input delay margins
set dv_bre                 1.0
set dv_are                 1.0
set dv_bfe                 1.0
set dv_afe                 1.0

# input delay constraints
#
# Sample:
# set fmc_input_data_port          [get_ports {fmc_data_i[*] fmc_v_i}]
# set_input_delay -clock $fmc_input_clk_name -max [expr $fmc_input_clk_period/2 - $dv_bre] $fmc_input_data_port
# set_input_delay -clock $fmc_input_clk_name -min $dv_are                                  $fmc_input_data_port
# set_input_delay -clock $fmc_input_clk_name -max [expr $fmc_input_clk_period/2 - $dv_bfe] $fmc_input_data_port -clock_fall -add_delay
# set_input_delay -clock $fmc_input_clk_name -min $dv_afe                                  $fmc_input_data_port -clock_fall -add_delay
#
# Translated:
set fmc_input_data_port [get_ports { \
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
set_input_delay -clock $fmc_input_clk_name -max [expr $fmc_input_clk_period/2 - $dv_bre] $fmc_input_data_port
set_input_delay -clock $fmc_input_clk_name -min $dv_are                                  $fmc_input_data_port
set_input_delay -clock $fmc_input_clk_name -max [expr $fmc_input_clk_period/2 - $dv_bfe] $fmc_input_data_port -clock_fall -add_delay
set_input_delay -clock $fmc_input_clk_name -min $dv_afe                                  $fmc_input_data_port -clock_fall -add_delay

# output delay margins
set tsu_r                  0.8
set thd_r                  0.8
set tsu_f                  0.8
set thd_f                  0.8

# output delay constraints
#
# Sample:
# set fmc_output_data_port         [get_ports {fmc_data_o[*] fmc_v_o}]
# set_output_delay -clock $fmc_output_clk_name -max [expr $fmc_input_clk_period/4 + $fmc_input_clk_period/2 - $tsu_r] $fmc_output_data_port
# set_output_delay -clock $fmc_output_clk_name -min [expr $fmc_input_clk_period/4 + $thd_r]                           $fmc_output_data_port
# set_output_delay -clock $fmc_output_clk_name -max [expr $fmc_input_clk_period/4 + $fmc_input_clk_period/2 - $tsu_f] $fmc_output_data_port -clock_fall -add_delay
# set_output_delay -clock $fmc_output_clk_name -min [expr $fmc_input_clk_period/4 + $thd_f]                           $fmc_output_data_port -clock_fall -add_delay
#
# Translated:
set fmc_output_data_port [get_ports { \
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
set_output_delay -clock $fmc_output_clk_name -max [expr $fmc_input_clk_period/4 + $fmc_input_clk_period/2 - $tsu_r] $fmc_output_data_port
set_output_delay -clock $fmc_output_clk_name -min [expr $fmc_input_clk_period/4 + $thd_r]                           $fmc_output_data_port
set_output_delay -clock $fmc_output_clk_name -max [expr $fmc_input_clk_period/4 + $fmc_input_clk_period/2 - $tsu_f] $fmc_output_data_port -clock_fall -add_delay
set_output_delay -clock $fmc_output_clk_name -min [expr $fmc_input_clk_period/4 + $thd_f]                           $fmc_output_data_port -clock_fall -add_delay

# Additional BSG Link timing not present in the sample XDC:
#
# token_clk_i[0] is a real input clock for the upstream credit-return path.
create_clock -name token_clk_0 -period $fmc_input_clk_period [get_ports {token_clk_i[0]}]

# bsg_link crosses these domains with async FIFOs/synchronizers.
set_clock_groups -asynchronous \
  -group [get_clocks {core_clk upstream_io_clk_0}] \
  -group [get_clocks downstream_io_clk_0] \
  -group [get_clocks token_clk_0]
