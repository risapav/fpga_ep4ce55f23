module AxiStreamToSdramWrite #(
  parameter DATA_WIDTH = 16,
  parameter ADDR_WIDTH = 24,
  parameter FIFO_DEPTH = 1024,
  parameter BURST_LEN  = 8
)(
  input  logic        axi_clk,
  input  logic        axi_rstn,
  input  logic        sdram_clk,
  input  logic        sdram_rstn,

  axi4s_if.slave      s_axis,  // AXI4-Stream vstup

  // SDRAM Controller command interface
  output logic                  sdram_cmd_valid,
  output logic                  sdram_cmd_rw,     // 0 = write
  output logic [ADDR_WIDTH-1:0] sdram_cmd_addr,
  output logic [DATA_WIDTH-1:0] sdram_cmd_wdata,
  input  logic                  sdram_cmd_ready,

  input  logic                  sdram_resp_valid,
  output logic                  sdram_resp_ready,

  // Status
  output logic                  fifo_overflow
);

  // FIFO prekladá tlast do vyššieho bitu
  logic [DATA_WIDTH:0] fifo_din_ext, fifo_dout_ext;
  logic fifo_wr_en, fifo_rd_en;
  logic fifo_full, fifo_empty;

  assign fifo_din_ext = {s_axis.tlast, s_axis.tdata};
  assign fifo_wr_en   = s_axis.tvalid && s_axis.tready;
  assign s_axis.tready = ~fifo_full;

  // FIFO overflow detekcia
  always_ff @(posedge axi_clk or negedge axi_rstn) begin
    if (!axi_rstn)
      fifo_overflow <= 0;
    else if (s_axis.tvalid && fifo_full)
      fifo_overflow <= 1;
    else
      fifo_overflow <= 0;
  end

  // FIFO inštancia pre prechod medzi hodinovými doménami
  DualClockFifo #(
    .DATA_WIDTH(DATA_WIDTH + 1),
    .DEPTH(FIFO_DEPTH)
  ) fifo_inst (
    .wr_clk(axi_clk),
    .wr_rstn(axi_rstn),
    .wr_en(fifo_wr_en),
    .din(fifo_din_ext),
    .full(fifo_full),

    .rd_clk(sdram_clk),
    .rd_rstn(sdram_rstn),
    .rd_en(fifo_rd_en),
    .dout(fifo_dout_ext),
    .empty(fifo_empty)
  );

  // FIFO výstup
  logic tlast_sync;
  assign {tlast_sync, sdram_cmd_wdata} = fifo_dout_ext;
  assign fifo_rd_en = sdram_cmd_valid && sdram_cmd_ready;

  // FSM
  typedef enum logic [1:0] {
    CMD_IDLE,
    CMD_WRITE,
    CMD_WAIT_RESP
  } cmd_state_t;

  cmd_state_t cmd_state, cmd_next;

  logic [ADDR_WIDTH-1:0] write_addr;
  logic [3:0] burst_cnt;
  logic burst_active;

  // Sekvenčná logika
  always_ff @(posedge sdram_clk or negedge sdram_rstn) begin
    if (!sdram_rstn) begin
      cmd_state     <= CMD_IDLE;
      write_addr    <= 0;
      burst_cnt     <= 0;
      burst_active  <= 0;
    end else begin
      cmd_state <= cmd_next;

      if (cmd_state == CMD_WRITE && sdram_cmd_valid && sdram_cmd_ready) begin
        write_addr <= write_addr + 1;

        if (burst_cnt < BURST_LEN - 1)
          burst_cnt <= burst_cnt + 1;
        else
          burst_cnt <= 0;

        if (tlast_sync || burst_cnt == BURST_LEN - 1)
          burst_active <= 0;
      end

      if (cmd_state == CMD_IDLE && !fifo_empty)
        burst_active <= 1;
    end
  end

  // Kombinačná logika
  always_comb begin
    sdram_cmd_valid  = 0;
    sdram_cmd_rw     = 0; // write
    sdram_cmd_addr   = write_addr;
    sdram_resp_ready = 0;
    cmd_next         = cmd_state;

    case (cmd_state)
      CMD_IDLE: begin
        if (!fifo_empty && burst_active)
          cmd_next = CMD_WRITE;
      end

      CMD_WRITE: begin
        if (!fifo_empty && burst_active) begin
          sdram_cmd_valid = 1;
          if (sdram_cmd_ready)
            cmd_next = CMD_WAIT_RESP;
        end else
          cmd_next = CMD_IDLE;
      end

      CMD_WAIT_RESP: begin
        sdram_resp_ready = 1;
        if (sdram_resp_valid) begin
          if (burst_cnt == BURST_LEN - 1 || tlast_sync)
            cmd_next = CMD_IDLE;
          else
            cmd_next = CMD_WRITE;
        end
      end

      default: cmd_next = CMD_IDLE;
    endcase
  end

endmodule


