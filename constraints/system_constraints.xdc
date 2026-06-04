# #==============================================================================
# # system_constraints.xdc
# #
# # Board/system constraints for bsg_link_test_top that are not part of the BSG
# # Link physical interface or DDR source-synchronous timing.
# #
# # BSG Link-specific constraints live in:
# #   placement_constraints.xdc
# #   bsg_link_ddr_constraints.xdc
# #==============================================================================

# #------------------------------------------------------------------------------
# # 1. System clock
# #
# # clk_in1_p/n is the ZCU102 user_si570_sysclk (300 MHz differential, bank 65).
# # clk_wiz_0 divides this to 50 MHz for the internal core_clk_w.
# # The clk_wiz IP auto-generates the derived output clock constraint; only the
# # primary input clock needs a create_clock here.
# #------------------------------------------------------------------------------

# # ZCU102 bank 65 Si570: H9 (P) / H8 (N) — fill pins once board wiring is confirmed.
# # set_property PACKAGE_PIN H9 [get_ports clk_in1_p]
# # set_property PACKAGE_PIN H8 [get_ports clk_in1_n]
# set_property IOSTANDARD LVDS [get_ports {clk_in1_p clk_in1_n}]
# create_clock -name clk_in1_p -period 3.333 [get_ports clk_in1_p]

# # TODO: fill PACKAGE_PIN for rst_i once the ZCU102 button/GPIO pin is chosen.
# set_property IOSTANDARD LVCMOS18 [get_ports rst_i]

# #------------------------------------------------------------------------------
# # 2. Temporary clock-route overrides
# #
# # Existing routed reports show Vivado needs these overrides for the current
# # token/downstream clock pin choices. Prefer replacing them with GC-capable pin
# # choices or better clocking once the board routing is final.
# #------------------------------------------------------------------------------

# set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets token_clk_i_IBUF[0]_inst/O]
# set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets downstream_io_clk_i_IBUF[0]_inst/O]
