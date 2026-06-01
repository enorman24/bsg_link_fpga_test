# Simple JTAG-to-AXI smoke test for bsg_link_test.
#
# Usage after programming the FPGA:
#   vivado -mode batch -source scripts/drive_jtag_axi.tcl

set TX_ADDR     0x40000000
set RX_ADDR     0x40010000
set STA_STATUS  0x40020000
set STA_COUNT   0x40020004
set TEST_WORD   0xdeadbeef
set DRY_RUN     0

foreach arg $argv {
  if {$arg eq "--dry-run" || $arg eq "dry_run"} {
    set DRY_RUN 1
  }
}

proc fmt32 {value} {
  return [format %08X [expr {$value & 0xffffffff}]]
}

proc delete_txn_if_exists {name} {
  set old_txn [get_hw_axi_txns -quiet $name]
  if {[llength $old_txn] > 0} {
    delete_hw_axi_txn $old_txn
  }
}

proc axi_write32 {axi name addr data} {
  delete_txn_if_exists $name
  create_hw_axi_txn $name $axi \
    -type write \
    -address [fmt32 $addr] \
    -data [fmt32 $data]
  run_hw_axi [get_hw_axi_txns $name]
  report_hw_axi_txn [get_hw_axi_txns $name]
}

proc axi_read32 {axi name addr} {
  delete_txn_if_exists $name
  create_hw_axi_txn $name $axi \
    -type read \
    -address [fmt32 $addr] \
    -len 1
  run_hw_axi [get_hw_axi_txns $name]
  report_hw_axi_txn [get_hw_axi_txns $name]
  return [get_property DATA [get_hw_axi_txns $name]]
}

if {$DRY_RUN} {
  puts "DRY RUN: no hardware connection will be opened"
  puts "Would write [fmt32 $TEST_WORD] to TX FIFO at [fmt32 $TX_ADDR]"
  puts "Would read RX STATUS from [fmt32 $STA_STATUS]"
  puts "Would read RX COUNT  from [fmt32 $STA_COUNT]"
  puts "Would read RX DATA   from [fmt32 $RX_ADDR] if RX count is nonzero"
  exit 0
}

open_hw_manager
connect_hw_server
open_hw_target

set devices [get_hw_devices -quiet]
if {[llength $devices] == 0} {
  error "No hardware devices found. Is the board connected and powered?"
}

current_hw_device [lindex $devices 0]
refresh_hw_device [current_hw_device]

set axis [get_hw_axis -quiet]
if {[llength $axis] == 0} {
  error "No hw_axi objects found. Program the FPGA with a bitstream containing jtag_axi_0 first."
}

set axi [lindex $axis 0]
puts "Using JTAG AXI master: $axi"

puts "Writing [fmt32 $TEST_WORD] to TX FIFO at [fmt32 $TX_ADDR]"
axi_write32 $axi wr_tx_fifo $TX_ADDR $TEST_WORD

set status [axi_read32 $axi rd_status $STA_STATUS]
set count  [axi_read32 $axi rd_count  $STA_COUNT]

puts "RX STATUS @ [fmt32 $STA_STATUS] = $status"
puts "RX COUNT  @ [fmt32 $STA_COUNT]  = $count"

if {[scan $count %x count_value] == 1 && $count_value > 0} {
  set rx_data [axi_read32 $axi rd_rx_fifo $RX_ADDR]
  puts "RX DATA   @ [fmt32 $RX_ADDR]    = $rx_data"
} else {
  puts "RX FIFO appears empty; skipping RX read."
}
