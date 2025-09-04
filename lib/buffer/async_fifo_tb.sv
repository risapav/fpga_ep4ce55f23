module AsyncFIFO_tb;

  parameter DATA_WIDTH = 8;
  parameter DEPTH      = 16;

  // Hodiny a resety
  logic wr_clk, rd_clk;
  logic wr_rstn, rd_rstn;

  // FIFO signály
  logic                  wr_en, rd_en;
  logic [DATA_WIDTH-1:0] wr_data, rd_data;
  logic                  full, empty;

  // DUT – Design Under Test
  AsyncFIFO #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) dut (
    .wr_clk(wr_clk),
    .wr_rstn(wr_rstn),
    .wr_en(wr_en),
    .wr_data(wr_data),
    .full(full),

    .rd_clk(rd_clk),
    .rd_rstn(rd_rstn),
    .rd_en(rd_en),
    .rd_data(rd_data),
    .empty(empty)
  );

  // Hodinové generátory – rôzne periódy pre asynchrónnosť
  initial wr_clk = 0;
  always #5 wr_clk = ~wr_clk; // 100 MHz

  initial rd_clk = 0;
  always #7 rd_clk = ~rd_clk; // ~71 MHz

  // FIFO test logika
  logic [7:0] tx_counter, rx_counter;
  logic [7:0] rx_data_log [0:255];

  initial begin
    // Reset
    wr_rstn = 0;
    rd_rstn = 0;
    wr_en   = 0;
    rd_en   = 0;
    tx_counter = 0;
    rx_counter = 0;

    #20;
    wr_rstn = 1;
    rd_rstn = 1;

    // Čakáme na stabilizáciu
    #20;

    fork
      // Write process
      forever begin
        @(posedge wr_clk);
        if (!full && tx_counter < 100) begin
          wr_en   <= 1;
          wr_data <= tx_counter;
          tx_counter <= tx_counter + 1;
        end else begin
          wr_en <= 0;
        end
      end

      // Read process
      forever begin
        @(posedge rd_clk);
        if (!empty && rx_counter < tx_counter) begin
          rd_en <= 1;
        end else begin
          rd_en <= 0;
        end
      end

      // Monitor read data
      forever begin
        @(posedge rd_clk);
        if (rd_en && !empty) begin
          rx_data_log[rx_counter] = rd_data;
          $display("Read data[%0d] = %0d", rx_counter, rd_data);
          rx_counter <= rx_counter + 1;
        end
      end

    join_any

    // Očakávame, že sa FIFO vyprázdni
    wait (rx_counter == tx_counter);

    // Overenie obsahu FIFO
    for (int i = 0; i < tx_counter; i++) begin
      if (rx_data_log[i] !== i)
        $display("❌ Mismatch at index %0d: got %0d, expected %0d", i, rx_data_log[i], i);
      else
        $display("✅ Match at index %0d: %0d", i, rx_data_log[i]);
    end

    $display("✅ Test completed successfully.");
    $finish;
  end

endmodule
