# Runs synthesis for the bsg_link_vivado project and writes reports to build/synth/.
#
# Usage:
#   vivado -mode batch -source scripts/run_synth.tcl
#   make synth

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"
set PROJ_DIR   [file normalize "$REPO_ROOT/build/$PROJ_NAME"]
set XPR_FILE   [file normalize "$PROJ_DIR/$PROJ_NAME.xpr"]
set SYNTH_DIR  [file normalize "$REPO_ROOT/build/synth"]
set JOBS       [expr {[info exists ::env(BSG_LINK_JOBS)] ? $::env(BSG_LINK_JOBS) : 25}]

if {![file exists $XPR_FILE]} {
  error "Project does not exist at $XPR_FILE. Run scripts/create_project.tcl first."
}

file mkdir $SYNTH_DIR

open_project $XPR_FILE
reset_run synth_1
launch_runs synth_1 -jobs $JOBS
wait_on_run synth_1

set status [get_property STATUS [get_runs synth_1]]
puts "run_synth.tcl: synth_1 status: $status"
if {![string match "*Complete*" $status]} {
  error "synth_1 did not complete successfully: $status"
}

open_run synth_1
report_utilization       -file "$SYNTH_DIR/utilization.rpt"
report_timing_summary    -file "$SYNTH_DIR/timing_summary.rpt"
report_clock_interaction -file "$SYNTH_DIR/clock_interaction.rpt"

puts "run_synth.tcl: reports written to $SYNTH_DIR"
close_project
