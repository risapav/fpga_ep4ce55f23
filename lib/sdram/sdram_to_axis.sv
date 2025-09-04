//sdram_to_axis.sv

module SdramToAxiStreamRead #(
  parameter DATA_WIDTH = 16,
  parameter ADDR_WIDTH = 24,
  parameter FIFO_DEPTH = 1024,
  parameter BURST_LEN  = 8
)(
  input  logic        axi_clk,
  input  logic        axi_rstn,
  input  logic        sdram_clk,
  input  logic        sdram_rstn,

  axi4s_if.master     m_axis,  // AXI Stream výstup

  // SDRAM Controller interface
  output logic                  sdram_cmd_valid,
  output logic                  sdram_cmd_rw,     // 1 = read
  output logic [ADDR_WIDTH-1:0] sdram_cmd_addr,
  input  logic [DATA_WIDTH-1:0] sdram_cmd_rdata,
  input  logic                  sdram_resp_valid,
  output logic                  sdram_resp_ready
);

  // FIFO signály (SDRAM → AXI clock domain)
  logic fifo_wr_en, fifo_rd_en;
  logic [DATA_WIDTH-1:0] fifo_din, fifo_dout;
  logic fifo_full, fifo_empty;

  // SDRAM write (sdram_clk domain)
  assign fifo_wr_en       = sdram_resp_valid && sdram_resp_ready;
  assign fifo_din         = sdram_cmd_rdata;
  assign sdram_resp_ready = ~fifo_full;

  // AXI read (axi_clk domain)
  assign fifo_rd_en   = m_axis.tready && m_axis.tvalid;
  assign m_axis.tdata = fifo_dout;
  assign m_axis.tvalid = ~fifo_empty;

  // tlast na konci burstu
  logic [3:0] burst_read_cnt;
  logic       tlast_reg;

  always_ff @(posedge axi_clk or negedge axi_rstn) begin
    if (!axi_rstn) begin
      burst_read_cnt <= 0;
      tlast_reg      <= 0;
    end else if (fifo_rd_en) begin
      if (burst_read_cnt == BURST_LEN - 1) begin
        burst_read_cnt <= 0;
        tlast_reg <= 1;
      end else begin
        burst_read_cnt <= burst_read_cnt + 1;
        tlast_reg <= 0;
      end
    end else begin
      tlast_reg <= 0;
    end
  end

  assign m_axis.tlast = tlast_reg;

  // FIFO inštancia
  DualClockFifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(FIFO_DEPTH)
  ) fifo_inst (
    .wr_clk (sdram_clk),
    .wr_rstn(sdram_rstn),
    .wr_en  (fifo_wr_en),
    .din    (fifo_din),
    .full   (fifo_full),

    .rd_clk (axi_clk),
    .rd_rstn(axi_rstn),
    .rd_en  (fifo_rd_en),
    .dout   (fifo_dout),
    .empty  (fifo_empty)
  );

  // FSM: generovanie read príkazov
  typedef enum logic [1:0] {
    CMD_IDLE,
    CMD_READ,
    CMD_WAIT_RESP
  } cmd_state_t;

  cmd_state_t cmd_state, cmd_next;

  logic [ADDR_WIDTH-1:0] read_addr;
  logic [3:0] burst_cnt;

  // Sekvenčná logika FSM (sdram_clk doména)
  always_ff @(posedge sdram_clk or negedge sdram_rstn) begin
    if (!sdram_rstn) begin
      cmd_state <= CMD_IDLE;
      read_addr <= 0;
      burst_cnt <= 0;
    end else begin
      cmd_state <= cmd_next;

      if (cmd_state == CMD_READ && sdram_cmd_valid && sdram_cmd_ready) begin
        read_addr <= read_addr + 1;
        burst_cnt <= burst_cnt + 1;
      end

      if (cmd_state == CMD_IDLE)
        burst_cnt <= 0;
    end
  end

  // Kombinačná logika FSM
  always_comb begin
    sdram_cmd_valid = 0;
    sdram_cmd_rw    = 1;  // read
    sdram_cmd_addr  = read_addr;
    cmd_next        = cmd_state;

    case (cmd_state)
      CMD_IDLE: begin
        if (!fifo_full)
          cmd_next = CMD_READ;
      end

      CMD_READ: begin
        sdram_cmd_valid = 1;
        if (sdram_cmd_ready)
          cmd_next = CMD_WAIT_RESP;
      end

      CMD_WAIT_RESP: begin
        if (sdram_resp_valid) begin
          if (burst_cnt == BURST_LEN - 1)
            cmd_next = CMD_IDLE;
          else if (!fifo_full)
            cmd_next = CMD_READ;
        end
      end

      default: cmd_next = CMD_IDLE;
    endcase
  end

endmodule
