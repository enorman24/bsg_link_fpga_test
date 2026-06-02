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

create_ip -name axi_switch -vendor xilinx.com -library ip -version 1.0 -module_name axi_crossbar
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

set_property top $TOP_MODULE [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "create_project.tcl: created $PROJ_DIR/$PROJ_NAME.xpr"
close_project
