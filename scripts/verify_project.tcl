# Verifies that the generated project uses the source/build layout.
#
# Usage:
#   vivado -mode batch -source scripts/verify_project.tcl

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"
set PROJ_DIR   [file normalize "$REPO_ROOT/build/$PROJ_NAME"]
set XPR_FILE   [file normalize "$PROJ_DIR/$PROJ_NAME.xpr"]

if {![file exists $XPR_FILE]} {
  error "Project does not exist at $XPR_FILE. Run scripts/create_project.tcl first."
}

open_project $XPR_FILE

set source_files [get_files -quiet -of_objects [get_filesets sources_1]]
set sim_files    [get_files -quiet -of_objects [get_filesets sim_1]]
set xdc_files    [get_files -quiet -of_objects [get_filesets constrs_1] *.xdc]

set stale [list]
foreach f [concat $source_files $sim_files $xdc_files] {
  set normalized [file normalize $f]
  if {[string match "*/bsg_link_test/rtl/*" $normalized] ||
      [string match "*/bsg_link_test/tb/*" $normalized]} {
    lappend stale $normalized
  }
}

set required [list \
  "$REPO_ROOT/rtl/bsg_link_test_top.sv" \
  "$REPO_ROOT/rtl/bsg_link_xbar.sv" \
  "$REPO_ROOT/rtl/bsg_link_axi_tx_fifo.sv" \
  "$REPO_ROOT/rtl/bsg_link_axi_rx_fifo.sv" \
  "$REPO_ROOT/rtl/bsg_link_axi_rx_status.sv" \
  "$REPO_ROOT/sim/bsg_link_test_tb.sv" \
  "$REPO_ROOT/constraints/bsg_link_test_zcu102.xdc" \
]

set missing [list]
foreach f $required {
  if {[llength [get_files -quiet [file normalize $f]]] == 0} {
    lappend missing [file normalize $f]
  }
}

puts "verify_project.tcl: sources_1 file count: [llength $source_files]"
puts "verify_project.tcl: sim_1 file count: [llength $sim_files]"
puts "verify_project.tcl: constrs_1 XDC count: [llength $xdc_files]"

if {[llength $stale] > 0} {
  error "Generated project contains stale bsg_link_test source references:\n  [join $stale "\n  "]"
}
if {[llength $missing] > 0} {
  error "Generated project is missing required file(s):\n  [join $missing "\n  "]"
}
if {[llength $xdc_files] == 0} {
  error "Generated project has no XDC constraints in constrs_1"
}

puts "verify_project.tcl: project source, sim, and constraint references are valid"
close_project

