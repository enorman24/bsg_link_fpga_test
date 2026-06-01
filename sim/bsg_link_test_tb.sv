`timescale 1ps/1ps

module bsg_link_test_tb ();

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int FLIT_W   = 32;
  localparam int CH_W     = 16;  // 16-bit channel — matches Mini_Dice bsg_link_wrapper
  localparam int NUM_CH   = 1;
  localparam int LG_LINK  = 4;  // log2 of link FIFO depth  → 16 entries
  localparam int LG_CRED  = 3;  // log2 of credit-to-token decrement
  localparam int LG_TXDEP = 5;  // log2 of TX FIFO depth    → 32 entries
  localparam int LG_RXDEP = 5;  // log2 of RX FIFO depth    → 32 entries

  localparam int N           = 8;    // words per test round
  localparam int POLL_MAX    = 500;  // max STATUS poll iterations before timeout

  localparam int CORE_HALF = 4;  // core clock half-period (ps) → 8 ps period

  // =========================================================================
  // Clock generation
  // io_master_clk is tied to core_clk (matches chip_top: wire io_master_clk = core_clk)
  // =========================================================================
  logic core_clk = 1'b1;

  always #CORE_HALF core_clk = ~core_clk;

  // =========================================================================
  // DUT signals
  // =========================================================================
  // Single external reset input, matching chip_top's hard_reset pad.
  // A 6-bit counter (identical to chip_top.sv lines 189-204) generates the
  // four staged internal resets.  The one loopback-specific adjustment:
  // dn_io_rst drops 16 cycles *after* up_io_rst, because in this sim
  // link_clk_w (the downstream's w_clk) comes from the loopback and only
  // runs after up_io_rst drops — the downstream async FIFO needs those
  // extra cycles clocked-under-reset to clear its write pointer.
  // On real silicon the downstream clock comes from the FPGA (always on),
  // so chip_top can release both IO link resets at the same cycle.
  logic rst;

  reg [5:0] reset_cnt_r = '0;  // reg + initializer matches chip_top.sv style; avoids always_ff driver conflict
  always @(posedge core_clk)
    if (rst) reset_cnt_r <= '0;
    else if (reset_cnt_r < 6'd63) reset_cnt_r <= reset_cnt_r + 6'd1;

  wire async_tok_rst_w = !rst && (reset_cnt_r >= 6'd2)  && (reset_cnt_r < 6'd5);  // pulse cycles 2-4
  wire up_io_rst_w     = rst  || (reset_cnt_r < 6'd16);  // upstream IO link reset, drops at cycle 16
  wire dn_io_rst_w     = rst  || (reset_cnt_r < 6'd32);  // downstream: 16 extra cycles for loopback
  wire core_rst_w      = rst  || (reset_cnt_r < 6'd48);  // core released last

  // Ribbon-cable loopback wires
  logic [NUM_CH-1:0]              link_clk_w;
  logic [NUM_CH-1:0][CH_W-1:0]   link_data_w;
  logic [NUM_CH-1:0]              link_valid_w;
  logic [NUM_CH-1:0]              downstream_token_w;

  // Simulation AXI master bus
  import bsg_link_xbar_pkg::*;
  import axi_pkg::*;
  slv_req_t  sim_req;
  slv_resp_t sim_resp;

  // =========================================================================
  // DUT instantiation
  // =========================================================================
  bsg_link_test_top #(
    .FLIT_WIDTH_P            (FLIT_W),
    .CHANNEL_WIDTH_P         (CH_W),
    .NUM_CHANNELS_P          (NUM_CH),
    .LG_LINK_FIFO_DEPTH_P    (LG_LINK),
    .LG_CREDIT_TO_TOKEN_DEC_P(LG_CRED),
    .LG_TX_FIFO_DEPTH_P      (LG_TXDEP),
    .LG_RX_FIFO_DEPTH_P      (LG_RXDEP)
  ) dut (
    .core_clk_i                (core_clk),
    .token_clk_i               (downstream_token_w),

    // DUT owns the bsg_link reset sequencer internally; drive raw reset here.
    // core_rst_w (TB-local) still provides the @(negedge core_rst_w) timing
    // reference — it fires at cycle 52, after DUT's core_link_reset_int
    // deasserts at cycle 36.
    .rst_i                     (rst),

    // Ribbon-cable loopback: TX output → RX input
    .upstream_io_clk_r_o       (link_clk_w),
    .upstream_io_data_r_o      (link_data_w),
    .upstream_io_valid_r_o     (link_valid_w),
    .downstream_io_clk_i       (link_clk_w),
    .downstream_io_data_i      (link_data_w),
    .downstream_io_valid_i     (link_valid_w),
    .downstream_core_token_r_o (downstream_token_w),

    // Simulation AXI master
    .sim_req_i                 (sim_req),
    .sim_resp_o                (sim_resp)
  );

  // =========================================================================
  // Register address map (as seen by the simulation AXI master)
  //   0x4000_0000  TX_DATA  — write-only: push one word into the upstream TX FIFO
  //   0x4001_0000  RX_DATA  — read-only:  pop one word from the downstream RX FIFO
  //   0x4002_0000  STATUS   — read-only:  bit[0] = RX FIFO empty flag
  //   0x4002_0004  RX_COUNT — read-only:  number of words currently in the RX FIFO
  // =========================================================================

  // =========================================================================
  // AXI4 master tasks
  //
  // The bsg_link_axi_tx_fifo SM only asserts w_ready after aw fires (BURST
  // state), so axi_write issues AW first, waits for aw_ready, then W.
  // Both tasks check the AXI response code and call $error on anything other
  // than RESP_OKAY.
  // Each `@(posedge core_clk); #1;` pattern waits for the clock edge then
  // steps 1 ps forward so driven signals land after the edge, not on it.
  // =========================================================================

  // Single-beat AXI4 write.
  task automatic axi_write(input logic [31:0] addr, input logic [31:0] data);
    // -- AW phase --
    @(posedge core_clk); #1;
    sim_req          = '0;
    sim_req.aw.addr  = addr;
    sim_req.aw.id    = '0;
    sim_req.aw.len   = 8'h00;   // 1 beat
    sim_req.aw.size  = 3'b010;  // 4 bytes
    sim_req.aw.burst = 2'b01;   // INCR
    sim_req.aw_valid = 1'b1;
    forever begin
      @(posedge core_clk);
      if (sim_resp.aw_ready) break;
    end
    #1;
    sim_req.aw_valid = 1'b0;

    // -- W phase --
    sim_req.w.data  = data;
    sim_req.w.strb  = 4'hF;
    sim_req.w.last  = 1'b1;
    sim_req.w_valid = 1'b1;
    forever begin
      @(posedge core_clk);
      if (sim_resp.w_ready) break;
    end
    #1;
    sim_req.w_valid = 1'b0;

    // -- B phase --
    sim_req.b_ready = 1'b1;
    forever begin
      @(posedge core_clk);
      if (sim_resp.b_valid) break;
    end
    if (sim_resp.b.resp !== RESP_OKAY)
      $error("axi_write addr=0x%08h: bad b.resp=%0d", addr, sim_resp.b.resp);
    #1;
    sim_req.b_ready = 1'b0;
    sim_req = '0;
  endtask

  // Single-beat AXI4 read.
  task automatic axi_read(input logic [31:0] addr, output logic [31:0] data);
    // -- AR phase --
    @(posedge core_clk); #1;
    sim_req          = '0;
    sim_req.ar.addr  = addr;
    sim_req.ar.id    = '0;
    sim_req.ar.len   = 8'h00;
    sim_req.ar.size  = 3'b010;
    sim_req.ar.burst = 2'b01;
    sim_req.ar_valid = 1'b1;
    forever begin
      @(posedge core_clk);
      if (sim_resp.ar_ready) break;
    end
    #1;
    sim_req.ar_valid = 1'b0;

    // -- R phase --
    sim_req.r_ready = 1'b1;
    forever begin
      @(posedge core_clk);
      if (sim_resp.r_valid) break;
    end
    data = sim_resp.r.data;
    if (sim_resp.r.resp !== RESP_OKAY)
      $error("axi_read addr=0x%08h: bad r.resp=%0d", addr, sim_resp.r.resp);
    #1;
    sim_req.r_ready = 1'b0;
    sim_req = '0;
  endtask

  // Poll COUNT register (0x4002_0004) until it reaches min_count.
  // Errors out after POLL_MAX iterations so the simulation never hangs.
  task automatic wait_for_count(input int min_count, output logic [31:0] count);
    count = '0;
    for (int tries = 0; tries < POLL_MAX; tries++) begin
      axi_read(32'h4002_0004, count);
      if (count >= min_count) return;
      #(CORE_HALF * 4);  // 16 ps = 2 full core clock cycles between polls
    end
    $error("TIMEOUT: RX count only reached %0d of %0d after %0d polls",
           count, min_count, POLL_MAX);
    $finish;
  endtask

  // Send N words, wait for them to loopback, read them back and verify.
  // tag is printed in pass/fail messages to distinguish rounds.
  task automatic run_round(input string tag, input logic [31:0] pattern [N]);
    logic [31:0] got [N];
    logic [31:0] cnt;
    int          fails;

    $display("[%s] writing %0d words...", tag, N);
    for (int i = 0; i < N; i++)
      axi_write(32'h4000_0000, pattern[i]);  // TX_DATA

    $display("[%s] waiting for loopback...", tag);
    wait_for_count(N, cnt);
    $display("[%s] RX count = %0d", tag, cnt);

    $display("[%s] reading back...", tag);
    for (int i = 0; i < N; i++)
      axi_read(32'h4001_0000, got[i]);   // RX_DATA

    // Verify data matches
    fails = 0;
    for (int i = 0; i < N; i++) begin
      if (got[i] !== pattern[i]) begin
        $error("[%s] MISMATCH [%0d]: expected 0x%08h, got 0x%08h",
               tag, i, pattern[i], got[i]);
        fails++;
      end
    end

    // RX FIFO should now be empty
    axi_read(32'h4002_0004, cnt);  // RX_COUNT
    if (cnt !== 0)
      $error("[%s] RX FIFO not empty after drain: count=%0d", tag, cnt);

    // STATUS register bit[0] = empty flag
    axi_read(32'h4002_0000, cnt);  // STATUS
    if (cnt[0] !== 1'b1)
      $error("[%s] STATUS: empty flag not set after drain (STATUS=0x%08h)", tag, cnt);

    if (fails == 0)
      $display("[%s] PASS — all %0d words match.\n", tag, N);
    else
      $display("[%s] FAIL — %0d mismatches.\n", tag, fails);
  endtask

  // =========================================================================
  // Stimulus
  // =========================================================================
  logic [31:0] pattern_a [N];
  logic [31:0] pattern_b [N];

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, bsg_link_test_tb, "+struct", "+mda");

    
    $display("=== bsg_link_test_tb start ===");

    sim_req = '0;
    rst     = 1'b1;

    // Round A: walking increment; round B: bit-inverted
    for (int i = 0; i < N; i++) begin
      pattern_a[i] = 32'hA000_0000 + i;
      pattern_b[i] = ~pattern_a[i];
    end

    // -----------------------------------------------------------------------
    // Assert rst for a few cycles then release. The counter takes over:
    //   cycles  2- 4 : async_tok_rst pulses (flushes token ring)
    //   cycle  16    : up_io_rst drops  → link_clk_w starts
    //   cycle  32    : dn_io_rst drops  → downstream FIFO has had 16 clocked-
    //                                     reset cycles, write pointer is clean
    //   cycle  48    : core_rst drops   → AXI state machines come up
    // -----------------------------------------------------------------------
    repeat(4) @(posedge core_clk); #1;
    rst = 1'b0;
    @(negedge core_rst_w);  // wait for the counter to finish all stages

    // -----------------------------------------------------------------------
    // Two independent loopback rounds
    // -----------------------------------------------------------------------
    run_round("round-A", pattern_a);
    run_round("round-B", pattern_b);

    $display("=== all rounds passed ===");
    $finish;
  end

  // Safety timeout
  initial begin
    #10_000_000;
    $error("TIMEOUT — simulation did not finish in time.");
    $finish;
  end

endmodule : bsg_link_test_tb
