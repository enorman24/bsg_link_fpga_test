// AXI4 write-slave backed by a synchronous FIFO.
// Write transactions push data words into the FIFO; the FIFO drains to the
// bsg_link TX core-side interface (valid/data/ready).
// Read transactions return DECERR.
// WREADY deasserts when the FIFO is full, providing AXI-legal backpressure.

module bsg_link_axi_tx_fifo
  import bsg_link_xbar_pkg::*;
#(
  parameter type axi_req_t      = mst_req_t,
  parameter type axi_resp_t     = mst_resp_t,
  parameter int  LG_FIFO_DEPTH_P = 5
) (
  input  logic      clk_i,
  input  logic      rst_i,

  // AXI4 slave port
  input  axi_req_t  axi_req_i,
  output axi_resp_t axi_resp_o,

  // bsg_link TX core-side
  output logic                        tx_valid_o,
  output logic [AxiDataWidth-1:0]     tx_data_o,
  input  logic                        tx_ready_i,

  // FIFO status
  output logic                        tx_fifo_full_o,
  output logic                        tx_fifo_empty_o,
  output logic [LG_FIFO_DEPTH_P:0]    tx_fifo_count_o
);

  localparam int Depth = 1 << LG_FIFO_DEPTH_P;

  // ---- Synchronous FIFO ----
  logic [AxiDataWidth-1:0]   mem [0:Depth-1];
  logic [LG_FIFO_DEPTH_P:0]  wr_ptr_r, rd_ptr_r;

  wire full_w  = (wr_ptr_r[LG_FIFO_DEPTH_P] != rd_ptr_r[LG_FIFO_DEPTH_P]) &&
                 (wr_ptr_r[LG_FIFO_DEPTH_P-1:0] == rd_ptr_r[LG_FIFO_DEPTH_P-1:0]);
  wire empty_w = (wr_ptr_r == rd_ptr_r);

  assign tx_fifo_full_o  = full_w;
  assign tx_fifo_empty_o = empty_w;
  assign tx_fifo_count_o = wr_ptr_r - rd_ptr_r;

  // ---- AXI write state machine ----
  typedef enum logic [1:0] {IDLE, BURST, RESP} state_e;
  state_e state_r;

  logic [$bits(axi_req_i.aw.id)-1:0] aw_id_r;

  wire aw_fire = axi_req_i.aw_valid && axi_resp_o.aw_ready;
  wire w_fire  = axi_req_i.w_valid  && axi_resp_o.w_ready;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_r <= IDLE;
      aw_id_r <= '0;
    end else begin
      case (state_r)
        IDLE:  if (aw_fire) begin
                 aw_id_r <= axi_req_i.aw.id;
                 state_r <= BURST;
               end
        BURST: if (w_fire && axi_req_i.w.last)  state_r <= RESP;
        RESP:  if (axi_req_i.b_ready)            state_r <= IDLE;
        default: state_r <= IDLE;
      endcase
    end
  end

  // Push W beats to FIFO while in BURST state and there is space
  wire push_w = (state_r == BURST) && w_fire;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      wr_ptr_r <= '0;
    end else if (push_w) begin
      mem[wr_ptr_r[LG_FIFO_DEPTH_P-1:0]] <= axi_req_i.w.data;
      wr_ptr_r <= wr_ptr_r + 1'b1;
    end
  end

  // Drain FIFO to bsg_link TX
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      rd_ptr_r <= '0;
    end else if (!empty_w && tx_ready_i) begin
      rd_ptr_r <= rd_ptr_r + 1'b1;
    end
  end

  assign tx_valid_o = !empty_w;
  assign tx_data_o  = mem[rd_ptr_r[LG_FIFO_DEPTH_P-1:0]];

  // ---- Read state machine (returns DECERR for all reads) ----
  typedef enum logic {R_IDLE, R_BURST} r_state_e;
  r_state_e r_state_r;

  logic [$bits(axi_req_i.ar.id)-1:0] ar_id_r;
  logic [7:0] r_beats_rem_r;

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
          r_beats_rem_r <= axi_req_i.ar.len;
          r_state_r     <= R_BURST;
        end
        R_BURST: if (r_fire) begin
          if (r_beats_rem_r == '0)
            r_state_r <= R_IDLE;
          else
            r_beats_rem_r <= r_beats_rem_r - 1'b1;
        end
        default: r_state_r <= R_IDLE;
      endcase
    end
  end

  // ---- AXI response combinational outputs ----
  always_comb begin
    axi_resp_o          = '0;
    // AW: accept only when idle
    axi_resp_o.aw_ready = (state_r == IDLE);
    // W: accept during burst when FIFO has space
    axi_resp_o.w_ready  = (state_r == BURST) && !full_w;
    // B: respond after burst completes
    axi_resp_o.b_valid  = (state_r == RESP);
    axi_resp_o.b.id     = aw_id_r;
    axi_resp_o.b.resp   = RESP_OKAY;
    // AR: accept when read SM idle; return DECERR on all R beats
    axi_resp_o.ar_ready = (r_state_r == R_IDLE);
    axi_resp_o.r_valid  = (r_state_r == R_BURST);
    axi_resp_o.r.id     = ar_id_r;
    axi_resp_o.r.resp   = RESP_DECERR;
    axi_resp_o.r.last   = (r_beats_rem_r == '0);
    axi_resp_o.r.data   = '0;
  end

endmodule : bsg_link_axi_tx_fifo
