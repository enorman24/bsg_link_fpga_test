# Compatibility helper for adding bsg_link_test sources to an existing project.
# New flows should use scripts/create_project.tcl.

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set PROJ_NAME  "bsg_link_vivado"
set PROJECT_FILE [file normalize "$REPO_ROOT/build/$PROJ_NAME/$PROJ_NAME.xpr"]

source "$SCRIPT_DIR/project_sources.tcl"

set close_project_when_done 0
if {[catch {current_project} current_proj] || $current_proj eq ""} {
  if {![file exists $PROJECT_FILE]} {
    error "Project does not exist at $PROJECT_FILE. Run scripts/create_project.tcl first."
  }
  open_project $PROJECT_FILE
  set close_project_when_done 1
}

bsg_link_project_add_sources $REPO_ROOT

if {$close_project_when_done} {
  close_project
}
