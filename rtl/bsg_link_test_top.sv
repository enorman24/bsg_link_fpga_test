// FPGA top-level for BSG link loopback test.
//
// A Xilinx JTAG-to-AXI Master IP (jtag_axi_0, USB-connected) is the sole AXI
// master.  It writes data to the TX FIFO (address 0x4000_0000), which drains
// to bsg_link_ddr_upstream and exits via ribbon-cable pins.  Data received
// through the ribbon cable enters via bsg_link_ddr_downstream, is buffered in
// the RX FIFO (address 0x4001_0000), and can be read back.  The RX status
// register map (address 0x4002_0000) reports empty/full/count so the JTAG
// master knows when received data is ready.
//
// CONSTRAINT: FLIT_WIDTH_P must equal bsg_link_xbar_pkg::AxiDataWidth (32).
//
// Vivado project setup:
//   - Run scripts/create_project.tcl to generate the jtag_axi_0 IP.
//   - The axi_crossbar IP must be present in the Vivado project (already generated).
//
// Simulation:
//   Compile with +define+SIM.  The `ifdef SIM block replaces jtag_axi_0 with
//   direct AXI ports (sim_req_i / sim_resp_o) driven by the testbench.

module bsg_link_test_top
  import bsg_link_xbar_pkg::*;
#(
  // ---- BSG link parameters ----
  parameter int FLIT_WIDTH_P             = 32,   // must equal AxiDataWidth (32)
  parameter int CHANNEL_WIDTH_P          = 16,
  parameter int NUM_CHANNELS_P           = 1,
  parameter int LG_LINK_FIFO_DEPTH_P     = 4,    // bsg_link internal FIFO depth (log2)
  parameter int LG_CREDIT_TO_TOKEN_DEC_P = 3,    // token credit decimation (log2)
  // ---- AXI buffer FIFO depths ----
  parameter int LG_TX_FIFO_DEPTH_P       = 5,    // TX buffer depth (log2)
  parameter int LG_RX_FIFO_DEPTH_P       = 5     // RX buffer depth (log2)
) (
  // ---- Clocks ----
  input  logic                                           core_clk_i,
  input  logic [NUM_CHANNELS_P-1:0]                      token_clk_i,

  input  logic                                           rst_i,

  // ---- BSG Link TX outputs → ribbon cable ----
  output logic [NUM_CHANNELS_P-1:0]                      upstream_io_clk_r_o,
  output logic [NUM_CHANNELS_P-1:0][CHANNEL_WIDTH_P-1:0] upstream_io_data_r_o,
  output logic [NUM_CHANNELS_P-1:0]                      upstream_io_valid_r_o,

  // ---- BSG Link RX inputs ← ribbon cable ----
  input  logic [NUM_CHANNELS_P-1:0]                      downstream_io_clk_i,
  input  logic [NUM_CHANNELS_P-1:0][CHANNEL_WIDTH_P-1:0] downstream_io_data_i,
  input  logic [NUM_CHANNELS_P-1:0]                      downstream_io_valid_i,
  output logic [NUM_CHANNELS_P-1:0]                      downstream_core_token_r_o
`ifdef SIM
  // Simulation AXI master — exposed only when compiled with +define+SIM.
  // In synthesis this block is absent; no dead ports or warnings.
  ,input  slv_req_t  sim_req_i
  ,output slv_resp_t sim_resp_o
`endif
);

  if (FLIT_WIDTH_P != AxiDataWidth)
    $error("FLIT_WIDTH_P (%0d) must equal AxiDataWidth (%0d) from bsg_link_xbar_pkg",
           FLIT_WIDTH_P, AxiDataWidth);

  logic rst_n;
  assign rst_n = ~rst_i;

  // =========================================================================
  // Internal bsg_link reset sequencer (mirrors chip_top.sv lines 189-204)
  //
  // rst_i deasserts → counter increments each core_clk_i cycle:
  //   counts  2- 4 : async_token_reset_int pulses (flushes token ring)
  //   count  16    : io_link_reset_int deasserts
  //   count  32    : core_link_reset_int deasserts
  // =========================================================================
  logic [5:0] reset_cnt_r;
  always_ff @(posedge core_clk_i) begin
    if (rst_i) reset_cnt_r <= '0;
    else if (reset_cnt_r < 6'd63) reset_cnt_r <= reset_cnt_r + 6'd1;
  end

  logic async_token_reset_int;
  assign async_token_reset_int = !rst_i && (reset_cnt_r >= 6'd2) && (reset_cnt_r < 6'd5);

  // Upstream io reset: deasserts at count 16.
  logic io_link_reset_int;
  assign io_link_reset_int = rst_i || (reset_cnt_r < 6'd16);

  // Downstream io reset: deasserts 16 cycles later (count 32).
  // In loopback simulation, downstream_io_clk_i is the forwarded output clock
  // which only starts after io_link_reset_int drops. The async FIFO write
  // pointer needs several clocked-under-reset cycles to initialize to 0;
  // holding this reset for an extra 16 cycles provides that window.
  // On real hardware the chip's upstream clock is always running, so the
  // extra delay is harmless.
  logic downstream_io_link_reset_int;
  assign downstream_io_link_reset_int = rst_i || (reset_cnt_r < 6'd32);

  logic core_link_reset_int;
  assign core_link_reset_int = rst_i || (reset_cnt_r < 6'd32);

  // io_master_clk tied to core_clk_i (saves a port; bsg_link CDC degenerates
  // when both are the same net, matching chip_top.sv's wire io_master_clk = core_clk)

  // =========================================================================
  // AXI master request / response structs — driven by jtag_axi_0 in synthesis
  // or directly by the testbench in simulation.
  // =========================================================================
  slv_req_t  jtag_req_w;
  slv_resp_t jtag_resp_w;

`ifdef SIM
  // Simulation: testbench drives the AXI bus directly.
  assign jtag_req_w = sim_req_i;
  assign sim_resp_o = jtag_resp_w;
`else
  // =========================================================================
  // Xilinx JTAG-to-AXI Master IP (jtag_axi_0)
  //   Module name  : jtag_axi_0  (baked-in at IP generation; no parameters)
  //   AXI ID width : 1 bit  (M_AXI_ID_WIDTH=1 in the generated IP)
  //   Address width: 32 bits
  //   Data width   : 32 bits
  //   USB connection goes through the FPGA JTAG TAP — no extra I/O pins needed.
  // =========================================================================
  localparam int JtagAddrW = AxiAddrWidth;  // 32
  localparam int JtagDataW = AxiDataWidth;  // 32
  localparam int JtagStrbW = JtagDataW / 8; // 4

  // AW channel
  logic [0:0]           jtag_awid_w;
  logic [JtagAddrW-1:0] jtag_awaddr_w;
  logic [7:0]           jtag_awlen_w;
  logic [2:0]           jtag_awsize_w;
  logic [1:0]           jtag_awburst_w;
  logic                 jtag_awlock_w;
  logic [3:0]           jtag_awcache_w;
  logic [2:0]           jtag_awprot_w;
  logic [3:0]           jtag_awqos_w;
  logic                 jtag_awvalid_w;
  logic                 jtag_awready_w;
  // W channel
  logic [JtagDataW-1:0] jtag_wdata_w;
  logic [JtagStrbW-1:0] jtag_wstrb_w;
  logic                 jtag_wlast_w;
  logic                 jtag_wvalid_w;
  logic                 jtag_wready_w;
  // B channel
  logic [0:0]           jtag_bid_w;
  logic [1:0]           jtag_bresp_w;
  logic                 jtag_bvalid_w;
  logic                 jtag_bready_w;
  // AR channel
  logic [0:0]           jtag_arid_w;
  logic [JtagAddrW-1:0] jtag_araddr_w;
  logic [7:0]           jtag_arlen_w;
  logic [2:0]           jtag_arsize_w;
  logic [1:0]           jtag_arburst_w;
  logic                 jtag_arlock_w;
  logic [3:0]           jtag_arcache_w;
  logic [2:0]           jtag_arprot_w;
  logic [3:0]           jtag_arqos_w;
  logic                 jtag_arvalid_w;
  logic                 jtag_arready_w;
  // R channel
  logic [0:0]           jtag_rid_w;
  logic [JtagDataW-1:0] jtag_rdata_w;
  logic [1:0]           jtag_rresp_w;
  logic                 jtag_rlast_w;
  logic                 jtag_rvalid_w;
  logic                 jtag_rready_w;

  jtag_axi_0 i_jtag_axi_0 (
    .aclk          (core_clk_i),
    .aresetn        (rst_n),
    .m_axi_awid     (jtag_awid_w),
    .m_axi_awaddr   (jtag_awaddr_w),
    .m_axi_awlen    (jtag_awlen_w),
    .m_axi_awsize   (jtag_awsize_w),
    .m_axi_awburst  (jtag_awburst_w),
    .m_axi_awlock   (jtag_awlock_w),
    .m_axi_awcache  (jtag_awcache_w),
    .m_axi_awprot   (jtag_awprot_w),
    .m_axi_awqos    (jtag_awqos_w),
    .m_axi_awvalid  (jtag_awvalid_w),
    .m_axi_awready  (jtag_awready_w),
    .m_axi_wdata    (jtag_wdata_w),
    .m_axi_wstrb    (jtag_wstrb_w),
    .m_axi_wlast    (jtag_wlast_w),
    .m_axi_wvalid   (jtag_wvalid_w),
    .m_axi_wready   (jtag_wready_w),
    .m_axi_bid      (jtag_bid_w),
    .m_axi_bresp    (jtag_bresp_w),
    .m_axi_bvalid   (jtag_bvalid_w),
    .m_axi_bready   (jtag_bready_w),
    .m_axi_arid     (jtag_arid_w),
    .m_axi_araddr   (jtag_araddr_w),
    .m_axi_arlen    (jtag_arlen_w),
    .m_axi_arsize   (jtag_arsize_w),
    .m_axi_arburst  (jtag_arburst_w),
    .m_axi_arlock   (jtag_arlock_w),
    .m_axi_arcache  (jtag_arcache_w),
    .m_axi_arprot   (jtag_arprot_w),
    .m_axi_arqos    (jtag_arqos_w),
    .m_axi_arvalid  (jtag_arvalid_w),
    .m_axi_arready  (jtag_arready_w),
    .m_axi_rid      (jtag_rid_w),
    .m_axi_rdata    (jtag_rdata_w),
    .m_axi_rresp    (jtag_rresp_w),
    .m_axi_rlast    (jtag_rlast_w),
    .m_axi_rvalid   (jtag_rvalid_w),
    .m_axi_rready   (jtag_rready_w)
  );

  // =========================================================================
  // Pack flat jtag_axi_0 ports into slv_req_t / slv_resp_t structs.
  // jtag_axi_0 has 1-bit IDs; slv_id_t = logic[0:0], so direct assignment.
  // Fields absent in the IP (region, atop, user) are tied to zero.
  // =========================================================================
  always_comb begin : pack_jtag_req
    jtag_req_w           = '0;
    jtag_req_w.aw.id     = jtag_awid_w;
    jtag_req_w.aw.addr   = jtag_awaddr_w;
    jtag_req_w.aw.len    = jtag_awlen_w;
    jtag_req_w.aw.size   = jtag_awsize_w;
    jtag_req_w.aw.burst  = jtag_awburst_w;
    jtag_req_w.aw.lock   = jtag_awlock_w;
    jtag_req_w.aw.cache  = jtag_awcache_w;
    jtag_req_w.aw.prot   = jtag_awprot_w;
    jtag_req_w.aw.qos    = jtag_awqos_w;
    jtag_req_w.aw.region = '0;
    jtag_req_w.aw.atop   = '0;
    jtag_req_w.aw.user   = '0;
    jtag_req_w.aw_valid  = jtag_awvalid_w;
    jtag_req_w.w.data    = jtag_wdata_w;
    jtag_req_w.w.strb    = jtag_wstrb_w;
    jtag_req_w.w.last    = jtag_wlast_w;
    jtag_req_w.w.user    = '0;
    jtag_req_w.w_valid   = jtag_wvalid_w;
    jtag_req_w.b_ready   = jtag_bready_w;
    jtag_req_w.ar.id     = jtag_arid_w;
    jtag_req_w.ar.addr   = jtag_araddr_w;
    jtag_req_w.ar.len    = jtag_arlen_w;
    jtag_req_w.ar.size   = jtag_arsize_w;
    jtag_req_w.ar.burst  = jtag_arburst_w;
    jtag_req_w.ar.lock   = jtag_arlock_w;
    jtag_req_w.ar.cache  = jtag_arcache_w;
    jtag_req_w.ar.prot   = jtag_arprot_w;
    jtag_req_w.ar.qos    = jtag_arqos_w;
    jtag_req_w.ar.region = '0;
    jtag_req_w.ar.user   = '0;
    jtag_req_w.ar_valid  = jtag_arvalid_w;
    jtag_req_w.r_ready   = jtag_rready_w;
  end

  assign jtag_awready_w = jtag_resp_w.aw_ready;
  assign jtag_wready_w  = jtag_resp_w.w_ready;
  assign jtag_bid_w     = jtag_resp_w.b.id;
  assign jtag_bresp_w   = jtag_resp_w.b.resp;
  assign jtag_bvalid_w  = jtag_resp_w.b_valid;
  assign jtag_arready_w = jtag_resp_w.ar_ready;
  assign jtag_rid_w     = jtag_resp_w.r.id;
  assign jtag_rdata_w   = jtag_resp_w.r.data;
  assign jtag_rresp_w   = jtag_resp_w.r.resp;
  assign jtag_rlast_w   = jtag_resp_w.r.last;
  assign jtag_rvalid_w  = jtag_resp_w.r_valid;
`endif

  // =========================================================================
  // AXI crossbar: 1 slave port (JTAG → S00), 3 master ports
  // (TX FIFO → M00, RX FIFO → M01, RX Status → M02).
  // Vivado AXI Switch IP (axi_crossbar); address map configured at IP-gen time.
  // =========================================================================
  mst_req_t  tx_axi_req_w,  rx_axi_req_w,  sta_axi_req_w;
  mst_resp_t tx_axi_resp_w, rx_axi_resp_w, sta_axi_resp_w;

  // ---- S00 output wires (crossbar → jtag_resp_w) ----
  logic        xbar_s00_aw_ready_w;
  logic        xbar_s00_w_ready_w;
  logic        xbar_s00_b_valid_w;
  logic [0:0]  xbar_s00_b_id_w;
  logic [1:0]  xbar_s00_b_resp_w;
  logic [0:0]  xbar_s00_b_user_w;
  logic        xbar_s00_ar_ready_w;
  logic        xbar_s00_r_valid_w;
  logic [0:0]  xbar_s00_r_id_w;
  logic [31:0] xbar_s00_r_data_w;
  logic [1:0]  xbar_s00_r_resp_w;
  logic        xbar_s00_r_last_w;
  logic [0:0]  xbar_s00_r_user_w;

  always_comb begin : pack_s00_resp
    jtag_resp_w          = '0;
    jtag_resp_w.aw_ready = xbar_s00_aw_ready_w;
    jtag_resp_w.w_ready  = xbar_s00_w_ready_w;
    jtag_resp_w.b_valid  = xbar_s00_b_valid_w;
    jtag_resp_w.b.id     = xbar_s00_b_id_w;
    jtag_resp_w.b.resp   = xbar_s00_b_resp_w;
    jtag_resp_w.b.user   = xbar_s00_b_user_w;
    jtag_resp_w.ar_ready = xbar_s00_ar_ready_w;
    jtag_resp_w.r_valid  = xbar_s00_r_valid_w;
    jtag_resp_w.r.id     = xbar_s00_r_id_w;
    jtag_resp_w.r.data   = xbar_s00_r_data_w;
    jtag_resp_w.r.resp   = xbar_s00_r_resp_w;
    jtag_resp_w.r.last   = xbar_s00_r_last_w;
    jtag_resp_w.r.user   = xbar_s00_r_user_w;
  end

  // ---- M00 wires: TX FIFO (0x4000_0000 – 0x4000_FFFF) ----
  logic        xbar_m00_aw_valid_w;  logic [0:0]  xbar_m00_aw_id_w;
  logic [31:0] xbar_m00_aw_addr_w;  logic [7:0]  xbar_m00_aw_len_w;
  logic [2:0]  xbar_m00_aw_size_w;  logic [1:0]  xbar_m00_aw_burst_w;
  logic [0:0]  xbar_m00_aw_lock_w;  logic [3:0]  xbar_m00_aw_cache_w;
  logic [2:0]  xbar_m00_aw_prot_w;  logic [3:0]  xbar_m00_aw_qos_w;
  logic [0:0]  xbar_m00_aw_user_w;
  logic        xbar_m00_w_valid_w;   logic [31:0] xbar_m00_w_data_w;
  logic [3:0]  xbar_m00_w_strb_w;   logic        xbar_m00_w_last_w;
  logic [0:0]  xbar_m00_w_user_w;   logic        xbar_m00_b_ready_w;
  logic        xbar_m00_ar_valid_w;  logic [0:0]  xbar_m00_ar_id_w;
  logic [31:0] xbar_m00_ar_addr_w;  logic [7:0]  xbar_m00_ar_len_w;
  logic [2:0]  xbar_m00_ar_size_w;  logic [1:0]  xbar_m00_ar_burst_w;
  logic [0:0]  xbar_m00_ar_lock_w;  logic [3:0]  xbar_m00_ar_cache_w;
  logic [2:0]  xbar_m00_ar_prot_w;  logic [3:0]  xbar_m00_ar_qos_w;
  logic [0:0]  xbar_m00_ar_user_w;  logic        xbar_m00_r_ready_w;
  logic        xbar_m00_aw_ready_w;  logic        xbar_m00_w_ready_w;
  logic        xbar_m00_b_valid_w;   logic [0:0]  xbar_m00_b_id_w;
  logic [1:0]  xbar_m00_b_resp_w;   logic [0:0]  xbar_m00_b_user_w;
  logic        xbar_m00_ar_ready_w;  logic        xbar_m00_r_valid_w;
  logic [0:0]  xbar_m00_r_id_w;     logic [31:0] xbar_m00_r_data_w;
  logic [1:0]  xbar_m00_r_resp_w;   logic        xbar_m00_r_last_w;
  logic [0:0]  xbar_m00_r_user_w;

  always_comb begin : pack_m00_req
    tx_axi_req_w          = '0;
    tx_axi_req_w.aw_valid = xbar_m00_aw_valid_w;
    tx_axi_req_w.aw.id    = xbar_m00_aw_id_w;
    tx_axi_req_w.aw.addr  = xbar_m00_aw_addr_w;
    tx_axi_req_w.aw.len   = xbar_m00_aw_len_w;
    tx_axi_req_w.aw.size  = xbar_m00_aw_size_w;
    tx_axi_req_w.aw.burst = xbar_m00_aw_burst_w;
    tx_axi_req_w.aw.lock  = xbar_m00_aw_lock_w;
    tx_axi_req_w.aw.cache = xbar_m00_aw_cache_w;
    tx_axi_req_w.aw.prot  = xbar_m00_aw_prot_w;
    tx_axi_req_w.aw.qos   = xbar_m00_aw_qos_w;
    tx_axi_req_w.aw.user  = xbar_m00_aw_user_w;
    tx_axi_req_w.w_valid  = xbar_m00_w_valid_w;
    tx_axi_req_w.w.data   = xbar_m00_w_data_w;
    tx_axi_req_w.w.strb   = xbar_m00_w_strb_w;
    tx_axi_req_w.w.last   = xbar_m00_w_last_w;
    tx_axi_req_w.w.user   = xbar_m00_w_user_w;
    tx_axi_req_w.b_ready  = xbar_m00_b_ready_w;
    tx_axi_req_w.ar_valid = xbar_m00_ar_valid_w;
    tx_axi_req_w.ar.id    = xbar_m00_ar_id_w;
    tx_axi_req_w.ar.addr  = xbar_m00_ar_addr_w;
    tx_axi_req_w.ar.len   = xbar_m00_ar_len_w;
    tx_axi_req_w.ar.size  = xbar_m00_ar_size_w;
    tx_axi_req_w.ar.burst = xbar_m00_ar_burst_w;
    tx_axi_req_w.ar.lock  = xbar_m00_ar_lock_w;
    tx_axi_req_w.ar.cache = xbar_m00_ar_cache_w;
    tx_axi_req_w.ar.prot  = xbar_m00_ar_prot_w;
    tx_axi_req_w.ar.qos   = xbar_m00_ar_qos_w;
    tx_axi_req_w.ar.user  = xbar_m00_ar_user_w;
    tx_axi_req_w.r_ready  = xbar_m00_r_ready_w;
  end

  assign xbar_m00_aw_ready_w = tx_axi_resp_w.aw_ready;
  assign xbar_m00_w_ready_w  = tx_axi_resp_w.w_ready;
  assign xbar_m00_b_valid_w  = tx_axi_resp_w.b_valid;
  assign xbar_m00_b_id_w     = tx_axi_resp_w.b.id;
  assign xbar_m00_b_resp_w   = tx_axi_resp_w.b.resp;
  assign xbar_m00_b_user_w   = tx_axi_resp_w.b.user;
  assign xbar_m00_ar_ready_w = tx_axi_resp_w.ar_ready;
  assign xbar_m00_r_valid_w  = tx_axi_resp_w.r_valid;
  assign xbar_m00_r_id_w     = tx_axi_resp_w.r.id;
  assign xbar_m00_r_data_w   = tx_axi_resp_w.r.data;
  assign xbar_m00_r_resp_w   = tx_axi_resp_w.r.resp;
  assign xbar_m00_r_last_w   = tx_axi_resp_w.r.last;
  assign xbar_m00_r_user_w   = tx_axi_resp_w.r.user;

  // ---- M01 wires: RX FIFO (0x4001_0000 – 0x4001_FFFF) ----
  logic        xbar_m01_aw_valid_w;  logic [0:0]  xbar_m01_aw_id_w;
  logic [31:0] xbar_m01_aw_addr_w;  logic [7:0]  xbar_m01_aw_len_w;
  logic [2:0]  xbar_m01_aw_size_w;  logic [1:0]  xbar_m01_aw_burst_w;
  logic [0:0]  xbar_m01_aw_lock_w;  logic [3:0]  xbar_m01_aw_cache_w;
  logic [2:0]  xbar_m01_aw_prot_w;  logic [3:0]  xbar_m01_aw_qos_w;
  logic [0:0]  xbar_m01_aw_user_w;
  logic        xbar_m01_w_valid_w;   logic [31:0] xbar_m01_w_data_w;
  logic [3:0]  xbar_m01_w_strb_w;   logic        xbar_m01_w_last_w;
  logic [0:0]  xbar_m01_w_user_w;   logic        xbar_m01_b_ready_w;
  logic        xbar_m01_ar_valid_w;  logic [0:0]  xbar_m01_ar_id_w;
  logic [31:0] xbar_m01_ar_addr_w;  logic [7:0]  xbar_m01_ar_len_w;
  logic [2:0]  xbar_m01_ar_size_w;  logic [1:0]  xbar_m01_ar_burst_w;
  logic [0:0]  xbar_m01_ar_lock_w;  logic [3:0]  xbar_m01_ar_cache_w;
  logic [2:0]  xbar_m01_ar_prot_w;  logic [3:0]  xbar_m01_ar_qos_w;
  logic [0:0]  xbar_m01_ar_user_w;  logic        xbar_m01_r_ready_w;
  logic        xbar_m01_aw_ready_w;  logic        xbar_m01_w_ready_w;
  logic        xbar_m01_b_valid_w;   logic [0:0]  xbar_m01_b_id_w;
  logic [1:0]  xbar_m01_b_resp_w;   logic [0:0]  xbar_m01_b_user_w;
  logic        xbar_m01_ar_ready_w;  logic        xbar_m01_r_valid_w;
  logic [0:0]  xbar_m01_r_id_w;     logic [31:0] xbar_m01_r_data_w;
  logic [1:0]  xbar_m01_r_resp_w;   logic        xbar_m01_r_last_w;
  logic [0:0]  xbar_m01_r_user_w;

  always_comb begin : pack_m01_req
    rx_axi_req_w          = '0;
    rx_axi_req_w.aw_valid = xbar_m01_aw_valid_w;
    rx_axi_req_w.aw.id    = xbar_m01_aw_id_w;
    rx_axi_req_w.aw.addr  = xbar_m01_aw_addr_w;
    rx_axi_req_w.aw.len   = xbar_m01_aw_len_w;
    rx_axi_req_w.aw.size  = xbar_m01_aw_size_w;
    rx_axi_req_w.aw.burst = xbar_m01_aw_burst_w;
    rx_axi_req_w.aw.lock  = xbar_m01_aw_lock_w;
    rx_axi_req_w.aw.cache = xbar_m01_aw_cache_w;
    rx_axi_req_w.aw.prot  = xbar_m01_aw_prot_w;
    rx_axi_req_w.aw.qos   = xbar_m01_aw_qos_w;
    rx_axi_req_w.aw.user  = xbar_m01_aw_user_w;
    rx_axi_req_w.w_valid  = xbar_m01_w_valid_w;
    rx_axi_req_w.w.data   = xbar_m01_w_data_w;
    rx_axi_req_w.w.strb   = xbar_m01_w_strb_w;
    rx_axi_req_w.w.last   = xbar_m01_w_last_w;
    rx_axi_req_w.w.user   = xbar_m01_w_user_w;
    rx_axi_req_w.b_ready  = xbar_m01_b_ready_w;
    rx_axi_req_w.ar_valid = xbar_m01_ar_valid_w;
    rx_axi_req_w.ar.id    = xbar_m01_ar_id_w;
    rx_axi_req_w.ar.addr  = xbar_m01_ar_addr_w;
    rx_axi_req_w.ar.len   = xbar_m01_ar_len_w;
    rx_axi_req_w.ar.size  = xbar_m01_ar_size_w;
    rx_axi_req_w.ar.burst = xbar_m01_ar_burst_w;
    rx_axi_req_w.ar.lock  = xbar_m01_ar_lock_w;
    rx_axi_req_w.ar.cache = xbar_m01_ar_cache_w;
    rx_axi_req_w.ar.prot  = xbar_m01_ar_prot_w;
    rx_axi_req_w.ar.qos   = xbar_m01_ar_qos_w;
    rx_axi_req_w.ar.user  = xbar_m01_ar_user_w;
    rx_axi_req_w.r_ready  = xbar_m01_r_ready_w;
  end

  assign xbar_m01_aw_ready_w = rx_axi_resp_w.aw_ready;
  assign xbar_m01_w_ready_w  = rx_axi_resp_w.w_ready;
  assign xbar_m01_b_valid_w  = rx_axi_resp_w.b_valid;
  assign xbar_m01_b_id_w     = rx_axi_resp_w.b.id;
  assign xbar_m01_b_resp_w   = rx_axi_resp_w.b.resp;
  assign xbar_m01_b_user_w   = rx_axi_resp_w.b.user;
  assign xbar_m01_ar_ready_w = rx_axi_resp_w.ar_ready;
  assign xbar_m01_r_valid_w  = rx_axi_resp_w.r_valid;
  assign xbar_m01_r_id_w     = rx_axi_resp_w.r.id;
  assign xbar_m01_r_data_w   = rx_axi_resp_w.r.data;
  assign xbar_m01_r_resp_w   = rx_axi_resp_w.r.resp;
  assign xbar_m01_r_last_w   = rx_axi_resp_w.r.last;
  assign xbar_m01_r_user_w   = rx_axi_resp_w.r.user;

  // ---- M02 wires: RX Status (0x4002_0000 – 0x4002_FFFF) ----
  logic        xbar_m02_aw_valid_w;  logic [0:0]  xbar_m02_aw_id_w;
  logic [31:0] xbar_m02_aw_addr_w;  logic [7:0]  xbar_m02_aw_len_w;
  logic [2:0]  xbar_m02_aw_size_w;  logic [1:0]  xbar_m02_aw_burst_w;
  logic [0:0]  xbar_m02_aw_lock_w;  logic [3:0]  xbar_m02_aw_cache_w;
  logic [2:0]  xbar_m02_aw_prot_w;  logic [3:0]  xbar_m02_aw_qos_w;
  logic [0:0]  xbar_m02_aw_user_w;
  logic        xbar_m02_w_valid_w;   logic [31:0] xbar_m02_w_data_w;
  logic [3:0]  xbar_m02_w_strb_w;   logic        xbar_m02_w_last_w;
  logic [0:0]  xbar_m02_w_user_w;   logic        xbar_m02_b_ready_w;
  logic        xbar_m02_ar_valid_w;  logic [0:0]  xbar_m02_ar_id_w;
  logic [31:0] xbar_m02_ar_addr_w;  logic [7:0]  xbar_m02_ar_len_w;
  logic [2:0]  xbar_m02_ar_size_w;  logic [1:0]  xbar_m02_ar_burst_w;
  logic [0:0]  xbar_m02_ar_lock_w;  logic [3:0]  xbar_m02_ar_cache_w;
  logic [2:0]  xbar_m02_ar_prot_w;  logic [3:0]  xbar_m02_ar_qos_w;
  logic [0:0]  xbar_m02_ar_user_w;  logic        xbar_m02_r_ready_w;
  logic        xbar_m02_aw_ready_w;  logic        xbar_m02_w_ready_w;
  logic        xbar_m02_b_valid_w;   logic [0:0]  xbar_m02_b_id_w;
  logic [1:0]  xbar_m02_b_resp_w;   logic [0:0]  xbar_m02_b_user_w;
  logic        xbar_m02_ar_ready_w;  logic        xbar_m02_r_valid_w;
  logic [0:0]  xbar_m02_r_id_w;     logic [31:0] xbar_m02_r_data_w;
  logic [1:0]  xbar_m02_r_resp_w;   logic        xbar_m02_r_last_w;
  logic [0:0]  xbar_m02_r_user_w;

  always_comb begin : pack_m02_req
    sta_axi_req_w          = '0;
    sta_axi_req_w.aw_valid = xbar_m02_aw_valid_w;
    sta_axi_req_w.aw.id    = xbar_m02_aw_id_w;
    sta_axi_req_w.aw.addr  = xbar_m02_aw_addr_w;
    sta_axi_req_w.aw.len   = xbar_m02_aw_len_w;
    sta_axi_req_w.aw.size  = xbar_m02_aw_size_w;
    sta_axi_req_w.aw.burst = xbar_m02_aw_burst_w;
    sta_axi_req_w.aw.lock  = xbar_m02_aw_lock_w;
    sta_axi_req_w.aw.cache = xbar_m02_aw_cache_w;
    sta_axi_req_w.aw.prot  = xbar_m02_aw_prot_w;
    sta_axi_req_w.aw.qos   = xbar_m02_aw_qos_w;
    sta_axi_req_w.aw.user  = xbar_m02_aw_user_w;
    sta_axi_req_w.w_valid  = xbar_m02_w_valid_w;
    sta_axi_req_w.w.data   = xbar_m02_w_data_w;
    sta_axi_req_w.w.strb   = xbar_m02_w_strb_w;
    sta_axi_req_w.w.last   = xbar_m02_w_last_w;
    sta_axi_req_w.w.user   = xbar_m02_w_user_w;
    sta_axi_req_w.b_ready  = xbar_m02_b_ready_w;
    sta_axi_req_w.ar_valid = xbar_m02_ar_valid_w;
    sta_axi_req_w.ar.id    = xbar_m02_ar_id_w;
    sta_axi_req_w.ar.addr  = xbar_m02_ar_addr_w;
    sta_axi_req_w.ar.len   = xbar_m02_ar_len_w;
    sta_axi_req_w.ar.size  = xbar_m02_ar_size_w;
    sta_axi_req_w.ar.burst = xbar_m02_ar_burst_w;
    sta_axi_req_w.ar.lock  = xbar_m02_ar_lock_w;
    sta_axi_req_w.ar.cache = xbar_m02_ar_cache_w;
    sta_axi_req_w.ar.prot  = xbar_m02_ar_prot_w;
    sta_axi_req_w.ar.qos   = xbar_m02_ar_qos_w;
    sta_axi_req_w.ar.user  = xbar_m02_ar_user_w;
    sta_axi_req_w.r_ready  = xbar_m02_r_ready_w;
  end

  assign xbar_m02_aw_ready_w = sta_axi_resp_w.aw_ready;
  assign xbar_m02_w_ready_w  = sta_axi_resp_w.w_ready;
  assign xbar_m02_b_valid_w  = sta_axi_resp_w.b_valid;
  assign xbar_m02_b_id_w     = sta_axi_resp_w.b.id;
  assign xbar_m02_b_resp_w   = sta_axi_resp_w.b.resp;
  assign xbar_m02_b_user_w   = sta_axi_resp_w.b.user;
  assign xbar_m02_ar_ready_w = sta_axi_resp_w.ar_ready;
  assign xbar_m02_r_valid_w  = sta_axi_resp_w.r_valid;
  assign xbar_m02_r_id_w     = sta_axi_resp_w.r.id;
  assign xbar_m02_r_data_w   = sta_axi_resp_w.r.data;
  assign xbar_m02_r_resp_w   = sta_axi_resp_w.r.resp;
  assign xbar_m02_r_last_w   = sta_axi_resp_w.r.last;
  assign xbar_m02_r_user_w   = sta_axi_resp_w.r.user;

  // ---- Vivado AXI Switch IP ----
  axi_crossbar i_xbar (
    .aclk            (core_clk_i),
    .aresetn         (rst_n),
    .aresetn_out     (),
    .pc_asserted     (),
    .pc_status       (),
    // S00: JTAG AXI master
    .s00_axi_awid    (jtag_req_w.aw.id),
    .s00_axi_awaddr  (jtag_req_w.aw.addr),
    .s00_axi_awlen   (jtag_req_w.aw.len),
    .s00_axi_awsize  (jtag_req_w.aw.size),
    .s00_axi_awburst (jtag_req_w.aw.burst),
    .s00_axi_awlock  (jtag_req_w.aw.lock),
    .s00_axi_awcache (jtag_req_w.aw.cache),
    .s00_axi_awprot  (jtag_req_w.aw.prot),
    .s00_axi_awqos   (jtag_req_w.aw.qos),
    .s00_axi_awuser  (jtag_req_w.aw.user),
    .s00_axi_awvalid (jtag_req_w.aw_valid),
    .s00_axi_awready (xbar_s00_aw_ready_w),
    .s00_axi_wdata   (jtag_req_w.w.data),
    .s00_axi_wstrb   (jtag_req_w.w.strb),
    .s00_axi_wlast   (jtag_req_w.w.last),
    .s00_axi_wuser   (jtag_req_w.w.user),
    .s00_axi_wvalid  (jtag_req_w.w_valid),
    .s00_axi_wready  (xbar_s00_w_ready_w),
    .s00_axi_bid     (xbar_s00_b_id_w),
    .s00_axi_bresp   (xbar_s00_b_resp_w),
    .s00_axi_buser   (xbar_s00_b_user_w),
    .s00_axi_bvalid  (xbar_s00_b_valid_w),
    .s00_axi_bready  (jtag_req_w.b_ready),
    .s00_axi_arid    (jtag_req_w.ar.id),
    .s00_axi_araddr  (jtag_req_w.ar.addr),
    .s00_axi_arlen   (jtag_req_w.ar.len),
    .s00_axi_arsize  (jtag_req_w.ar.size),
    .s00_axi_arburst (jtag_req_w.ar.burst),
    .s00_axi_arlock  (jtag_req_w.ar.lock),
    .s00_axi_arcache (jtag_req_w.ar.cache),
    .s00_axi_arprot  (jtag_req_w.ar.prot),
    .s00_axi_arqos   (jtag_req_w.ar.qos),
    .s00_axi_aruser  (jtag_req_w.ar.user),
    .s00_axi_arvalid (jtag_req_w.ar_valid),
    .s00_axi_arready (xbar_s00_ar_ready_w),
    .s00_axi_rid     (xbar_s00_r_id_w),
    .s00_axi_rdata   (xbar_s00_r_data_w),
    .s00_axi_rresp   (xbar_s00_r_resp_w),
    .s00_axi_rlast   (xbar_s00_r_last_w),
    .s00_axi_ruser   (xbar_s00_r_user_w),
    .s00_axi_rvalid  (xbar_s00_r_valid_w),
    .s00_axi_rready  (jtag_req_w.r_ready),
    // M00: TX FIFO
    .m00_axi_awid    (xbar_m00_aw_id_w),
    .m00_axi_awaddr  (xbar_m00_aw_addr_w),
    .m00_axi_awlen   (xbar_m00_aw_len_w),
    .m00_axi_awsize  (xbar_m00_aw_size_w),
    .m00_axi_awburst (xbar_m00_aw_burst_w),
    .m00_axi_awlock  (xbar_m00_aw_lock_w),
    .m00_axi_awcache (xbar_m00_aw_cache_w),
    .m00_axi_awprot  (xbar_m00_aw_prot_w),
    .m00_axi_awqos   (xbar_m00_aw_qos_w),
    .m00_axi_awuser  (xbar_m00_aw_user_w),
    .m00_axi_awvalid (xbar_m00_aw_valid_w),
    .m00_axi_awready (xbar_m00_aw_ready_w),
    .m00_axi_wdata   (xbar_m00_w_data_w),
    .m00_axi_wstrb   (xbar_m00_w_strb_w),
    .m00_axi_wlast   (xbar_m00_w_last_w),
    .m00_axi_wuser   (xbar_m00_w_user_w),
    .m00_axi_wvalid  (xbar_m00_w_valid_w),
    .m00_axi_wready  (xbar_m00_w_ready_w),
    .m00_axi_bid     (xbar_m00_b_id_w),
    .m00_axi_bresp   (xbar_m00_b_resp_w),
    .m00_axi_buser   (xbar_m00_b_user_w),
    .m00_axi_bvalid  (xbar_m00_b_valid_w),
    .m00_axi_bready  (xbar_m00_b_ready_w),
    .m00_axi_arid    (xbar_m00_ar_id_w),
    .m00_axi_araddr  (xbar_m00_ar_addr_w),
    .m00_axi_arlen   (xbar_m00_ar_len_w),
    .m00_axi_arsize  (xbar_m00_ar_size_w),
    .m00_axi_arburst (xbar_m00_ar_burst_w),
    .m00_axi_arlock  (xbar_m00_ar_lock_w),
    .m00_axi_arcache (xbar_m00_ar_cache_w),
    .m00_axi_arprot  (xbar_m00_ar_prot_w),
    .m00_axi_arqos   (xbar_m00_ar_qos_w),
    .m00_axi_aruser  (xbar_m00_ar_user_w),
    .m00_axi_arvalid (xbar_m00_ar_valid_w),
    .m00_axi_arready (xbar_m00_ar_ready_w),
    .m00_axi_rid     (xbar_m00_r_id_w),
    .m00_axi_rdata   (xbar_m00_r_data_w),
    .m00_axi_rresp   (xbar_m00_r_resp_w),
    .m00_axi_rlast   (xbar_m00_r_last_w),
    .m00_axi_ruser   (xbar_m00_r_user_w),
    .m00_axi_rvalid  (xbar_m00_r_valid_w),
    .m00_axi_rready  (xbar_m00_r_ready_w),
    // M01: RX FIFO
    .m01_axi_awid    (xbar_m01_aw_id_w),
    .m01_axi_awaddr  (xbar_m01_aw_addr_w),
    .m01_axi_awlen   (xbar_m01_aw_len_w),
    .m01_axi_awsize  (xbar_m01_aw_size_w),
    .m01_axi_awburst (xbar_m01_aw_burst_w),
    .m01_axi_awlock  (xbar_m01_aw_lock_w),
    .m01_axi_awcache (xbar_m01_aw_cache_w),
    .m01_axi_awprot  (xbar_m01_aw_prot_w),
    .m01_axi_awqos   (xbar_m01_aw_qos_w),
    .m01_axi_awuser  (xbar_m01_aw_user_w),
    .m01_axi_awvalid (xbar_m01_aw_valid_w),
    .m01_axi_awready (xbar_m01_aw_ready_w),
    .m01_axi_wdata   (xbar_m01_w_data_w),
    .m01_axi_wstrb   (xbar_m01_w_strb_w),
    .m01_axi_wlast   (xbar_m01_w_last_w),
    .m01_axi_wuser   (xbar_m01_w_user_w),
    .m01_axi_wvalid  (xbar_m01_w_valid_w),
    .m01_axi_wready  (xbar_m01_w_ready_w),
    .m01_axi_bid     (xbar_m01_b_id_w),
    .m01_axi_bresp   (xbar_m01_b_resp_w),
    .m01_axi_buser   (xbar_m01_b_user_w),
    .m01_axi_bvalid  (xbar_m01_b_valid_w),
    .m01_axi_bready  (xbar_m01_b_ready_w),
    .m01_axi_arid    (xbar_m01_ar_id_w),
    .m01_axi_araddr  (xbar_m01_ar_addr_w),
    .m01_axi_arlen   (xbar_m01_ar_len_w),
    .m01_axi_arsize  (xbar_m01_ar_size_w),
    .m01_axi_arburst (xbar_m01_ar_burst_w),
    .m01_axi_arlock  (xbar_m01_ar_lock_w),
    .m01_axi_arcache (xbar_m01_ar_cache_w),
    .m01_axi_arprot  (xbar_m01_ar_prot_w),
    .m01_axi_arqos   (xbar_m01_ar_qos_w),
    .m01_axi_aruser  (xbar_m01_ar_user_w),
    .m01_axi_arvalid (xbar_m01_ar_valid_w),
    .m01_axi_arready (xbar_m01_ar_ready_w),
    .m01_axi_rid     (xbar_m01_r_id_w),
    .m01_axi_rdata   (xbar_m01_r_data_w),
    .m01_axi_rresp   (xbar_m01_r_resp_w),
    .m01_axi_rlast   (xbar_m01_r_last_w),
    .m01_axi_ruser   (xbar_m01_r_user_w),
    .m01_axi_rvalid  (xbar_m01_r_valid_w),
    .m01_axi_rready  (xbar_m01_r_ready_w),
    // M02: RX Status
    .m02_axi_awid    (xbar_m02_aw_id_w),
    .m02_axi_awaddr  (xbar_m02_aw_addr_w),
    .m02_axi_awlen   (xbar_m02_aw_len_w),
    .m02_axi_awsize  (xbar_m02_aw_size_w),
    .m02_axi_awburst (xbar_m02_aw_burst_w),
    .m02_axi_awlock  (xbar_m02_aw_lock_w),
    .m02_axi_awcache (xbar_m02_aw_cache_w),
    .m02_axi_awprot  (xbar_m02_aw_prot_w),
    .m02_axi_awqos   (xbar_m02_aw_qos_w),
    .m02_axi_awuser  (xbar_m02_aw_user_w),
    .m02_axi_awvalid (xbar_m02_aw_valid_w),
    .m02_axi_awready (xbar_m02_aw_ready_w),
    .m02_axi_wdata   (xbar_m02_w_data_w),
    .m02_axi_wstrb   (xbar_m02_w_strb_w),
    .m02_axi_wlast   (xbar_m02_w_last_w),
    .m02_axi_wuser   (xbar_m02_w_user_w),
    .m02_axi_wvalid  (xbar_m02_w_valid_w),
    .m02_axi_wready  (xbar_m02_w_ready_w),
    .m02_axi_bid     (xbar_m02_b_id_w),
    .m02_axi_bresp   (xbar_m02_b_resp_w),
    .m02_axi_buser   (xbar_m02_b_user_w),
    .m02_axi_bvalid  (xbar_m02_b_valid_w),
    .m02_axi_bready  (xbar_m02_b_ready_w),
    .m02_axi_arid    (xbar_m02_ar_id_w),
    .m02_axi_araddr  (xbar_m02_ar_addr_w),
    .m02_axi_arlen   (xbar_m02_ar_len_w),
    .m02_axi_arsize  (xbar_m02_ar_size_w),
    .m02_axi_arburst (xbar_m02_ar_burst_w),
    .m02_axi_arlock  (xbar_m02_ar_lock_w),
    .m02_axi_arcache (xbar_m02_ar_cache_w),
    .m02_axi_arprot  (xbar_m02_ar_prot_w),
    .m02_axi_arqos   (xbar_m02_ar_qos_w),
    .m02_axi_aruser  (xbar_m02_ar_user_w),
    .m02_axi_arvalid (xbar_m02_ar_valid_w),
    .m02_axi_arready (xbar_m02_ar_ready_w),
    .m02_axi_rid     (xbar_m02_r_id_w),
    .m02_axi_rdata   (xbar_m02_r_data_w),
    .m02_axi_rresp   (xbar_m02_r_resp_w),
    .m02_axi_rlast   (xbar_m02_r_last_w),
    .m02_axi_ruser   (xbar_m02_r_user_w),
    .m02_axi_rvalid  (xbar_m02_r_valid_w),
    .m02_axi_rready  (xbar_m02_r_ready_w)
  );

  // =========================================================================
  // TX FIFO: AXI4 write slave → bsg_link TX core side (valid/data/ready)
  // =========================================================================
  logic                        tx_valid_w;
  logic [FLIT_WIDTH_P-1:0]     tx_data_w;
  logic                        tx_ready_w;
  logic                        tx_fifo_full_w;
  logic                        tx_fifo_empty_w;
  logic [LG_TX_FIFO_DEPTH_P:0] tx_fifo_count_w;

  bsg_link_axi_tx_fifo #(
    .axi_req_t      (mst_req_t),
    .axi_resp_t     (mst_resp_t),
    .LG_FIFO_DEPTH_P(LG_TX_FIFO_DEPTH_P)
  ) i_tx_fifo (
    .clk_i          (core_clk_i),
    .rst_i          (rst_i),
    .axi_req_i      (tx_axi_req_w),
    .axi_resp_o     (tx_axi_resp_w),
    .tx_valid_o     (tx_valid_w),
    .tx_data_o      (tx_data_w),
    .tx_ready_i     (tx_ready_w),
    .tx_fifo_full_o (tx_fifo_full_w),
    .tx_fifo_empty_o(tx_fifo_empty_w),
    .tx_fifo_count_o(tx_fifo_count_w)
  );

  // =========================================================================
  // RX FIFO: bsg_link RX core side (valid/data/yumi) → AXI4 read slave
  // =========================================================================
  logic                        rx_valid_w;
  logic [FLIT_WIDTH_P-1:0]     rx_data_w;
  logic                        rx_yumi_w;
  logic                        rx_fifo_full_w;
  logic                        rx_fifo_empty_w;
  logic [LG_RX_FIFO_DEPTH_P:0] rx_fifo_count_w;

  bsg_link_axi_rx_fifo #(
    .axi_req_t      (mst_req_t),
    .axi_resp_t     (mst_resp_t),
    .LG_FIFO_DEPTH_P(LG_RX_FIFO_DEPTH_P)
  ) i_rx_fifo (
    .clk_i          (core_clk_i),
    .rst_i          (rst_i),
    .axi_req_i      (rx_axi_req_w),
    .axi_resp_o     (rx_axi_resp_w),
    .rx_valid_i     (rx_valid_w),
    .rx_data_i      (rx_data_w),
    .rx_yumi_o      (rx_yumi_w),
    .rx_fifo_full_o (rx_fifo_full_w),
    .rx_fifo_empty_o(rx_fifo_empty_w),
    .rx_fifo_count_o(rx_fifo_count_w)
  );

  // =========================================================================
  // RX Status registers: read RX FIFO empty/full/count; write CTRL to flush
  // =========================================================================
  logic rx_fifo_flush_w;

  bsg_link_axi_rx_status #(
    .COUNT_WIDTH_P(LG_RX_FIFO_DEPTH_P + 1)
  ) i_rx_status (
    .clk_i           (core_clk_i),
    .rst_i           (rst_i),
    .axi_req_i       (sta_axi_req_w),
    .axi_resp_o      (sta_axi_resp_w),
    .rx_fifo_empty_i (rx_fifo_empty_w),
    .rx_fifo_full_i  (rx_fifo_full_w),
    .rx_fifo_count_i (rx_fifo_count_w),
    .rx_fifo_flush_o (rx_fifo_flush_w)
  );

  // rx_fifo_flush_w reserved for future use (add flush logic to i_rx_fifo if needed).

  // =========================================================================
  // bsg_link_ddr_upstream – TX, sends data over ribbon cable
  // =========================================================================
  bsg_link_ddr_upstream #(
    .width_p                         (FLIT_WIDTH_P),
    .channel_width_p                 (CHANNEL_WIDTH_P),
    .num_channels_p                  (NUM_CHANNELS_P),
    .lg_fifo_depth_p                 (LG_LINK_FIFO_DEPTH_P),
    .lg_credit_to_token_decimation_p (LG_CREDIT_TO_TOKEN_DEC_P)
  ) link_tx_i (
    .core_clk_i         (core_clk_i),
    .core_link_reset_i  (core_link_reset_int),
    .core_data_i        (tx_data_w),
    .core_valid_i       (tx_valid_w),
    .core_ready_o       (tx_ready_w),
    .io_clk_i           (core_clk_i),
    .io_link_reset_i    (io_link_reset_int),
    .async_token_reset_i(async_token_reset_int),
    .io_clk_r_o         (upstream_io_clk_r_o),
    .io_data_r_o        (upstream_io_data_r_o),
    .io_valid_r_o       (upstream_io_valid_r_o),
    .token_clk_i        (token_clk_i)
  );

  // =========================================================================
  // bsg_link_ddr_downstream – RX, receives data from ribbon cable
  // =========================================================================
  bsg_link_ddr_downstream #(
    .width_p                         (FLIT_WIDTH_P),
    .channel_width_p                 (CHANNEL_WIDTH_P),
    .num_channels_p                  (NUM_CHANNELS_P),
    .lg_fifo_depth_p                 (LG_LINK_FIFO_DEPTH_P),
    .lg_credit_to_token_decimation_p (LG_CREDIT_TO_TOKEN_DEC_P)
  ) link_rx_i (
    .core_clk_i       (core_clk_i),
    .core_link_reset_i(core_link_reset_int),
    .io_link_reset_i  (downstream_io_link_reset_int),
    .core_data_o      (rx_data_w),
    .core_valid_o     (rx_valid_w),
    .core_yumi_i      (rx_yumi_w),
    .io_clk_i         (downstream_io_clk_i),
    .io_data_i        (downstream_io_data_i),
    .io_valid_i       (downstream_io_valid_i),
    .core_token_r_o   (downstream_core_token_r_o)
  );

endmodule : bsg_link_test_top
