#=============================================================================
# bsg_link_integrity.tcl
#
# AXI-JTAG link-integrity tests for the bsg_link loopback FPGA image
# (bsg_link_test_top + jtag_axi_0). Drives the JTAG-to-AXI master, pushes
# patterns through the upstream TX -> ribbon -> downstream RX path, and verifies
# what comes back.
#
# Preconditions
#   - Bitstream programmed (jtag_axi_0 present as a hw_axi).
#   - PHYSICAL loopback in place: upstream_io_* cabled to downstream_io_*
#     (F2G GPIO_1 on FMC_HPC1  <->  F2G GPIO_0 on FMC_HPC0, straight-through).
#   - The image powers up HELD IN RESET by vio_0 probe_out0 (init=1).
#     bsg_link_open releases it.
#
# Memory map (bsg_link_xbar_pkg / bsg_link_test_top)
#   0x4000_0000  TX_DATA   WO  push one 32-bit flit into the upstream TX FIFO
#   0x4001_0000  RX_DATA   RO  pop  one 32-bit flit from the downstream RX FIFO
#   0x4002_0000  RX_STATUS RO  bit[1]=full  bit[0]=empty
#   0x4002_0004  RX_COUNT  RO  flits currently in the RX FIFO (0..32)
#   0x4002_0008  RX_CTRL   WO  bit[0]=flush  (NOTE: not wired in current RTL -> no-op;
#                              this library drains by reading, never relies on flush)
#
# Notes
#   - A 32-bit flit is serialized over the 16-bit DDR channel, so a 32-bit word
#     exercises all 16 data lanes on BOTH DDR phases. walking-1/walking-0 cover
#     every lane/phase; the sticky error mask localises a stuck/open lane.
#   - Batches are kept <= RX FIFO depth so the RX never overflows and JTAG writes
#     never stall on backpressure.
#
# Usage
#   source scripts/bsg_link_integrity.tcl
#   set axi [bsg_link_open]            ;# connect, pick hw_axi, release VIO reset
#   bsg_link_test_all $axi             ;# full suite -> PASS/FAIL summary
#   # individual tests also return {ntested nfail errmask}:
#   bsg_link_test_walking_ones $axi
#   bsg_link_test_prbs $axi 1000
#=============================================================================

# ---- configuration (override after sourcing if needed) ----
set ::BSG_TX_DATA   0x40000000
set ::BSG_RX_DATA   0x40010000
set ::BSG_RX_STATUS 0x40020000
set ::BSG_RX_COUNT  0x40020004
set ::BSG_RX_CTRL   0x40020008
set ::BSG_RX_DEPTH  32     ;# RX FIFO depth (LG_RX_FIFO_DEPTH_P = 5)
set ::BSG_BATCH     16     ;# words per write/read chunk (< depth: no overflow/stall)
set ::BSG_POLL_MAX  100    ;# RX_COUNT polls before declaring a word lost

# ============================================================================
# Low-level AXI access (single beat; unambiguous FIFO ordering)
# ============================================================================
proc bsg_h32 {v} { return [format %08X [expr {$v & 0xffffffff}]] }

proc bsg_wr32 {axi addr data} {
  catch {delete_hw_axi_txn [get_hw_axi_txns -quiet bsg_wr]}
  create_hw_axi_txn bsg_wr $axi -type write \
    -address [bsg_h32 $addr] -data [bsg_h32 $data]
  run_hw_axi [get_hw_axi_txns bsg_wr]
}

proc bsg_rd32 {axi addr} {
  catch {delete_hw_axi_txn [get_hw_axi_txns -quiet bsg_rd]}
  create_hw_axi_txn bsg_rd $axi -type read -address [bsg_h32 $addr] -len 1
  run_hw_axi [get_hw_axi_txns bsg_rd]
  set hex [get_property DATA [get_hw_axi_txns bsg_rd]]
  return [expr {("0x$hex") & 0xffffffff}]
}

# ---- status helpers ----
proc bsg_rx_count  {axi} { return [bsg_rd32 $axi $::BSG_RX_COUNT] }
proc bsg_rx_status {axi} { return [bsg_rd32 $axi $::BSG_RX_STATUS] }
proc bsg_rx_empty  {axi} { return [expr {[bsg_rx_status $axi] & 0x1}] }
proc bsg_rx_full   {axi} { return [expr {([bsg_rx_status $axi] >> 1) & 0x1}] }

# Read every word currently in the RX FIFO (flush is a no-op in RTL).
proc bsg_drain {axi} {
  set n 0
  set guard [expr {($::BSG_RX_DEPTH + 8) * 4}]
  while {[bsg_rx_count $axi] > 0 && $n < $guard} {
    bsg_rd32 $axi $::BSG_RX_DATA
    incr n
  }
  return $n
}

# Poll RX_COUNT until it reaches target (or time out). Returns the count seen.
proc bsg_wait_count {axi target} {
  for {set i 0} {$i < $::BSG_POLL_MAX} {incr i} {
    set c [bsg_rx_count $axi]
    if {$c >= $target} { return $c }
  }
  return [bsg_rx_count $axi]
}

# ============================================================================
# Core round: drain, then send/receive/compare a word list in safe chunks.
# Returns {ntested nfail errmask}. errmask = OR of (sent ^ received) over all
# mismatching words -> a set bit means that flit bit failed at least once.
# ============================================================================
proc bsg_round {axi label words} {
  bsg_drain $axi
  set total [llength $words]
  set ntest 0 ; set nfail 0 ; set emask 0 ; set lost 0 ; set shown 0
  for {set off 0} {$off < $total} {incr off $::BSG_BATCH} {
    set chunk [lrange $words $off [expr {$off + $::BSG_BATCH - 1}]]
    set k [llength $chunk]

    foreach w $chunk { bsg_wr32 $axi $::BSG_TX_DATA $w }
    bsg_wait_count $axi $k
    set avail [bsg_rx_count $axi]

    set recv {}
    for {set j 0} {$j < $avail} {incr j} { lappend recv [bsg_rd32 $axi $::BSG_RX_DATA] }

    for {set j 0} {$j < $k} {incr j} {
      incr ntest
      set exp [lindex $chunk $j]
      if {$j >= [llength $recv]} { incr nfail ; incr lost ; continue }
      set act [lindex $recv $j]
      if {$act != $exp} {
        incr nfail
        set e [expr {($exp ^ $act) & 0xffffffff}]
        set emask [expr {$emask | $e}]
        if {$shown < 8} {
          puts [format "  \[%s\] MISMATCH idx %d: exp %08X got %08X  (err %08X)" \
                $label [expr {$off + $j}] $exp $act $e]
          incr shown
        }
      }
    }
    if {$avail > $k} {
      puts [format "  \[%s\] WARNING: %d spurious word(s) after chunk @%d" \
            $label [expr {$avail - $k}] $off]
      incr nfail [expr {$avail - $k}]
    }
    bsg_drain $axi
  }
  if {$lost > 0} {
    puts [format "  \[%s\] %d word(s) never looped back (link loss / timeout)" $label $lost]
  }
  set verdict [expr {$nfail == 0 ? "PASS" : "FAIL"}]
  puts [format "  %-18s %s  tested=%-4d errors=%-4d sticky-errmask=%08X" \
        $label $verdict $ntest $nfail $emask]
  return [list $ntest $nfail $emask]
}

# ============================================================================
# Pattern tests (each returns {ntested nfail errmask})
# ============================================================================
proc bsg_test_const {axi val {n 16}} {
  set w {} ; for {set i 0} {$i < $n} {incr i} { lappend w $val }
  return [bsg_round $axi [format "const-%08X" [expr {$val & 0xffffffff}]] $w]
}

proc bsg_test_walking_ones {axi} {
  set w {} ; for {set b 0} {$b < 32} {incr b} { lappend w [expr {(1 << $b) & 0xffffffff}] }
  return [bsg_round $axi "walking-ones" $w]
}

proc bsg_test_walking_zeros {axi} {
  set w {} ; for {set b 0} {$b < 32} {incr b} { lappend w [expr {(~(1 << $b)) & 0xffffffff}] }
  return [bsg_round $axi "walking-zeros" $w]
}

# Alternating 0xAAAAAAAA / 0x55555555 stresses adjacent-lane shorts / crosstalk.
proc bsg_test_aa55 {axi {n 32}} {
  set w {}
  for {set i 0} {$i < $n} {incr i} { lappend w [expr {$i & 1 ? 0x55555555 : 0xAAAAAAAA}] }
  return [bsg_round $axi "aa55-crosstalk" $w]
}

proc bsg_test_incrementing {axi {n 64} {base 0xA0000000}} {
  set w {} ; for {set i 0} {$i < $n} {incr i} { lappend w [expr {($base + $i) & 0xffffffff}] }
  return [bsg_round $axi "incrementing" $w]
}

# 32-bit xorshift (Marsaglia) - long pseudo-random sequence for volume/soak.
proc bsg_xorshift32 {x} {
  set x [expr {$x & 0xffffffff}]
  if {$x == 0} { set x 1 }
  set x [expr {($x ^ ($x << 13)) & 0xffffffff}]
  set x [expr {($x ^ ($x >> 17)) & 0xffffffff}]
  set x [expr {($x ^ ($x << 5))  & 0xffffffff}]
  return $x
}
proc bsg_test_prbs {axi {n 256} {seed 0xDEADBEEF}} {
  set w {} ; set s $seed
  for {set i 0} {$i < $n} {incr i} { set s [bsg_xorshift32 $s] ; lappend w $s }
  return [bsg_round $axi "prbs-x$n" $w]
}

# ============================================================================
# Sanity / status / connection
# ============================================================================
proc bsg_bits_set {mask} {
  set l {}
  for {set b 0} {$b < 32} {incr b} { if {($mask >> $b) & 1} { lappend l $b } }
  return $l
}

proc bsg_link_status {axi} {
  set st [bsg_rx_status $axi] ; set ct [bsg_rx_count $axi]
  puts [format "  RX_STATUS=%08X (empty=%d full=%d)  RX_COUNT=%d" \
        $st [expr {$st & 1}] [expr {($st >> 1) & 1}] $ct]
}

# Single-word smoke test: confirms reset is released, the loopback is cabled,
# and the link clock is running before the bulk patterns run.
proc bsg_link_sanity {axi} {
  bsg_drain $axi
  bsg_link_status $axi
  set tok 0xC0FFEE5A
  bsg_wr32 $axi $::BSG_TX_DATA $tok
  if {[bsg_wait_count $axi 1] < 1} {
    puts "  ERROR: single-word loopback FAILED (RX_COUNT stayed 0)."
    puts "         Check: VIO reset released? loopback cabled? io/link clock alive?"
    return 0
  }
  set rb [bsg_rd32 $axi $::BSG_RX_DATA]
  bsg_drain $axi
  if {$rb != $tok} {
    puts [format "  ERROR: smoke mismatch exp %08X got %08X" $tok $rb] ; return 0
  }
  puts [format "  smoke: wrote/read-back %08X OK" $tok]
  return 1
}

# Release the vio_0 reset (probe_out0, init=1 -> held in reset).
proc bsg_link_release_reset {} {
  set vios [get_hw_vios -quiet]
  if {[llength $vios] == 0} {
    puts "bsg_link_release_reset: no hw_vio found (no .ltx?); assuming reset already released"
    return
  }
  set committed {}
  foreach vio $vios {
    foreach p [get_hw_probes -quiet -of_objects $vio] {
      if {![catch {set_property OUTPUT_VALUE 0 [get_hw_probes $p]}]} { lappend committed $p }
    }
  }
  if {[llength $committed] > 0} {
    commit_hw_vio $committed
    puts "bsg_link_release_reset: deasserted [llength $committed] VIO output probe(s)"
  }
}

# Connect to the board, select the JTAG-AXI master, release reset.
proc bsg_link_open {{device_index 0}} {
  if {[catch {current_hw_target}]} {
    open_hw_manager
    connect_hw_server
    open_hw_target
  }
  set devs [get_hw_devices -quiet]
  if {[llength $devs] == 0} { error "no hw devices found - board connected / powered?" }
  current_hw_device [lindex $devs $device_index]
  refresh_hw_device -quiet [current_hw_device]
  bsg_link_release_reset
  set axis [get_hw_axis -quiet]
  if {[llength $axis] == 0} { error "no hw_axi - program a bitstream containing jtag_axi_0 first" }
  set axi [lindex $axis 0]
  puts "bsg_link_open: using JTAG-AXI master $axi"
  return $axi
}

# ============================================================================
# Full suite
# ============================================================================
proc bsg_link_test_all {axi {volume 512}} {
  puts "=============================================="
  puts "  bsg_link loopback integrity suite"
  puts "=============================================="
  if {![bsg_link_sanity $axi]} {
    puts "ABORT: sanity/smoke failed - link not up. Fix before running patterns."
    return 0
  }
  set tt 0 ; set tf 0 ; set gmask 0
  foreach r [list \
        [bsg_test_const         $axi 0x00000000] \
        [bsg_test_const         $axi 0xFFFFFFFF] \
        [bsg_test_walking_ones   $axi] \
        [bsg_test_walking_zeros  $axi] \
        [bsg_test_aa55           $axi 32] \
        [bsg_test_incrementing   $axi 64] \
        [bsg_test_prbs           $axi $volume] ] {
    lassign $r nt nf em
    incr tt $nt ; incr tf $nf ; set gmask [expr {$gmask | $em}]
  }
  puts "----------------------------------------------"
  puts [format "TOTAL  tested=%d  errors=%d  global-errmask=%08X  -> %s" \
        $tt $tf $gmask [expr {$tf == 0 ? "LINK OK" : "LINK FAILED"}]]
  if {$tf != 0} {
    puts [format "  failing flit bits: %s" [bsg_bits_set $gmask]]
    puts "  (a bit failing across patterns => stuck/open data lane;"
    puts "   flit bit b uses physical data lane b%16 on DDR phase b/16)"
  }
  return [expr {$tf == 0}]
}

# Continuous soak: run the PRBS test forever (or 'iters' times), stop on first error.
proc bsg_link_soak {axi {iters 0} {chunk 512}} {
  set i 0 ; set seed 0x12345678
  while {$iters == 0 || $i < $iters} {
    incr i
    set seed [bsg_xorshift32 $seed]
    lassign [bsg_test_prbs $axi $chunk $seed] nt nf em
    if {$nf != 0} {
      puts [format "SOAK STOPPED at iter %d: %d errors, errmask=%08X" $i $nf $em]
      return 0
    }
    if {$i % 20 == 0} { puts [format "  soak: %d iters x %d words clean" $i $chunk] }
  }
  puts [format "SOAK OK: %d iters x %d words clean" $i $chunk]
  return 1
}

puts "bsg_link_integrity.tcl loaded. Start with:  set axi \[bsg_link_open\] ; bsg_link_test_all \$axi"
