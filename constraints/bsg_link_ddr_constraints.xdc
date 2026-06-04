#==============================================================================
# bsg_link_ddr_constraints.xdc
#
# Based on:
#   constraints/bsg_link_sample/bsg_link_ddr.sample_constraints.xdc
#
# The sample lines are kept commented where they do not directly map to this
# ZCU102/UltraScale+ hard-PHY design. Active translated lines sit immediately below.
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
# The UltraScale+ hard ODDR PHY drives clk_r_o from an ODDRE1 clocked by
# io_clk90_i (50 MHz, 90° phase). ODDRE1 with D1=1 / D2=0 outputs the full
# 50 MHz clock, so the forwarded BSG Link clock is 50 MHz → 20 ns period.
# In loopback, downstream_io_clk_i receives this forwarded clock, so this value
# must match. Update if the peer drives downstream_io_clk_i at a different rate.
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
# Translated:
# The hard PHY uses ODDRE1_clk (clocked by io_clk90_i) to forward the link
# clock. The generated-clock source is that ODDRE1's C pin; -edges {1 2 3}
# with no shift models the full-rate output at the same frequency as clk_out2.
# Verify the exact pin path after first synthesis run.
set fmc_output_clk_name          upstream_io_clk_0
set fmc_output_clk_pin           [get_pins link_tx_i/ch[0].oddr_phy/ODDRE1_clk/C]
set fmc_output_clk_port          [get_ports {upstream_io_clk_r_o[0]}]
create_generated_clock -name $fmc_output_clk_name -source $fmc_output_clk_pin -edges {1 2 3} -edge_shift {0 0 0} $fmc_output_clk_port

# ---- Shared source-synchronous margin budget (TX output == RX input) ----
# This link is a loopback: the upstream_io_* outputs feed the downstream_io_*
# inputs through the ribbon, so both ends model the SAME physical link and must
# reserve the SAME data-to-forwarded-clock margin. These two numbers therefore
# drive BOTH the RX set_input_delay (below) and the TX set_output_delay (further
# down) — do not let them drift apart.
#
# Anchored to the verified receiver: in the routed build the downstream IDDRE1
# captures the looped-back data with +0.6 ns setup / +0.04 ns hold under this
# 1.0 ns budget (report_timing -to link_rx_i/ch[0].iddr_phy/.../IDDRE1_inst/D,
# group downstream_io_clk_0). So 1.0 ns is not a guess — it is the margin the
# real capture flop is shown to tolerate with positive slack.
#
# Budget = IDDRE1 setup/hold (after the FIXED IDELAYE3, DELAY_VALUE=192)
#        + data<->clk skew through the ribbon + 2x F2G GPIO headers + guardband.
# Refine on hardware (bench IDELAY tap sweep) and re-tighten. NOTE: the hold side
# is the real risk (downstream hold is only +0.04 ns, set by DELAY_VALUE), and an
# IDELAYCTRL (REFCLK 500 MHz) must be added before these numbers hold on silicon.
set link_setup_margin      1.0
set link_hold_margin       1.0

# input delay margins (RX) — driven by the shared budget
set dv_bre                 $link_setup_margin
set dv_are                 $link_hold_margin
set dv_bfe                 $link_setup_margin
set dv_afe                 $link_hold_margin

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

# output delay margins (TX) — SAME shared budget as the RX input above.
# Was 0.8 (sample placeholder, inconsistent with the 1.0 ns RX model). Driving
# both ends from link_setup_margin/link_hold_margin makes the TX output_delay
# reserve exactly the margin the receiver is verified to need.
set tsu_r                  $link_setup_margin
set thd_r                  $link_hold_margin
set tsu_f                  $link_setup_margin
set thd_f                  $link_hold_margin

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
# clk_out1_clk_wiz_0 and clk_out2_clk_wiz_0 are the auto-generated names Vivado
# assigns to the 50 MHz 0° and 90° clk_wiz_0 outputs; they are synchronous to
# each other (same MMCM source) and treated as one group.
# Verify the exact clock names after first synthesis run if the clock group fails.
set_clock_groups -asynchronous \
  -group [get_clocks {clk_out1_clk_wiz_0 clk_out2_clk_wiz_0 upstream_io_clk_0}] \
  -group [get_clocks downstream_io_clk_0] \
  -group [get_clocks token_clk_0]
