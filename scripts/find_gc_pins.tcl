open_checkpoint /home/enorman/bsg_link/bsg_link_vivado/build/bsg_link_vivado/bsg_link_vivado.runs/synth_1/bsg_link_test_top.dcp

foreach bank {66 67} {
  puts "\n=== IS_GLOBAL_CLK pins in bank $bank ==="
  set gc_pins [get_package_pins -filter "BANK == $bank && IS_GLOBAL_CLK == 1"]
  if {[llength $gc_pins] == 0} {
    puts "  (none)"
  } else {
    foreach pin $gc_pins {
      set func  [get_property PIN_FUNC   [get_package_pins $pin]]
      set bond  [get_property IS_BONDED  [get_package_pins $pin]]
      set used  [get_property IS_USED    [get_package_pins $pin]]
      set mast  [get_property IS_MASTER  [get_package_pins $pin]]
      set diff  [get_property DIFF_PAIR_PIN [get_package_pins $pin]]
      puts "  $pin  bonded=$bond  used=$used  master=$mast  pair=$diff  func=$func"
    }
  }
}

close_design
