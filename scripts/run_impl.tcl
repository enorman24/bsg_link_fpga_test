# Runs implementation and bitstream generation for the bsg_link_vivado project.
# Writes reports to build/impl/ and the bitstream to build/impl/.
#
# Usage:
#   vivado -mode batch -source scripts/run_impl.tcl
#   make impl

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"
set PROJ_DIR   [file normalize "$REPO_ROOT/build/$PROJ_NAME"]
set XPR_FILE   [file normalize "$PROJ_DIR/$PROJ_NAME.xpr"]
set IMPL_DIR   [file normalize "$REPO_ROOT/build/impl"]
set JOBS       [expr {[info exists ::env(BSG_LINK_JOBS)] ? $::env(BSG_LINK_JOBS) : 25}]

if {![file exists $XPR_FILE]} {
  error "Project does not exist at $XPR_FILE. Run scripts/create_project.tcl first."
}

file mkdir $IMPL_DIR

open_project $XPR_FILE

set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
  puts "run_impl.tcl: synth_1 not complete ($synth_status), running synthesis first"
  reset_run synth_1
  launch_runs synth_1 -jobs $JOBS
  wait_on_run synth_1
  set synth_status [get_property STATUS [get_runs synth_1]]
  if {![string match "*Complete*" $synth_status]} {
    error "synth_1 did not complete successfully: $synth_status"
  }
}

reset_run impl_1
launch_runs impl_1 -jobs $JOBS
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "run_impl.tcl: impl_1 status: $impl_status"
if {![string match "*Complete*" $impl_status]} {
  error "impl_1 did not complete successfully: $impl_status"
}

open_run impl_1
report_utilization    -file "$IMPL_DIR/utilization.rpt"
report_timing_summary -file "$IMPL_DIR/timing_summary.rpt"
report_power          -file "$IMPL_DIR/power.rpt"
report_route_status   -file "$IMPL_DIR/route_status.rpt"
report_drc            -file "$IMPL_DIR/drc.rpt"

puts "run_impl.tcl: reports written to $IMPL_DIR"

launch_runs impl_1 -to_step write_bitstream -jobs $JOBS
wait_on_run impl_1

set bit_status [get_property STATUS [get_runs impl_1]]
puts "run_impl.tcl: write_bitstream status: $bit_status"
if {![string match "*write_bitstream Complete*" $bit_status]} {
  error "write_bitstream did not complete successfully: $bit_status"
}

foreach f [glob -nocomplain "$PROJ_DIR/$PROJ_NAME.runs/impl_1/*.bit"] {
  file copy -force $f "$IMPL_DIR/[file tail $f]"
  puts "run_impl.tcl: bitstream written to $IMPL_DIR/[file tail $f]"
}

close_project
