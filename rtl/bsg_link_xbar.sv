// AXI4 crossbar for the BSG link FPGA test.
// 1 slave port (JTAG AXI master), 3 master ports (TX FIFO, RX FIFO, RX Status).
// Wraps axi_xbar from the pulp-platform AXI library.
// rst_i is active-high; inverted to active-low for axi_xbar.

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module bsg_link_xbar
  import bsg_link_xbar_pkg::*;
(
  input  logic      clk_i,
  input  logic      rst_i,

  // Slave port: JTAG AXI master
  input  slv_req_t  jtag_req_i,
  output slv_resp_t jtag_resp_o,

  // Master port 0: TX FIFO (address range TX_BASE–TX_END)
  output mst_req_t  tx_req_o,
  input  mst_resp_t tx_resp_i,

  // Master port 1: RX FIFO (address range RX_BASE–RX_END)
  output mst_req_t  rx_req_o,
  input  mst_resp_t rx_resp_i,

  // Master port 2: RX status registers (address range STA_BASE–STA_END)
  output mst_req_t  sta_req_o,
  input  mst_resp_t sta_resp_i
);

  logic rst_n;
  assign rst_n = ~rst_i;

  slv_req_t  [NoSlvPorts-1:0] slv_req;
  slv_resp_t [NoSlvPorts-1:0] slv_resp;
  assign slv_req[0]  = jtag_req_i;
  assign jtag_resp_o = slv_resp[0];

  mst_req_t  [NoMstPorts-1:0] mst_req;
  mst_resp_t [NoMstPorts-1:0] mst_resp;
  assign tx_req_o              = mst_req[IDX_TX_FIFO];
  assign rx_req_o              = mst_req[IDX_RX_FIFO];
  assign sta_req_o             = mst_req[IDX_RX_STA];
  assign mst_resp[IDX_TX_FIFO] = tx_resp_i;
  assign mst_resp[IDX_RX_FIFO] = rx_resp_i;
  assign mst_resp[IDX_RX_STA]  = sta_resp_i;

  localparam xbar_rule_32_t [NoAddrRules-1:0] AddrMap = '{
    '{idx: IDX_TX_FIFO, start_addr: TX_BASE,  end_addr: TX_END},
    '{idx: IDX_RX_FIFO, start_addr: RX_BASE,  end_addr: RX_END},
    '{idx: IDX_RX_STA,  start_addr: STA_BASE, end_addr: STA_END}
  };

  logic [NoSlvPorts-1:0]                        en_default_mst;
  logic [NoSlvPorts-1:0][$clog2(NoMstPorts)-1:0] default_mst;
  assign en_default_mst = '0;
  assign default_mst    = '0;

  axi_xbar #(
    .Cfg          (XbarCfg),
    .ATOPs        (1'b0),
    .slv_aw_chan_t(slv_aw_t),
    .mst_aw_chan_t(mst_aw_t),
    .w_chan_t     (w_t),
    .slv_b_chan_t (slv_b_t),
    .mst_b_chan_t (mst_b_t),
    .slv_ar_chan_t(slv_ar_t),
    .mst_ar_chan_t(mst_ar_t),
    .slv_r_chan_t (slv_r_t),
    .mst_r_chan_t (mst_r_t),
    .slv_req_t    (slv_req_t),
    .slv_resp_t   (slv_resp_t),
    .mst_req_t    (mst_req_t),
    .mst_resp_t   (mst_resp_t),
    .rule_t       (xbar_rule_32_t)
  ) i_xbar (
    .clk_i                (clk_i),
    .rst_ni               (rst_n),
    .test_i               (1'b0),
    .slv_ports_req_i      (slv_req),
    .slv_ports_resp_o     (slv_resp),
    .mst_ports_req_o      (mst_req),
    .mst_ports_resp_i     (mst_resp),
    .addr_map_i           (AddrMap),
    .en_default_mst_port_i(en_default_mst),
    .default_mst_port_i   (default_mst)
  );

endmodule : bsg_link_xbar
