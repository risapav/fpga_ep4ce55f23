module Axi4FullWriter #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 64,
  parameter ID_WIDTH = 4,
  parameter BURST_LEN = 16 // počet slov v burste
)(
  input  logic              clk,
  input  logic              rstn,

  // FIFO vstup (z AsyncFIFO)
  input  logic [DATA_WIDTH-1:0] fifo_data,
  input  logic              fifo_empty,
  output logic              fifo_rd_en,

  // AXI4-Full rozhranie master
  axi4_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) axi4_master_if
);

  typedef enum logic [1:0] {
    IDLE,
    SEND_AW,
    SEND_W,
    WAIT_B
  } state_t;

  state_t state, next_state;

  // Adresa zápisu, môže byť parameter alebo reg
  logic [ADDR_WIDTH-1:0] write_addr;
  logic [7:0] burst_count; // počítadlo slov v burste

  // FIFO read povel
  assign fifo_rd_en = (state == SEND_W) && axi4_master_if.WREADY && axi4_master_if.WVALID;

  // Inicializácia adries, ID
  always_ff @(posedge clk) begin
    if (!rstn) begin
      state <= IDLE;
      write_addr <= 0;
      burst_count <= 0;
    end else begin
      state <= next_state;

      if (state == WAIT_B && axi4_master_if.BVALID && axi4_master_if.BREADY) begin
        // Po potvrdení zápisu posun adresu o burst
        write_addr <= write_addr + BURST_LEN * (DATA_WIDTH/8);
      end

      if (state == SEND_W && axi4_master_if.WREADY && axi4_master_if.WVALID) begin
        if (burst_count == BURST_LEN - 1)
          burst_count <= 0;
        else
          burst_count <= burst_count + 1;
      end else if (state == IDLE) begin
        burst_count <= 0;
      end
    end
  end

  // Stavový stroj
  always_comb begin
    next_state = state;
    axi4_master_if.AWVALID = 0;
    axi4_master_if.AWADDR  = write_addr;
    axi4_master_if.AWLEN   = BURST_LEN - 1;
    axi4_master_if.AWSIZE  = $clog2(DATA_WIDTH/8);
    axi4_master_if.AWBURST = 2'b01; // INCR burst
    axi4_master_if.AWID    = 0;
    axi4_master_if.AWPROT  = 0;

    axi4_master_if.WVALID = 0;
    axi4_master_if.WDATA = fifo_data;
    axi4_master_if.WSTRB = {(DATA_WIDTH/8){1'b1}};
    axi4_master_if.WLAST = (burst_count == BURST_LEN - 1);

    axi4_master_if.BREADY = 0;

    case (state)
      IDLE: begin
        if (!fifo_empty) next_state = SEND_AW;
      end

      SEND_AW: begin
        axi4_master_if.AWVALID = 1;
        if (axi4_master_if.AWREADY) next_state = SEND_W;
      end

      SEND_W: begin
        axi4_master_if.WVALID = 1;
        if (axi4_master_if.WREADY && axi4_master_if.WLAST) next_state = WAIT_B;
      end

      WAIT_B: begin
        axi4_master_if.BREADY = 1;
        if (axi4_master_if.BVALID) next_state = IDLE;
      end
    endcase
  end

endmodule
