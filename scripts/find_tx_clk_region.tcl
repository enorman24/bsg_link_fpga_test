open_checkpoint /home/enorman/bsg_link/bsg_link_vivado/build/bsg_link_vivado/bsg_link_vivado.runs/synth_1/bsg_link_test_top.dcp

set tx_pins {AD7 AG11 AE3 AH1 AH2 AH4 AG10 AH7 AB11 AF11 AE10 U10 W12 AF3 AJ1 AJ4 AG9 AH6}

puts "\n=== TX output pin -> bank -> clock region ==="
set regions_seen {}
foreach pin $tx_pins {
  set bank   [get_property BANK        [get_package_pins $pin]]
  set func   [get_property PIN_FUNC    [get_package_pins $pin]]
  # Get the IOB site for this pin, then its clock region
  set site   [get_sites -of_objects [get_package_pins $pin]]
  set region [get_property CLOCK_REGION [get_sites $site]]
  puts "  $pin  bank=$bank  region=$region  site=$site  func=$func"
  if {$region ne "" && [lsearch $regions_seen $region] == -1} {
    lappend regions_seen $region
  }
}

puts "\n=== Clock regions used: $regions_seen ==="

close_design
