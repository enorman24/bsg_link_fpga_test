// AXI4 types for the BSG link FPGA test.
// Topology: 1 slave port (JTAG AXI master → S00), 6 master ports.
//   Link 1: TX1 FIFO → M00, RX1 FIFO → M01, RX1 Status → M02.
//   Link 2: TX2 FIFO → M03, RX2 FIFO → M04, RX2 Status → M05.
// (Link 2 is the independent reverse-direction bsg_link on the other F2G
//  headers; same RTL/IP topology, separate address space.)
// Bus widths: 32-bit address, 32-bit data, 1-bit ID, 1-bit user.
//
// Struct field order matches the PULP AXI4+ATOP typedef macros (typedef.svh)
// so that existing field-access expressions in bsg_link_test_top.sv and the
// three slave modules compile unchanged.

package bsg_link_xbar_pkg;

  // ---- Bus parameters ----
  localparam int unsigned AxiAddrWidth = 32;
  localparam int unsigned AxiDataWidth = 32;
  localparam int unsigned AxiStrbWidth = AxiDataWidth / 8;
  localparam int unsigned AxiUserWidth = 1;

  // ---- Crossbar topology ----
  localparam int unsigned NoSlvPorts = 1;   // one JTAG master  → S00
  localparam int unsigned NoMstPorts = 6;   // per link: TX FIFO, RX FIFO, RX Status (x2 links)

  // ---- ID widths ----
  // jtag_axi_0 generates 1-bit IDs.  With a single slave port the crossbar
  // prepends 0 bits, so master-port ID width equals slave-port ID width.
  localparam int unsigned SlvIdWidth = 1;
  localparam int unsigned MstIdWidth = 1;

  // ---- Master-port indices ----
  // Link 1
  localparam int unsigned IDX_TX_FIFO  = 0;
  localparam int unsigned IDX_RX_FIFO  = 1;
  localparam int unsigned IDX_RX_STA   = 2;
  // Link 2 (reverse-direction link)
  localparam int unsigned IDX_TX2_FIFO = 3;
  localparam int unsigned IDX_RX2_FIFO = 4;
  localparam int unsigned IDX_RX2_STA  = 5;

  // ---- Address map (end_addr is exclusive, matching addr_decode convention) ----
  // Link 1
  localparam logic [AxiAddrWidth-1:0] TX_BASE   = 32'h4000_0000;
  localparam logic [AxiAddrWidth-1:0] TX_END    = 32'h4001_0000;
  localparam logic [AxiAddrWidth-1:0] RX_BASE   = 32'h4001_0000;
  localparam logic [AxiAddrWidth-1:0] RX_END    = 32'h4002_0000;
  localparam logic [AxiAddrWidth-1:0] STA_BASE  = 32'h4002_0000;
  localparam logic [AxiAddrWidth-1:0] STA_END   = 32'h4003_0000;
  // Link 2
  localparam logic [AxiAddrWidth-1:0] TX2_BASE  = 32'h4003_0000;
  localparam logic [AxiAddrWidth-1:0] TX2_END   = 32'h4004_0000;
  localparam logic [AxiAddrWidth-1:0] RX2_BASE  = 32'h4004_0000;
  localparam logic [AxiAddrWidth-1:0] RX2_END   = 32'h4005_0000;
  localparam logic [AxiAddrWidth-1:0] STA2_BASE = 32'h4005_0000;
  localparam logic [AxiAddrWidth-1:0] STA2_END  = 32'h4006_0000;

  // ---- AXI response codes ----
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_EXOKAY = 2'b01;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;

  // ---- Scalar types ----
  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiStrbWidth-1:0] axi_strb_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;
  typedef logic [SlvIdWidth-1:0]   slv_id_t;
  typedef logic [MstIdWidth-1:0]   mst_id_t;

  // =========================================================================
  // AXI4 channel structs — explicit definitions replacing AXI_TYPEDEF_* macros.
  // =========================================================================

  // W channel (shared between slave-port and master-port request types)
  typedef struct packed {
    axi_data_t data;
    axi_strb_t strb;
    logic      last;
    axi_user_t user;
  } w_t;

  // ---- Slave-port types (S00 / JTAG side, SlvIdWidth IDs) ----

  typedef struct packed {
    slv_id_t   id;
    axi_addr_t addr;
    logic [7:0] len;
    logic [2:0] size;
    logic [1:0] burst;
    logic       lock;
    logic [3:0] cache;
    logic [2:0] prot;
    logic [3:0] qos;
    logic [3:0] region;
    logic [5:0] atop;   // AXI4+ATOP field; tied to '0 from JTAG
    axi_user_t  user;
  } slv_aw_t;

  typedef struct packed {
    slv_id_t    id;
    logic [1:0] resp;
    axi_user_t  user;
  } slv_b_t;

  typedef struct packed {
    slv_id_t   id;
    axi_addr_t addr;
    logic [7:0] len;
    logic [2:0] size;
    logic [1:0] burst;
    logic       lock;
    logic [3:0] cache;
    logic [2:0] prot;
    logic [3:0] qos;
    logic [3:0] region;
    axi_user_t  user;
  } slv_ar_t;

  typedef struct packed {
    slv_id_t    id;
    axi_data_t  data;
    logic [1:0] resp;
    logic       last;
    axi_user_t  user;
  } slv_r_t;

  typedef struct packed {
    slv_aw_t aw;
    logic    aw_valid;
    w_t      w;
    logic    w_valid;
    logic    b_ready;
    slv_ar_t ar;
    logic    ar_valid;
    logic    r_ready;
  } slv_req_t;

  typedef struct packed {
    logic    aw_ready;
    logic    ar_ready;
    logic    w_ready;
    logic    b_valid;
    slv_b_t  b;
    logic    r_valid;
    slv_r_t  r;
  } slv_resp_t;

  // ---- Master-port types (M00/M01/M02, MstIdWidth IDs) ----

  typedef struct packed {
    mst_id_t   id;
    axi_addr_t addr;
    logic [7:0] len;
    logic [2:0] size;
    logic [1:0] burst;
    logic       lock;
    logic [3:0] cache;
    logic [2:0] prot;
    logic [3:0] qos;
    logic [3:0] region;
    logic [5:0] atop;
    axi_user_t  user;
  } mst_aw_t;

  typedef struct packed {
    mst_id_t    id;
    logic [1:0] resp;
    axi_user_t  user;
  } mst_b_t;

  typedef struct packed {
    mst_id_t   id;
    axi_addr_t addr;
    logic [7:0] len;
    logic [2:0] size;
    logic [1:0] burst;
    logic       lock;
    logic [3:0] cache;
    logic [2:0] prot;
    logic [3:0] qos;
    logic [3:0] region;
    axi_user_t  user;
  } mst_ar_t;

  typedef struct packed {
    mst_id_t    id;
    axi_data_t  data;
    logic [1:0] resp;
    logic       last;
    axi_user_t  user;
  } mst_r_t;

  typedef struct packed {
    mst_aw_t aw;
    logic    aw_valid;
    w_t      w;
    logic    w_valid;
    logic    b_ready;
    mst_ar_t ar;
    logic    ar_valid;
    logic    r_ready;
  } mst_req_t;

  typedef struct packed {
    logic    aw_ready;
    logic    ar_ready;
    logic    w_ready;
    logic    b_valid;
    mst_b_t  b;
    logic    r_valid;
    mst_r_t  r;
  } mst_resp_t;

endpackage : bsg_link_xbar_pkg
