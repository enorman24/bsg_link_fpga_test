// AXI4 types and crossbar configuration for the BSG link FPGA test.
// Topology: 1 slave port (JTAG AXI master), 3 master ports (TX FIFO, RX FIFO, RX Status).
// Bus widths: 32-bit address, 32-bit data, 4-bit ID, 1-bit user.
// To change widths, edit the localparams and re-elaborate.

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

package bsg_link_xbar_pkg;

  import axi_pkg::*;

  // ---- Bus parameters ----
  localparam int unsigned AxiAddrWidth = 32;
  localparam int unsigned AxiDataWidth = 32;
  localparam int unsigned AxiStrbWidth = AxiDataWidth / 8;
  localparam int unsigned AxiUserWidth = 1;

  // ---- Crossbar topology ----
  localparam int unsigned NoSlvPorts  = 1;   // one JTAG master
  localparam int unsigned NoMstPorts  = 3;   // TX FIFO, RX FIFO, RX Status
  localparam int unsigned NoAddrRules = 3;

  // ---- ID widths ----
  // jtag_axi_0 generates 1-bit IDs (M_AXI_ID_WIDTH=1 in the generated IP).
  // With NoSlvPorts=1, $clog2(1)=0, so MstIdWidth equals SlvIdWidth.
  localparam int unsigned SlvIdWidth = 1;
  localparam int unsigned MstIdWidth = SlvIdWidth + $clog2(NoSlvPorts == 1 ? 1 : NoSlvPorts);

  // ---- Master-port indices ----
  localparam int unsigned IDX_TX_FIFO = 0;
  localparam int unsigned IDX_RX_FIFO = 1;
  localparam int unsigned IDX_RX_STA  = 2;

  // ---- Address map ----
  localparam logic [AxiAddrWidth-1:0] TX_BASE  = 32'h4000_0000;
  localparam logic [AxiAddrWidth-1:0] TX_END   = 32'h4001_0000;
  localparam logic [AxiAddrWidth-1:0] RX_BASE  = 32'h4001_0000;
  localparam logic [AxiAddrWidth-1:0] RX_END   = 32'h4002_0000;
  localparam logic [AxiAddrWidth-1:0] STA_BASE = 32'h4002_0000;
  localparam logic [AxiAddrWidth-1:0] STA_END  = 32'h4003_0000;

  // ---- Crossbar configuration ----
  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
      NoSlvPorts:         NoSlvPorts,
      NoMstPorts:         NoMstPorts,
      MaxMstTrans:        4,
      MaxSlvTrans:        4,
      FallThrough:        1'b0,
      LatencyMode:        axi_pkg::NO_LATENCY,
      PipelineStages:     0,
      AxiIdWidthSlvPorts: SlvIdWidth,
      AxiIdUsedSlvPorts:  SlvIdWidth,
      UniqueIds:          1'b0,
      AxiAddrWidth:       AxiAddrWidth,
      AxiDataWidth:       AxiDataWidth,
      NoAddrRules:        NoAddrRules
  };

  // ---- Scalar types ----
  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiStrbWidth-1:0] axi_strb_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;
  typedef logic [SlvIdWidth-1:0]   slv_id_t;
  typedef logic [MstIdWidth-1:0]   mst_id_t;

  // 32-bit address rule for addr_decode
  typedef struct packed {
    int unsigned             idx;
    logic [AxiAddrWidth-1:0] start_addr;
    logic [AxiAddrWidth-1:0] end_addr;
  } xbar_rule_32_t;

  // ---- Slave-port AXI types (JTAG master → xbar, SlvIdWidth IDs) ----
  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_t, axi_addr_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_t, axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_t, axi_addr_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(slv_r_t, axi_data_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(slv_req_t, slv_aw_t, w_t, slv_ar_t)
  `AXI_TYPEDEF_RESP_T(slv_resp_t, slv_b_t, slv_r_t)

  // ---- Master-port AXI types (xbar → slaves, MstIdWidth IDs) ----
  `AXI_TYPEDEF_AW_CHAN_T(mst_aw_t, axi_addr_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T(mst_b_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(mst_ar_t, axi_addr_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T(mst_r_t, axi_data_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T(mst_req_t, mst_aw_t, w_t, mst_ar_t)
  `AXI_TYPEDEF_RESP_T(mst_resp_t, mst_b_t, mst_r_t)

endpackage : bsg_link_xbar_pkg
