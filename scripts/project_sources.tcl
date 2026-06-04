# Shared source list for the bsg_link_vivado source-driven project flow.

proc bsg_link_project_basejump_root {repo_root} {
  if {[info exists ::env(BASEJUMP_STL_DIR)] && $::env(BASEJUMP_STL_DIR) ne ""} {
    return [file normalize $::env(BASEJUMP_STL_DIR)]
  }
  return [file normalize "$repo_root/../basejump_stl"]
}

proc bsg_link_project_require_files {files} {
  set missing [list]
  foreach f $files {
    if {![file exists $f]} {
      lappend missing $f
    }
  }
  if {[llength $missing] > 0} {
    error "Missing required source file(s):\n  [join $missing "\n  "]"
  }
}

proc bsg_link_project_add_sources {repo_root} {
  set repo_root [file normalize $repo_root]
  set rtl       [file normalize "$repo_root/rtl"]
  set sim       [file normalize "$repo_root/sim"]
  set bsl       [bsg_link_project_basejump_root $repo_root]

  set incdirs [list \
      $bsl/bsg_misc \
  ]
  set_property include_dirs $incdirs [get_filesets sources_1]
  set_property include_dirs $incdirs [get_filesets sim_1]

  set src_files [list \
      $bsl/bsg_misc/bsg_defines.sv \
      \
      $bsl/bsg_async/bsg_async_ptr_gray.sv \
      $bsl/bsg_async/bsg_launch_sync_sync.sv \
      $bsl/bsg_async/bsg_async_credit_counter.sv \
      $bsl/bsg_async/bsg_async_fifo.sv \
      \
      $bsl/bsg_misc/bsg_array_reverse.sv \
      $bsl/bsg_misc/bsg_circular_ptr.sv \
      $bsl/bsg_misc/bsg_counter_clear_up.sv \
      $bsl/bsg_misc/bsg_and.sv \
      $bsl/bsg_misc/bsg_mux.sv \
      $bsl/bsg_misc/bsg_gray_to_binary.sv \
      $bsl/bsg_misc/bsg_binary_plus_one_to_gray.sv \
      $bsl/bsg_misc/bsg_scan.sv \
      $bsl/bsg_misc/bsg_dff.sv \
      $bsl/bsg_misc/bsg_dff_reset.sv \
      $bsl/bsg_misc/bsg_dff_en.sv \
      \
      $bsl/bsg_mem/bsg_mem_1r1w_synth.sv \
      $bsl/bsg_mem/bsg_mem_1r1w.sv \
      $bsl/bsg_mem/bsg_mem_1r1w_sync_synth.sv \
      $bsl/bsg_mem/bsg_mem_1r1w_sync.sv \
      \
      $bsl/bsg_dataflow/bsg_fifo_tracker.sv \
      $bsl/bsg_dataflow/bsg_fifo_1r1w_small_unhardened.sv \
      $bsl/bsg_dataflow/bsg_fifo_1r1w_small_hardened.sv \
      $bsl/bsg_dataflow/bsg_fifo_1r1w_small.sv \
      $bsl/bsg_dataflow/bsg_one_fifo.sv \
      $bsl/bsg_dataflow/bsg_two_fifo.sv \
      $bsl/bsg_dataflow/bsg_parallel_in_serial_out.sv \
      $bsl/bsg_dataflow/bsg_serial_in_parallel_out_full.sv \
      $bsl/bsg_dataflow/bsg_round_robin_1_to_n.sv \
      \
      $bsl/hard/ultrascale_plus/bsg_link/bsg_link_oddr_phy.sv \
      $bsl/hard/ultrascale_plus/bsg_link/bsg_link_iddr_phy.sv \
      $bsl/bsg_link/bsg_link_source_sync_upstream.sv \
      $bsl/bsg_link/bsg_link_source_sync_downstream.sv \
      $bsl/hard/ultrascale_plus/bsg_link/bsg_link_ddr_upstream.sv \
      $bsl/bsg_link/bsg_link_ddr_downstream.sv \
      \
      $rtl/bsg_link_xbar_pkg.sv \
      $rtl/bsg_link_axi_tx_fifo.sv \
      $rtl/bsg_link_axi_rx_fifo.sv \
      $rtl/bsg_link_axi_rx_status.sv \
      $rtl/bsg_link_test_top.sv \
  ]
  bsg_link_project_require_files $src_files
  add_files -fileset sources_1 -norecurse $src_files

  set tb_file [file normalize "$sim/bsg_link_test_tb.sv"]
  bsg_link_project_require_files [list $tb_file]
  add_files -fileset sim_1 -norecurse $tb_file

  foreach f [concat $src_files [list $tb_file]] {
    if {[file extension $f] eq ".sv"} {
      set_property file_type SystemVerilog [get_files $f]
    }
  }

  puts "project_sources.tcl: added [llength $src_files] synthesis source file(s)"
  puts "project_sources.tcl: added 1 simulation source file"
}

