// AXI4 read-slave backed by a synchronous FIFO.
// Data from the bsg_link RX core side (valid/data/yumi) is pushed into the FIFO.
// AXI read transactions pop entries; RVALID stalls when the FIFO is empty.
// Write transactions return DECERR.
// rx_yumi_o deasserts when the FIFO is full, providing backpressure to bsg_link.

module bsg_link_axi_rx_fifo
  import bsg_link_xbar_pkg::*;
#(
  parameter type axi_req_t       = mst_req_t,
  parameter type axi_resp_t      = mst_resp_t,
  parameter int  LG_FIFO_DEPTH_P = 5
) (
  input  logic      clk_i,
  input  logic      rst_i,

  // AXI4 slave port
  input  axi_req_t  axi_req_i,
  output axi_resp_t axi_resp_o,

  // bsg_link RX core-side
  input  logic                    rx_valid_i,
  input  logic [AxiDataWidth-1:0] rx_data_i,
  output logic                    rx_yumi_o,

  // FIFO status
  output logic                    rx_fifo_full_o,
  output logic                    rx_fifo_empty_o,
  output logic [LG_FIFO_DEPTH_P:0] rx_fifo_count_o
);

  localparam int Depth = 1 << LG_FIFO_DEPTH_P;

  // ---- Synchronous FIFO ----
  logic [AxiDataWidth-1:0]  mem [0:Depth-1];
  logic [LG_FIFO_DEPTH_P:0] wr_ptr_r, rd_ptr_r;

  wire full_w  = (wr_ptr_r[LG_FIFO_DEPTH_P] != rd_ptr_r[LG_FIFO_DEPTH_P]) &&
                 (wr_ptr_r[LG_FIFO_DEPTH_P-1:0] == rd_ptr_r[LG_FIFO_DEPTH_P-1:0]);
  wire empty_w = (wr_ptr_r == rd_ptr_r);

  assign rx_fifo_full_o  = full_w;
  assign rx_fifo_empty_o = empty_w;
  assign rx_fifo_count_o = wr_ptr_r - rd_ptr_r;

  // Accept data from bsg_link RX when FIFO has space
  assign rx_yumi_o = rx_valid_i && !full_w;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      wr_ptr_r <= '0;
    end else if (rx_yumi_o) begin
      mem[wr_ptr_r[LG_FIFO_DEPTH_P-1:0]] <= rx_data_i;
      wr_ptr_r <= wr_ptr_r + 1'b1;
    end
  end

  // ---- AXI read state machine ----
  typedef enum logic {R_IDLE, R_BURST} r_state_e;
  r_state_e r_state_r;

  logic [$bits(axi_req_i.ar.id)-1:0] ar_id_r;
  logic [7:0] r_beats_rem_r;   // remaining R beats in current burst

  wire ar_fire = axi_req_i.ar_valid && axi_resp_o.ar_ready;
  wire r_fire  = axi_resp_o.r_valid  && axi_req_i.r_ready;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      r_state_r    <= R_IDLE;
      ar_id_r      <= '0;
      r_beats_rem_r <= '0;
    end else begin
      case (r_state_r)
        R_IDLE: if (ar_fire) begin
          ar_id_r       <= axi_req_i.ar.id;
          r_beats_rem_r <= axi_req_i.ar.len;  // arlen is beats-1
          r_state_r     <= R_BURST;
        end
        R_BURST: if (r_fire) begin
          if (r_beats_rem_r == '0) begin
            r_state_r <= R_IDLE;
          end else begin
            r_beats_rem_r <= r_beats_rem_r - 1'b1;
          end
        end
        default: r_state_r <= R_IDLE;
      endcase
    end
  end

  // Pop FIFO when an R beat is accepted
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      rd_ptr_r <= '0;
    end else if (r_fire) begin
      rd_ptr_r <= rd_ptr_r + 1'b1;
    end
  end

  // ---- Write state machine (discards writes, returns DECERR) ----
  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} w_state_e;
  w_state_e w_state_r;

  logic [$bits(axi_req_i.aw.id)-1:0] aw_id_r;

  wire aw_fire = axi_req_i.aw_valid && axi_resp_o.aw_ready;
  wire w_wr_fire = axi_req_i.w_valid && axi_resp_o.w_ready;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      w_state_r <= W_IDLE;
      aw_id_r   <= '0;
    end else begin
      case (w_state_r)
        W_IDLE: if (aw_fire) begin
          aw_id_r <= axi_req_i.aw.id;
          // Simultaneous AW+W with WLAST: skip W_DATA and go straight to RESP
          if (axi_req_i.w_valid && axi_req_i.w.last)
            w_state_r <= W_RESP;
          else
            w_state_r <= W_DATA;
        end
        W_DATA: if (w_wr_fire && axi_req_i.w.last) w_state_r <= W_RESP;
        W_RESP: if (axi_req_i.b_ready)              w_state_r <= W_IDLE;
        default: w_state_r <= W_IDLE;
      endcase
    end
  end

  // ---- AXI response combinational outputs ----
  always_comb begin
    axi_resp_o          = '0;
    // AR: accept when read SM idle
    axi_resp_o.ar_ready = (r_state_r == R_IDLE);
    // R: valid when in burst and FIFO not empty
    axi_resp_o.r_valid  = (r_state_r == R_BURST) && !empty_w;
    axi_resp_o.r.id     = ar_id_r;
    axi_resp_o.r.data   = mem[rd_ptr_r[LG_FIFO_DEPTH_P-1:0]];
    axi_resp_o.r.resp   = RESP_OKAY;
    axi_resp_o.r.last   = (r_beats_rem_r == '0);
    // AW: accept when write SM idle
    axi_resp_o.aw_ready = (w_state_r == W_IDLE);
    // W: accept in W_DATA, or same cycle as AW fires in W_IDLE
    axi_resp_o.w_ready  = (w_state_r == W_DATA) ||
                          ((w_state_r == W_IDLE) && axi_req_i.aw_valid);
    // B: DECERR after all write data has been accepted
    axi_resp_o.b_valid  = (w_state_r == W_RESP);
    axi_resp_o.b.id     = aw_id_r;
    axi_resp_o.b.resp   = RESP_DECERR;
  end

endmodule : bsg_link_axi_rx_fifo
