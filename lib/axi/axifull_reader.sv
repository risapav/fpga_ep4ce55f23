module Axi4FullReader #(
  parameter ADDR_WIDTH = 32,
  parameter DATA_WIDTH = 64,
  parameter ID_WIDTH = 4,
  parameter BURST_LEN = 16  // počet slov v burste
)(
  input  logic              clk,
  input  logic              rstn,

  // Výstupné dáta (z AXI4-Full R channel)
  output logic [DATA_WIDTH-1:0] data_out,
  output logic              data_valid,
  input  logic              data_ready,  // downstream ready na dáta (FIFO rd_en)

  // AXI4-Full master interface (slave je SDRAM alebo pamäťový kontrolér)
  axi4_if #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH) axi4_master_if,

  // Adresa a veľkosť čítania (môže byť riadené zhora)
  input logic [ADDR_WIDTH-1:0] read_addr,
  input logic [15:0] read_length,  // počet slov na čítanie (max burst LEN na burst)
  input logic start_read,
  output logic read_done
);

  typedef enum logic [1:0] {
    IDLE,
    SEND_AR,
    READ_DATA,
    DONE
  } state_t;

  state_t state, next_state;

  logic [ADDR_WIDTH-1:0] addr;
  logic [7:0] burst_count;       // počíta slov v jednom burste
  logic [15:0] words_left;       // zostávajúce slová na čítanie

  // AR handshake
  logic ar_handshake = axi4_master_if.ARVALID && axi4_master_if.ARREADY;

  // R handshake
  logic r_handshake = axi4_master_if.RVALID && axi4_master_if.RREADY;

  // Reset a inicializácia
  always_ff @(posedge clk) begin
    if (!rstn) begin
      state <= IDLE;
      addr <= 0;
      burst_count <= 0;
      words_left <= 0;
      read_done <= 0;
    end else begin
      state <= next_state;

      if (state == IDLE && start_read) begin
        addr <= read_addr;
        words_left <= read_length;
        read_done <= 0;
        burst_count <= 0;
      end

      if (ar_handshake) begin
        burst_count <= 0;
        // burst burst_len or words_left if smaller
        if (words_left > BURST_LEN)
          words_left <= words_left - BURST_LEN;
        else
          words_left <= 0;
      end

      if (state == READ_DATA && r_handshake) begin
        burst_count <= burst_count + 1;
        if (axi4_master_if.RLAST) begin
          addr <= addr + BURST_LEN * (DATA_WIDTH/8);
          if (words_left == 0)
            read_done <= 1;
        end
      end

      if (read_done)
        state <= DONE;
    end
  end

  // Stavový stroj
  always_comb begin
    next_state = state;

    axi4_master_if.ARVALID = 0;
    axi4_master_if.ARADDR  = addr;
    axi4_master_if.ARLEN   = (words_left > BURST_LEN) ? (BURST_LEN - 1) : (words_left - 1);
    axi4_master_if.ARSIZE  = $clog2(DATA_WIDTH/8);
    axi4_master_if.ARBURST = 2'b01; // INCR burst
    axi4_master_if.ARID    = 0;
    axi4_master_if.ARPROT  = 0;

    axi4_master_if.RREADY = 0;

    data_valid = 0;
    data_out = '0;

    case(state)
      IDLE: begin
        if (start_read) begin
          next_state = SEND_AR;
        end
      end

      SEND_AR: begin
        axi4_master_if.ARVALID = 1;
        if (axi4_master_if.ARREADY) begin
          next_state = READ_DATA;
        end
      end

      READ_DATA: begin
        axi4_master_if.RREADY = data_ready;
        if (axi4_master_if.RVALID && data_ready) begin
          data_valid = 1;
          data_out = axi4_master_if.RDATA;
        end

        if (axi4_master_if.RVALID && axi4_master_if.RLAST && data_ready) begin
          if (words_left == 0) next_state = DONE;
          else next_state = SEND_AR;
        end
      end

      DONE: begin
        // Môžeme čakať na nový start_read
        if (!start_read)
          next_state = IDLE;
      end
    endcase
  end

endmodule
