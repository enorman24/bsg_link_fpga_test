#==============================================================================
# create_project.tcl
#
# Recreates the bsg_link_vivado Vivado project from maintained source files.
# Generated project artifacts are written under build/bsg_link_vivado.
#
# Usage:
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
  puts "create_project.tcl: removing existing generated project at $PROJ_DIR"
  file delete -force $PROJ_DIR
}

create_project $PROJ_NAME $PROJ_DIR -part $PART
set_property board_part         $BOARD_PART [current_project]
set_property target_language    Verilog     [current_project]
set_property simulator_language Mixed       [current_project]
set_property default_lib        xil_defaultlib [current_project]

source "$SCRIPT_DIR/project_sources.tcl"
bsg_link_project_add_sources $REPO_ROOT

if {[file isdirectory $XDC_DIR]} {
  set xdc_files [list]
  foreach f [glob -nocomplain -directory $XDC_DIR *.xdc] {
    set name [file tail $f]
    if {[string match -nocase "*sample*" $name] ||
        [string match -nocase "*example*" $name]} {
      puts "create_project.tcl: skipping reference constraint file $name"
      continue
    }
    lappend xdc_files $f
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

set_property top $TOP_MODULE [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "create_project.tcl: created $PROJ_DIR/$PROJ_NAME.xpr"
close_project

