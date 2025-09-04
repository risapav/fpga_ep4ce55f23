module Axi4StreamMaster #(
  parameter DATA_WIDTH = 64
)(
  input  logic              aclk,
  input  logic              aresetn,

  // FIFO vstup
  input  logic [DATA_WIDTH-1:0] fifo_data,
  input  logic              fifo_valid,
  output logic              fifo_ready,

  // AXI4-Stream interface
  axi4s_if #(DATA_WIDTH) axi4s_master_if
);

  typedef enum logic [1:0] {
    IDLE,
    SEND
  } state_t;

  state_t state, next_state;

  always_ff @(posedge aclk) begin
    if (!aresetn)
      state <= IDLE;
    else
      state <= next_state;
  end

  always_comb begin
    fifo_ready = 0;
    axi4s_master_if.tvalid = 0;
    axi4s_master_if.tdata = '0;
    axi4s_master_if.tlast = 0;
    axi4s_master_if.tkeep = {(DATA_WIDTH/8){1'b1}};
    axi4s_master_if.tuser = 0;

    next_state = state;

    case(state)
      IDLE: begin
        if (fifo_valid) begin
          fifo_ready = 1;
          axi4s_master_if.tvalid = 1;
          axi4s_master_if.tdata = fifo_data;
          next_state = SEND;
        end
      end

      SEND: begin
        fifo_ready = axi4s_master_if.tready;
        axi4s_master_if.tvalid = fifo_valid;
        axi4s_master_if.tdata = fifo_data;

        if (axi4s_master_if.tready && fifo_valid) begin
          next_state = IDLE;
        end
      end
    endcase
  end

endmodule
