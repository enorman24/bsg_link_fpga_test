# Compatibility helper for adding required Vivado IP to an existing project.
# New project creation also generates these IPs via scripts/create_project.tcl.

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"

set project_file [file normalize "$REPO_ROOT/build/$PROJ_NAME/$PROJ_NAME.xpr"]

set close_project_when_done 0
if {[catch {current_project} current_proj] || $current_proj eq ""} {
  if {![file exists $project_file]} {
    error "Project does not exist at $project_file."
  }
  open_project $project_file
  set close_project_when_done 1
}

if {[llength [get_ips -quiet jtag_axi_0]] == 0} {
  create_ip -name jtag_axi -vendor xilinx.com -library ip -module_name jtag_axi_0
}
set_property -dict [list \
  CONFIG.RD_TXN_QUEUE_LENGTH {1} \
  CONFIG.WR_TXN_QUEUE_LENGTH {1} \
  CONFIG.M_HAS_BURST {1} \
  CONFIG.PROTOCOL {0} \
  CONFIG.M_AXI_DATA_WIDTH {32} \
  CONFIG.M_AXI_ADDR_WIDTH {32} \
  CONFIG.M_AXI_ID_WIDTH {1} \
] [get_ips jtag_axi_0]
generate_target all [get_ips jtag_axi_0]

if {[llength [get_ips -quiet axi_switch_0]] == 0} {
  create_ip -name axi_switch -vendor xilinx.com -library ip -version 1.0 -module_name axi_switch_0
}
set_property -dict [list \
  CONFIG.M00_SEG00_BASE_ADDR {0x40000000} \
  CONFIG.M00_SEG00_HIGH_ADDR {0x000000004000FFFF} \
  CONFIG.M01_SEG00_BASE_ADDR {0x40010000} \
  CONFIG.M01_SEG00_HIGH_ADDR {0x4001FFFF} \
  CONFIG.M02_AXI_PROTOCOL    {AXI4LITE} \
  CONFIG.M02_SEG00_BASE_ADDR {0x40020000} \
  CONFIG.M02_SEG00_HIGH_ADDR {0x4002FFFF} \
  CONFIG.M03_SEG00_BASE_ADDR {0x40030000} \
  CONFIG.M03_SEG00_HIGH_ADDR {0x4003FFFF} \
  CONFIG.M04_SEG00_BASE_ADDR {0x40040000} \
  CONFIG.M04_SEG00_HIGH_ADDR {0x4004FFFF} \
  CONFIG.M05_AXI_PROTOCOL    {AXI4LITE} \
  CONFIG.M05_SEG00_BASE_ADDR {0x40050000} \
  CONFIG.M05_SEG00_HIGH_ADDR {0x4005FFFF} \
  CONFIG.NUM_MI              {6} \
  CONFIG.NUM_SI              {1} \
  CONFIG.S00_AXI_ID_WIDTH    {1} \
  CONFIG.S00_SUPPORTS_NARROW {false} \
  CONFIG.S00_SUPPORTS_WRAP   {false} \
  CONFIG.SAME_AS_M00         {false} \
] [get_ips axi_switch_0]
generate_target all [get_ips axi_switch_0]

# ILA instances
foreach {mod_name num_probes probe0_w probe1_w probe2_w probe3_w probe4_w probe5_w} {
  ila_jtag_sw 6 12 32 32 32 32 4
  ila_sw_tx   6 12 32 32 32 32 4
  ila_sw_rx   6 12 32 32 32 32 4
  ila_sw_sta  6 12 32 32 32 32 4
  ila_tx_bsg  2  2 32  0  0  0 0
  ila_rx_bsg  2  2 32  0  0  0 0
  ila_rx_sta  1  8  0  0  0  0 0
  ila_sw_tx2  6 12 32 32 32 32 4
  ila_sw_rx2  6 12 32 32 32 32 4
  ila_sw_sta2 6 12 32 32 32 32 4
  ila_tx_bsg2 2  2 32  0  0  0 0
  ila_rx_bsg2 2  2 32  0  0  0 0
  ila_rx_sta2 1  8  0  0  0  0 0
} {
  if {[llength [get_ips -quiet $mod_name]] == 0} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name $mod_name
  }
  set props [list \
    CONFIG.C_NUM_OF_PROBES $num_probes \
    CONFIG.C_DATA_DEPTH     1024 \
    CONFIG.C_PROBE0_WIDTH   $probe0_w \
  ]
  if {$num_probes >= 2} { lappend props CONFIG.C_PROBE1_WIDTH $probe1_w }
  if {$num_probes >= 3} { lappend props CONFIG.C_PROBE2_WIDTH $probe2_w }
  if {$num_probes >= 4} { lappend props CONFIG.C_PROBE3_WIDTH $probe3_w }
  if {$num_probes >= 5} { lappend props CONFIG.C_PROBE4_WIDTH $probe4_w }
  if {$num_probes >= 6} { lappend props CONFIG.C_PROBE5_WIDTH $probe5_w }
  set_property -dict $props [get_ips $mod_name]
  generate_target all [get_ips $mod_name]
}

if {[llength [get_ips -quiet vio_0]] == 0} {
  create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
}
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN        {0} \
  CONFIG.C_PROBE_OUT0_INIT_VAL {0x1} \
] [get_ips vio_0]
generate_target all [get_ips vio_0]

if {[llength [get_ips -quiet clk_wiz_0]] == 0} {
  create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
}
set_property -dict [list \
  CONFIG.CLKIN1_JITTER_PS              {33.330000000000005} \
  CONFIG.CLKOUT1_JITTER                {116.415} \
  CONFIG.CLKOUT1_PHASE_ERROR           {77.836} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ    {50.000} \
  CONFIG.CLK_IN1_BOARD_INTERFACE       {user_si570_sysclk} \
  CONFIG.MMCM_CLKFBOUT_MULT_F          {4.000} \
  CONFIG.MMCM_CLKIN1_PERIOD            {3.333} \
  CONFIG.MMCM_CLKIN2_PERIOD            {10.0} \
  CONFIG.MMCM_CLKOUT0_DIVIDE_F         {24.000} \
  CONFIG.PRIM_IN_FREQ                  {300.000} \
  CONFIG.PRIM_SOURCE                   {Differential_clock_capable_pin} \
  CONFIG.USE_RESET                     {false} \
] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]

update_compile_order -fileset sources_1

puts "add_ips.tcl: required IP present: jtag_axi_0 axi_switch_0 clk_wiz_0 + 13 ILAs"

if {$close_project_when_done} {
  close_project
}
