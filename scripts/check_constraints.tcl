# check_constraints.tcl
# Verifies the bsg_link_test XDC against the latest synthesized checkpoint.
#
# Usage:
#   vivado -mode batch -source scripts/check_constraints.tcl

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"
set PROJ_DIR   [file normalize "$REPO_ROOT/build/$PROJ_NAME"]

set dcp_file   [file normalize "$PROJ_DIR/bsg_link_vivado.runs/synth_1/bsg_link_test_top.dcp"]
set xdc_file   [file normalize "$REPO_ROOT/constraints/bsg_link_test_zcu102.xdc"]
set report_dir [file normalize "$PROJ_DIR/reports/constraints"]

if {![file exists $dcp_file]} {
  error "Synthesized checkpoint does not exist at $dcp_file. Run scripts/run_synth.tcl first."
}

file mkdir $report_dir

open_checkpoint $dcp_file
read_xdc $xdc_file

report_clocks -file "$report_dir/bsg_link_test_clocks.rpt"
report_drc -file "$report_dir/bsg_link_test_drc_after_xdc.rpt"
report_timing_summary -file "$report_dir/bsg_link_test_timing_summary.rpt"

close_design
