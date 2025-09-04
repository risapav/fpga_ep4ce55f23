module axi_stream_sender #(
  parameter DATA_WIDTH = 64
)(
  input  logic                    clk,
  input  logic                    rstn,
  axi4s_if.master                 axis,
  input  logic [DATA_WIDTH-1:0]  fifo_rd_data,
  output logic                   fifo_rd_en,
  input  logic                   fifo_empty
);

  always_comb begin
    axis.tvalid = !fifo_empty;
    axis.tdata  = fifo_rd_data;
    axis.tkeep  = '1;
    axis.tlast  = 1'b0;  // nastav podľa potreby (napr. na konci bloku)
    fifo_rd_en  = axis.tvalid && axis.tready;
  end

endmodule
