# Compatibility helper for adding project constraints to an existing project.
# New flows should use scripts/create_project.tcl.

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"

set project_file [file normalize "$REPO_ROOT/build/$PROJ_NAME/$PROJ_NAME.xpr"]
set xdc_file     [file normalize "$REPO_ROOT/constraints/bsg_link_test_zcu102.xdc"]

set close_project_when_done 0
if {[catch {current_project} current_proj] || $current_proj eq ""} {
  if {![file exists $project_file]} {
    error "Project does not exist at $project_file. Run scripts/create_project.tcl first."
  }
  open_project $project_file
  set close_project_when_done 1
}

set existing [get_files -quiet $xdc_file]
if {[llength $existing] == 0} {
  add_files -fileset constrs_1 -norecurse $xdc_file
}

set_property used_in_synthesis true [get_files $xdc_file]
set_property used_in_implementation true [get_files $xdc_file]

if {$close_project_when_done} {
  close_project
}
