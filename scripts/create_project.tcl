#==============================================================================
# create_project.tcl
#
# Creates the bsg_link_vivado Vivado project from maintained source files.
# Generated project artifacts are written under build/bsg_link_vivado.
#
# Usage:
#   vivado -mode batch -source scripts/create_project.tcl
#
# To intentionally remove and rebuild an existing generated project:
#   export BSG_LINK_FORCE_RECREATE=1
#   vivado -mode batch -source scripts/create_project.tcl
#==============================================================================

set PROJ_NAME  "bsg_link_vivado"
set PART       "xczu9eg-ffvb1156-2-e"
set BOARD_PART "xilinx.com:zcu102:part0:3.4"
set TOP_MODULE "bsg_link_test_top"

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set BUILD_DIR  [file normalize "$REPO_ROOT/build"]
set PROJ_DIR   [file normalize "$BUILD_DIR/$PROJ_NAME"]
set XDC_DIR    [file normalize "$REPO_ROOT/constraints"]

file mkdir $BUILD_DIR
if {[file isdirectory $PROJ_DIR]} {
  if {[info exists ::env(BSG_LINK_FORCE_RECREATE)] && $::env(BSG_LINK_FORCE_RECREATE) ne ""} {
    puts "create_project.tcl: removing existing generated project at $PROJ_DIR"
    file delete -force $PROJ_DIR
  } else {
    error "Project already exists at $PROJ_DIR. Use scripts/add_constraints.tcl to update constraints, or set BSG_LINK_FORCE_RECREATE=1 to intentionally rebuild."
  }
}

create_project $PROJ_NAME $PROJ_DIR -part $PART
set_property board_part         $BOARD_PART [current_project]
set_property target_language    Verilog     [current_project]
set_property simulator_language Mixed       [current_project]
set_property default_lib        xil_defaultlib [current_project]

source "$SCRIPT_DIR/project_sources.tcl"
bsg_link_project_add_sources $REPO_ROOT

if {[file isdirectory $XDC_DIR]} {
  set xdc_files [list \
    [file normalize "$XDC_DIR/system_constraints.xdc"] \
    [file normalize "$XDC_DIR/placement_constraints.xdc"] \
    [file normalize "$XDC_DIR/bsg_link_ddr_constraints.xdc"] \
  ]
  set missing_xdc_files [list]
  foreach f $xdc_files {
    if {![file exists $f]} {
      lappend missing_xdc_files $f
    }
  }
  if {[llength $missing_xdc_files] > 0} {
    error "create_project.tcl: missing required constraint file(s):\n  [join $missing_xdc_files "\n  "]"
  }
  if {[llength $xdc_files] > 0} {
    add_files -fileset constrs_1 -norecurse $xdc_files
    set_property used_in_synthesis true [get_files $xdc_files]
    set_property used_in_implementation true [get_files $xdc_files]
    puts "create_project.tcl: added [llength $xdc_files] constraint file(s)"
  }
}

create_ip -name jtag_axi -vendor xilinx.com -library ip -module_name jtag_axi_0
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

create_ip -name axi_switch -vendor xilinx.com -library ip -version 1.0 -module_name axi_switch_0
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

# ILA: JTAG AXI master ↔ AXI switch (S00)
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_jtag_sw
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {12} \
  CONFIG.C_PROBE1_WIDTH   {32} \
  CONFIG.C_PROBE2_WIDTH   {32} \
  CONFIG.C_PROBE3_WIDTH   {32} \
  CONFIG.C_PROBE4_WIDTH   {32} \
  CONFIG.C_PROBE5_WIDTH   {4} \
] [get_ips ila_jtag_sw]
generate_target all [get_ips ila_jtag_sw]

# ILA: AXI switch M00 ↔ TX FIFO
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_sw_tx
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {12} \
  CONFIG.C_PROBE1_WIDTH   {32} \
  CONFIG.C_PROBE2_WIDTH   {32} \
  CONFIG.C_PROBE3_WIDTH   {32} \
  CONFIG.C_PROBE4_WIDTH   {32} \
  CONFIG.C_PROBE5_WIDTH   {4} \
] [get_ips ila_sw_tx]
generate_target all [get_ips ila_sw_tx]

# ILA: AXI switch M01 ↔ RX FIFO
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_sw_rx
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {12} \
  CONFIG.C_PROBE1_WIDTH   {32} \
  CONFIG.C_PROBE2_WIDTH   {32} \
  CONFIG.C_PROBE3_WIDTH   {32} \
  CONFIG.C_PROBE4_WIDTH   {32} \
  CONFIG.C_PROBE5_WIDTH   {4} \
] [get_ips ila_sw_rx]
generate_target all [get_ips ila_sw_rx]

# ILA: AXI switch M02 ↔ RX status register map
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_sw_sta
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {12} \
  CONFIG.C_PROBE1_WIDTH   {32} \
  CONFIG.C_PROBE2_WIDTH   {32} \
  CONFIG.C_PROBE3_WIDTH   {32} \
  CONFIG.C_PROBE4_WIDTH   {32} \
  CONFIG.C_PROBE5_WIDTH   {4} \
] [get_ips ila_sw_sta]
generate_target all [get_ips ila_sw_sta]

# ILA: TX FIFO ↔ BSG link TX core
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_tx_bsg
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {2} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {2} \
  CONFIG.C_PROBE1_WIDTH   {32} \
] [get_ips ila_tx_bsg]
generate_target all [get_ips ila_tx_bsg]

# ILA: RX FIFO ↔ BSG link RX core
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_rx_bsg
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {2} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {2} \
  CONFIG.C_PROBE1_WIDTH   {32} \
] [get_ips ila_rx_bsg]
generate_target all [get_ips ila_rx_bsg]

# ILA: RX FIFO status signals ↔ RX status register map
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_rx_sta
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {1} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {8} \
] [get_ips ila_rx_sta]
generate_target all [get_ips ila_rx_sta]

# ===== Link 2 ILAs (reverse-direction link; mirror the link-1 set) =====
# ILA: AXI switch M03 ↔ TX2 FIFO
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_sw_tx2
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {12} \
  CONFIG.C_PROBE1_WIDTH   {32} \
  CONFIG.C_PROBE2_WIDTH   {32} \
  CONFIG.C_PROBE3_WIDTH   {32} \
  CONFIG.C_PROBE4_WIDTH   {32} \
  CONFIG.C_PROBE5_WIDTH   {4} \
] [get_ips ila_sw_tx2]
generate_target all [get_ips ila_sw_tx2]

# ILA: AXI switch M04 ↔ RX2 FIFO
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_sw_rx2
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {12} \
  CONFIG.C_PROBE1_WIDTH   {32} \
  CONFIG.C_PROBE2_WIDTH   {32} \
  CONFIG.C_PROBE3_WIDTH   {32} \
  CONFIG.C_PROBE4_WIDTH   {32} \
  CONFIG.C_PROBE5_WIDTH   {4} \
] [get_ips ila_sw_rx2]
generate_target all [get_ips ila_sw_rx2]

# ILA: AXI switch M05 ↔ RX2 status register map
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_sw_sta2
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {6} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {12} \
  CONFIG.C_PROBE1_WIDTH   {32} \
  CONFIG.C_PROBE2_WIDTH   {32} \
  CONFIG.C_PROBE3_WIDTH   {32} \
  CONFIG.C_PROBE4_WIDTH   {32} \
  CONFIG.C_PROBE5_WIDTH   {4} \
] [get_ips ila_sw_sta2]
generate_target all [get_ips ila_sw_sta2]

# ILA: TX2 FIFO ↔ BSG link TX2 core
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_tx_bsg2
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {2} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {2} \
  CONFIG.C_PROBE1_WIDTH   {32} \
] [get_ips ila_tx_bsg2]
generate_target all [get_ips ila_tx_bsg2]

# ILA: RX2 FIFO ↔ BSG link RX2 core
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_rx_bsg2
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {2} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {2} \
  CONFIG.C_PROBE1_WIDTH   {32} \
] [get_ips ila_rx_bsg2]
generate_target all [get_ips ila_rx_bsg2]

# ILA: RX2 FIFO status signals ↔ RX2 status register map
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_rx_sta2
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {1} \
  CONFIG.C_DATA_DEPTH     {1024} \
  CONFIG.C_PROBE0_WIDTH   {8} \
] [get_ips ila_rx_sta2]
generate_target all [get_ips ila_rx_sta2]

create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN        {0} \
  CONFIG.C_PROBE_OUT0_INIT_VAL {0x1} \
] [get_ips vio_0]
generate_target all [get_ips vio_0]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
set_property -dict [list \
  CONFIG.CLKIN1_JITTER_PS              {33.330000000000005} \
  CONFIG.CLKOUT1_JITTER                {116.415} \
  CONFIG.CLKOUT1_PHASE_ERROR           {77.836} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ    {50.000} \
  CONFIG.CLKOUT2_USED                  {true} \
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ    {50.000} \
  CONFIG.CLKOUT2_REQUESTED_PHASE       {90.000} \
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

set_property top $TOP_MODULE [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "create_project.tcl: created $PROJ_DIR/$PROJ_NAME.xpr"
close_project
