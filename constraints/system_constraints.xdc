#==============================================================================
# system_constraints.xdc
#
# Board/system constraints for bsg_link_test_top that are not part of the BSG
# Link physical interface or DDR source-synchronous timing.
#
# BSG Link-specific constraints live in:
#   placement_constraints.xdc
#   bsg_link_ddr_constraints.xdc
#==============================================================================

#------------------------------------------------------------------------------
# 1. System clock
#
# core_clk_i drives the AXI/JTAG-facing core domain and is also tied to the
# generic BSG Link upstream io_clk_i in bsg_link_test_top.
#------------------------------------------------------------------------------

set bsg_core_period 10.000
create_clock -period $bsg_core_period -name core_clk [get_ports core_clk_i]

# TODO: fill these from the chosen ZCU102 clock/reset wiring.
# set_property PACKAGE_PIN TODO_CORE_CLK [get_ports core_clk_i]
# set_property PACKAGE_PIN TODO_RST      [get_ports rst_i]

set_property IOSTANDARD LVCMOS18 [get_ports { \
  core_clk_i \
  rst_i \
}]

#------------------------------------------------------------------------------
# 2. Temporary clock-route overrides
#
# Existing routed reports show Vivado needs these overrides for the current
# token/downstream clock pin choices. Prefer replacing them with GC-capable pin
# choices or better clocking once the board routing is final.
#------------------------------------------------------------------------------

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets token_clk_i_IBUF[0]_inst/O]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets downstream_io_clk_i_IBUF[0]_inst/O]
