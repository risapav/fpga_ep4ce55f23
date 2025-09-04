module axi_full_reader #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 64,
  parameter ID_WIDTH   = 4,
  parameter BURST_LEN  = 16
)(
  input  logic                    clk,
  input  logic                    rstn,
  axi4_if.master                  axi,
  output logic                   fifo_wr_en,
  output logic [DATA_WIDTH-1:0] fifo_wr_data,
  input  logic                   fifo_full
);

  // Jednoduchý stavový automat
  typedef enum logic [1:0] {IDLE, SEND_AR, READ_DATA} state_t;
  state_t state, next_state;

  logic [ADDR_WIDTH-1:0] addr_reg;
  logic [3:0]            beat_count;

  always_ff @(posedge clk) begin
    if (!rstn) begin
      state <= IDLE;
      addr_reg <= 32'h0000_0000;
    end else begin
      state <= next_state;
    end
  end

  always_comb begin
    // Defaulty
    axi.ARVALID = 0;
    axi.ARADDR  = '0;
    axi.ARLEN   = BURST_LEN - 1;
    axi.ARSIZE  = $clog2(DATA_WIDTH / 8);
    axi.ARBURST = 2'b01; // INCR
    axi.ARID    = 0;
    axi.ARPROT  = 3'b000;

    axi.RREADY  = 0;
    fifo_wr_en  = 0;
    fifo_wr_data = axi.RDATA;

    next_state = state;

    case (state)
      IDLE: begin
        if (!fifo_full) begin
          axi.ARVALID = 1;
          axi.ARADDR  = addr_reg;
          if (axi.ARREADY)
            next_state = READ_DATA;
        end
      end

      READ_DATA: begin
        axi.RREADY = !fifo_full;
        fifo_wr_en = axi.RVALID && !fifo_full;
        if (axi.RVALID && axi.RLAST)
          next_state = IDLE;
      end
    endcase
  end

endmodule
