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

if {[llength [get_ips -quiet axi_crossbar]] == 0} {
  create_ip -name axi_switch -vendor xilinx.com -library ip -version 1.0 -module_name axi_crossbar
}
set_property -dict [list \
  CONFIG.M00_SEG00_BASE_ADDR {0x40000000} \
  CONFIG.M00_SEG00_HIGH_ADDR {0x000000004000FFFF} \
  CONFIG.M01_SEG00_BASE_ADDR {0x40010000} \
  CONFIG.M01_SEG00_HIGH_ADDR {0x4001FFFF} \
  CONFIG.M02_SEG00_BASE_ADDR {0x40020000} \
  CONFIG.M02_SEG00_HIGH_ADDR {0x4002FFFF} \
  CONFIG.NUM_MI {3} \
  CONFIG.NUM_SI {1} \
  CONFIG.S00_AXI_ID_WIDTH {1} \
  CONFIG.S00_SUPPORTS_NARROW {false} \
  CONFIG.S00_SUPPORTS_WRAP {false} \
  CONFIG.SAME_AS_M00 {true} \
] [get_ips axi_crossbar]
generate_target all [get_ips axi_crossbar]

update_compile_order -fileset sources_1

puts "add_ips.tcl: required IP present: jtag_axi_0 axi_crossbar"

if {$close_project_when_done} {
  close_project
}
