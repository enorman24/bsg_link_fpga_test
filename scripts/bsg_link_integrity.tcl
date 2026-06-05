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
#   - PHYSICAL loopback(s) in place, straight-through:
#       Link 1: upstream_io_*  (F2G GPIO_1 on FMC_HPC1) <-> downstream_io_*  (F2G GPIO_0 on FMC_HPC0)
#       Link 2: upstream2_io_* (F2G GPIO_0 on FMC_HPC1) <-> downstream2_io_* (F2G GPIO_1 on FMC_HPC0)
#     (Only the link you intend to test needs its ribbon installed.)
#   - The image powers up HELD IN RESET by vio_0 probe_out0 (init=1).
#     bsg_link_open releases it.
#
# Two links share the one JTAG-AXI master; select which one the tests drive with
# bsg_link_select 1|2 (default 1). Each link has its own FIFOs/status:
#
# Memory map (bsg_link_xbar_pkg / bsg_link_test_top)
#   Link 1                                Link 2
#   0x4000_0000  TX_DATA   WO             0x4003_0000  TX2_DATA   WO
#   0x4001_0000  RX_DATA   RO             0x4004_0000  RX2_DATA   RO
#   0x4002_0000  RX_STATUS RO  bit1=full  0x4005_0000  RX2_STATUS RO  bit0=empty
#   0x4002_0004  RX_COUNT  RO  (0..32)    0x4005_0004  RX2_COUNT  RO
#   0x4002_0008  RX_CTRL   WO  flush      0x4005_0008  RX2_CTRL   WO  (not wired -> no-op;
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
# Per-link address maps. Link 1 = forward, Link 2 = reverse-direction link.
array set ::BSG_LINK1 {
  tx_data   0x40000000
  rx_data   0x40010000
  rx_status 0x40020000
  rx_count  0x40020004
  rx_ctrl   0x40020008
}
array set ::BSG_LINK2 {
  tx_data   0x40030000
  rx_data   0x40040000
  rx_status 0x40050000
  rx_count  0x40050004
  rx_ctrl   0x40050008
}
set ::BSG_RX_DEPTH  32     ;# RX FIFO depth (LG_RX_FIFO_DEPTH_P = 5)
set ::BSG_BATCH     16     ;# words per write/read chunk (< depth: no overflow/stall)
set ::BSG_POLL_MAX  100    ;# RX_COUNT polls before declaring a word lost
set ::BSG_LINK_SEL  0      ;# currently-selected link (set by bsg_link_select below)

# Point the active address globals (::BSG_TX_DATA etc.) at link $n (1 or 2).
# Every test proc operates on whichever link is currently selected.
proc bsg_link_select {{n 1}} {
  if {$n == 1} {
    array set m [array get ::BSG_LINK1]
  } elseif {$n == 2} {
    array set m [array get ::BSG_LINK2]
  } else {
    error "bsg_link_select: link must be 1 or 2 (got $n)"
  }
  set ::BSG_TX_DATA   $m(tx_data)
  set ::BSG_RX_DATA   $m(rx_data)
  set ::BSG_RX_STATUS $m(rx_status)
  set ::BSG_RX_COUNT  $m(rx_count)
  set ::BSG_RX_CTRL   $m(rx_ctrl)
  set ::BSG_LINK_SEL  $n
  return $n
}
bsg_link_select 1   ;# default to link 1 (backward compatible)

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

# Poll an explicit RX_COUNT address until it reaches target (for testing a link
# other than the currently-selected one, e.g. the concurrent both-links test).
proc bsg_wait_count_at {axi count_addr target} {
  for {set i 0} {$i < $::BSG_POLL_MAX} {incr i} {
    if {[bsg_rd32 $axi $count_addr] >= $target} { return 1 }
  }
  return 0
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
  # Idempotent connect — works from a fresh batch session AND an already-open GUI
  # Hardware Manager. (current_hw_target only warns when nothing is open, so it
  # cannot be used as a catch-guard.)
  catch {open_hw_manager}
  if {[llength [get_hw_servers -quiet]] == 0} { connect_hw_server }
  set tgts [get_hw_targets -quiet]
  if {[llength $tgts] == 0} { error "no JTAG targets - board connected/powered, cable seated?" }
  if {[catch {get_property NAME [current_hw_target]}]} { open_hw_target [lindex $tgts 0] }
  set devs [get_hw_devices -quiet]
  if {[llength $devs] == 0} { error "no hw devices found on the target" }
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
  puts [format "  bsg_link loopback integrity suite (LINK %d)" $::BSG_LINK_SEL]
  puts [format "  TX=%08X RX=%08X STATUS=%08X" $::BSG_TX_DATA $::BSG_RX_DATA $::BSG_RX_STATUS]
  puts "=============================================="
  if {![bsg_link_sanity $axi]} {
    puts "WARNING: sanity/smoke failed - link may be down; running patterns anyway."
    puts "         (pattern results below will show where/how it fails)"
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

# Run the full suite on a specific link (selects it first, then restores nothing —
# the selection persists so follow-up individual tests hit the same link).
proc bsg_link_test_link {axi n {volume 512}} {
  bsg_link_select $n
  return [bsg_link_test_all $axi $volume]
}

# Run the full suite on BOTH links in sequence. Requires both ribbons installed.
proc bsg_link_test_both {axi {volume 512}} {
  set ok1 [bsg_link_test_link $axi 1 $volume]
  set ok2 [bsg_link_test_link $axi 2 $volume]
  puts "=============================================="
  puts [format "BOTH LINKS:  link1=%s  link2=%s" \
        [expr {$ok1 ? "LINK OK" : "LINK FAILED"}] [expr {$ok2 ? "LINK OK" : "LINK FAILED"}]]
  return [expr {$ok1 && $ok2}]
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

# Round-robin soak over BOTH links (alternates link 1 / link 2 each iteration).
# Stops on the first error on either link. Leaves link 1 selected when done.
proc bsg_link_soak_both {axi {iters 0} {chunk 256}} {
  set i 0 ; set s1 0x1111AAAA ; set s2 0x2222BBBB
  while {$iters == 0 || $i < $iters} {
    incr i
    bsg_link_select 1 ; set s1 [bsg_xorshift32 $s1]
    lassign [bsg_test_prbs $axi $chunk $s1] nt1 nf1 em1
    bsg_link_select 2 ; set s2 [bsg_xorshift32 $s2]
    lassign [bsg_test_prbs $axi $chunk $s2] nt2 nf2 em2
    if {$nf1 != 0 || $nf2 != 0} {
      puts [format "SOAK-BOTH STOPPED at iter %d: link1 errors=%d (%08X)  link2 errors=%d (%08X)" \
            $i $nf1 $em1 $nf2 $em2]
      bsg_link_select 1 ; return 0
    }
    if {$i % 10 == 0} { puts [format "  soak-both: %d iters x %d words/link clean" $i $chunk] }
  }
  puts [format "SOAK-BOTH OK: %d iters x %d words/link clean" $i $chunk]
  bsg_link_select 1 ; return 1
}

# ============================================================================
# Concurrent both-links test — drives link 1 and link 2 SIMULTANEOUSLY
# (interleaved writes) and checks each link receives EXACTLY its own data.
# This is the test that sequential bsg_link_test_both cannot do: it proves the
# two links are independent (no cross-contamination through the shared AXI
# crossbar / FIFOs) and exercises both datapaths under concurrent load.
# Each link is given a distinct top-byte tag (link1=0x1A.., link2=0x2B..) so a
# word leaking from one link's RX into the other's is detected directly.
# n is capped to the RX FIFO depth so neither RX overflows.
# ============================================================================
proc bsg_link_test_concurrent {axi {n 32}} {
  if {$n > $::BSG_RX_DEPTH} { set n $::BSG_RX_DEPTH }
  set tx1  $::BSG_LINK1(tx_data) ; set rx1 $::BSG_LINK1(rx_data) ; set ct1 $::BSG_LINK1(rx_count)
  set tx2  $::BSG_LINK2(tx_data) ; set rx2 $::BSG_LINK2(rx_data) ; set ct2 $::BSG_LINK2(rx_count)
  puts "=============================================="
  puts [format "  concurrent both-links test (%d words/link, interleaved)" $n]
  puts "=============================================="

  # Drain both RX FIFOs first.
  foreach {rd ct} [list $rx1 $ct1 $rx2 $ct2] {
    set g 0
    while {[bsg_rd32 $axi $ct] > 0 && $g < [expr {$::BSG_RX_DEPTH + 8}]} { bsg_rd32 $axi $rd ; incr g }
  }

  # Build link-tagged patterns.
  set exp1 {} ; set exp2 {}
  for {set i 0} {$i < $n} {incr i} {
    lappend exp1 [expr {(0x1A << 24) | ($i & 0xffffff)}]
    lappend exp2 [expr {(0x2B << 24) | ($i & 0xffffff)}]
  }

  # Interleave writes: TX1[i], TX2[i], TX1[i+1], TX2[i+1], ... so both crossbar
  # master paths are active back-to-back.
  for {set i 0} {$i < $n} {incr i} {
    bsg_wr32 $axi $tx1 [lindex $exp1 $i]
    bsg_wr32 $axi $tx2 [lindex $exp2 $i]
  }

  # Wait for both RX FIFOs to collect n words.
  bsg_wait_count_at $axi $ct1 $n
  bsg_wait_count_at $axi $ct2 $n
  set avail1 [bsg_rd32 $axi $ct1] ; set avail2 [bsg_rd32 $axi $ct2]

  # Read both back.
  set got1 {} ; for {set i 0} {$i < $avail1} {incr i} { lappend got1 [bsg_rd32 $axi $rx1] }
  set got2 {} ; for {set i 0} {$i < $avail2} {incr i} { lappend got2 [bsg_rd32 $axi $rx2] }

  # Verify each link == its own expected; detect cross-contamination by tag.
  set fail 0 ; set cross 0
  foreach {label exp got tag othertag} [list \
        link1 $exp1 $got1 0x1A 0x2B \
        link2 $exp2 $got2 0x2B 0x1A] {
    set ne [llength $exp] ; set ng [llength $got]
    if {$ng != $ne} {
      puts [format "  \[%s\] COUNT mismatch: expected %d, got %d" $label $ne $ng]
      incr fail [expr {abs($ne - $ng)}]
    }
    set lim [expr {$ng < $ne ? $ng : $ne}]
    for {set i 0} {$i < $lim} {incr i} {
      set e [lindex $exp $i] ; set a [lindex $got $i]
      if {$a != $e} {
        incr fail
        set atag [expr {($a >> 24) & 0xff}]
        set leaked [expr {$atag == $othertag ? "  <-- CROSS-CONTAMINATION (data from other link!)" : ""}]
        if {$atag == $othertag} { incr cross }
        if {$fail <= 8} {
          puts [format "  \[%s\] idx %d: exp %08X got %08X%s" $label $i $e $a $leaked]
        }
      }
    }
  }

  set ok [expr {$fail == 0}]
  puts "----------------------------------------------"
  puts [format "CONCURRENT  link1=%d/%d  link2=%d/%d  errors=%d  cross-link=%d  -> %s" \
        $avail1 $n $avail2 $n $fail $cross \
        [expr {$ok ? "BOTH LINKS OK (independent)" : "FAILED"}]]
  if {$cross > 0} {
    puts "  CROSS-CONTAMINATION detected: a link received the other link's data."
    puts "  => crossbar address decode / FIFO routing bug (not a PHY/lane issue)."
  }
  return $ok
}

puts "bsg_link_integrity.tcl loaded. Start with:  set axi \[bsg_link_open\] ; bsg_link_test_all \$axi"
puts "  Two links: bsg_link_select 1|2 (default 1), bsg_link_test_link \$axi 2, bsg_link_test_both \$axi"
puts "  Concurrent (proves independence): bsg_link_test_concurrent \$axi ; soak both: bsg_link_soak_both \$axi"
