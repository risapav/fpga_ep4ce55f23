module AxiStreamToAsyncFifo #(
  parameter DATA_WIDTH = 64,
  parameter FIFO_DEPTH = 1024
)(
  // AXI4-Stream slave interface 75 MHz
  axi4s_if #(DATA_WIDTH, DATA_WIDTH/8) axi4s_slave_if,

  // AsyncFIFO read side 125 MHz
  input  logic              rd_clk,
  input  logic              rd_rstn,
  output logic [DATA_WIDTH-1:0] fifo_rd_data,
  output logic              fifo_empty,
  input  logic              fifo_rd_en
);

  // FIFO write side clock and reset (same as axi4s clock)
  logic wr_clk = axi4s_slave_if.aclk;
  logic wr_rstn = axi4s_slave_if.aresetn;

  logic fifo_full;

  // Zápisové povely FIFO
  logic fifo_wr_en = axi4s_slave_if.tvalid && axi4s_slave_if.tready;
  logic [DATA_WIDTH-1:0] fifo_wr_data = axi4s_slave_if.tdata;

  // Pripojenie ready na FIFO not full
  assign axi4s_slave_if.tready = !fifo_full;

  AsyncFIFO #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(FIFO_DEPTH)
  ) async_fifo_inst (
    .wr_clk(wr_clk),
    .wr_rstn(wr_rstn),
    .wr_en(fifo_wr_en),
    .wr_data(fifo_wr_data),
    .full(fifo_full),
    .almost_full(),

    .rd_clk(rd_clk),
    .rd_rstn(rd_rstn),
    .rd_en(fifo_rd_en),
    .rd_data(fifo_rd_data),
    .empty(fifo_empty),
    .almost_empty()
  );

endmodule
