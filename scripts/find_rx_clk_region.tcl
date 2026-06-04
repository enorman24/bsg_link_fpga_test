open_checkpoint /home/enorman/bsg_link/bsg_link_vivado/build/bsg_link_vivado/bsg_link_vivado.runs/synth_1/bsg_link_test_top.dcp

set rx_pins {AC4 AA12 V4 Y2 AC2 W5 Y12 AC7 N13 M15 M11 M10 V9 V8 V12 V3 Y1 AC1}

puts "\n=== RX input pin -> bank -> clock region ==="
set regions_seen {}
foreach pin $rx_pins {
  set bank   [get_property BANK       [get_package_pins $pin]]
  set site   [get_sites -of_objects   [get_package_pins $pin]]
  set region [get_property CLOCK_REGION [get_sites $site]]
  puts "  $pin  bank=$bank  region=$region  site=$site"
  if {$region ne "" && [lsearch $regions_seen $region] == -1} {
    lappend regions_seen $region
  }
}
puts "\n=== RX clock regions: $regions_seen ==="
close_design
