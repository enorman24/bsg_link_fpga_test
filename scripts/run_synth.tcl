# Runs synthesis for the generated bsg_link_vivado project.
#
# Usage:
#   vivado -mode batch -source scripts/run_synth.tcl

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"
set PROJ_DIR   [file normalize "$REPO_ROOT/build/$PROJ_NAME"]
set XPR_FILE   [file normalize "$PROJ_DIR/$PROJ_NAME.xpr"]

if {![file exists $XPR_FILE]} {
  error "Project does not exist at $XPR_FILE. Run scripts/create_project.tcl first."
}

open_project $XPR_FILE
reset_run synth_1
launch_runs synth_1 -jobs 30
wait_on_run synth_1

set status [get_property STATUS [get_runs synth_1]]
puts "run_synth.tcl: synth_1 status: $status"
if {![string match "*Complete*" $status]} {
  error "synth_1 did not complete successfully"
}

close_project

