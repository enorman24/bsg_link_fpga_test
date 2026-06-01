// AXI4 register-map slave for RX FIFO status and control.
//
// Register map (byte-addressed, 4-byte stride):
//   0x00  STATUS  RO  [1]=full, [0]=empty
//   0x04  COUNT   RO  [COUNT_WIDTH_P-1:0] = number of entries in RX FIFO
//   0x08  CTRL    WO  [0]=rx_fifo_flush (write 1 to pulse flush for 1 cycle)
//
// Only single-beat transactions are expected (ARLEN/AWLEN=0); larger bursts
// return SLVERR.

module bsg_link_axi_rx_status
  import bsg_link_xbar_pkg::*;
#(
  parameter int COUNT_WIDTH_P = 6
) (
  input  logic      clk_i,
  input  logic      rst_i,

  // AXI4 slave port
  input  mst_req_t  axi_req_i,
  output mst_resp_t axi_resp_o,

  // RX FIFO status inputs
  input  logic                        rx_fifo_empty_i,
  input  logic                        rx_fifo_full_i,
  input  logic [COUNT_WIDTH_P-1:0]    rx_fifo_count_i,

  // RX FIFO control output
  output logic                        rx_fifo_flush_o
);

  // ---- Register decode helpers ----
  localparam logic [3:0] OFF_STATUS = 4'h0;
  localparam logic [3:0] OFF_COUNT  = 4'h4;
  localparam logic [3:0] OFF_CTRL   = 4'h8;

  // ---- Read state machine ----
  typedef enum logic {R_IDLE, R_RESP} r_state_e;
  r_state_e r_state_r;

  logic [$bits(axi_req_i.ar.id)-1:0] ar_id_r;
  logic [AxiDataWidth-1:0]           r_data_r;
  logic                              r_slverr_r;

  wire ar_fire = axi_req_i.ar_valid && axi_resp_o.ar_ready;
  wire r_fire  = axi_resp_o.r_valid  && axi_req_i.r_ready;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      r_state_r  <= R_IDLE;
      ar_id_r    <= '0;
      r_data_r   <= '0;
      r_slverr_r <= 1'b0;
    end else begin
      case (r_state_r)
        R_IDLE: if (ar_fire) begin
          ar_id_r    <= axi_req_i.ar.id;
          r_slverr_r <= (axi_req_i.ar.len != '0);  // only single-beat
          unique case (axi_req_i.ar.addr[3:0])
            OFF_STATUS: r_data_r <= {{(AxiDataWidth-2){1'b0}},
                                     rx_fifo_full_i, rx_fifo_empty_i};
            OFF_COUNT:  r_data_r <= {{(AxiDataWidth-COUNT_WIDTH_P){1'b0}},
                                     rx_fifo_count_i};
            default:    r_data_r <= '0;
          endcase
          r_state_r <= R_RESP;
        end
        R_RESP: if (r_fire) r_state_r <= R_IDLE;
        default: r_state_r <= R_IDLE;
      endcase
    end
  end

  // ---- Write state machine ----
  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} w_state_e;
  w_state_e w_state_r;

  logic [$bits(axi_req_i.aw.id)-1:0] aw_id_r;
  logic [3:0]                         aw_off_r;
  logic                               w_slverr_r;

  wire aw_fire = axi_req_i.aw_valid && axi_resp_o.aw_ready;
  wire w_fire  = axi_req_i.w_valid  && axi_resp_o.w_ready;
  wire b_fire  = axi_resp_o.b_valid  && axi_req_i.b_ready;

  // Flush pulse: asserted for exactly one clock when CTRL[0] is written
  logic flush_r;
  assign rx_fifo_flush_o = flush_r;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      w_state_r  <= W_IDLE;
      aw_id_r    <= '0;
      aw_off_r   <= '0;
      w_slverr_r <= 1'b0;
      flush_r    <= 1'b0;
    end else begin
      flush_r <= 1'b0;  // default: no flush
      case (w_state_r)
        W_IDLE: if (aw_fire) begin
          aw_id_r    <= axi_req_i.aw.id;
          aw_off_r   <= axi_req_i.aw.addr[3:0];
          w_slverr_r <= (axi_req_i.aw.len != '0);
          // If W also valid in same cycle, handle immediately
          if (axi_req_i.w_valid && axi_req_i.w.last) begin
            if ((axi_req_i.aw.addr[3:0] == OFF_CTRL) && axi_req_i.w.data[0])
              flush_r <= 1'b1;
            w_state_r <= W_RESP;
          end else begin
            w_state_r <= W_DATA;
          end
        end
        W_DATA: if (w_fire) begin
          if ((aw_off_r == OFF_CTRL) && axi_req_i.w.data[0])
            flush_r <= 1'b1;
          w_state_r <= W_RESP;
        end
        W_RESP: if (b_fire) w_state_r <= W_IDLE;
        default: w_state_r <= W_IDLE;
      endcase
    end
  end

  // ---- Combinational AXI outputs ----
  always_comb begin
    axi_resp_o          = '0;
    // AR: accept when read SM idle
    axi_resp_o.ar_ready = (r_state_r == R_IDLE);
    // R: valid when read SM in RESP state
    axi_resp_o.r_valid  = (r_state_r == R_RESP);
    axi_resp_o.r.id     = ar_id_r;
    axi_resp_o.r.data   = r_data_r;
    axi_resp_o.r.resp   = r_slverr_r ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
    axi_resp_o.r.last   = 1'b1;
    // AW: accept when write SM idle
    axi_resp_o.aw_ready = (w_state_r == W_IDLE);
    // W: accept when write SM in DATA state, or in IDLE when AW fires simultaneously
    axi_resp_o.w_ready  = (w_state_r == W_DATA) ||
                          ((w_state_r == W_IDLE) && axi_req_i.aw_valid);
    // B: valid when write SM in RESP state
    axi_resp_o.b_valid  = (w_state_r == W_RESP);
    axi_resp_o.b.id     = aw_id_r;
    axi_resp_o.b.resp   = w_slverr_r ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
  end

endmodule : bsg_link_axi_rx_status
