module spi_slave (
    input  logic       clk,      // systémový clock (na spracovanie výstupu)
    input  logic       rst,

    input  logic       sclk,     // SPI Clock (z mastera)
    input  logic       mosi,     // Master Out Slave In
    output logic       miso,     // Master In Slave Out
    input  logic       ss,       // Slave Select (aktívne LOW)

    input  logic [7:0] data_in,  // dáta pripravené na odoslanie (MISO)
    input  logic       data_in_valid,
    output logic [7:0] data_out, // prijaté dáta (MOSI)
    output logic       data_ready // indikátor, že prijaté dáta sú platné
);

    logic [2:0] bit_cnt;
    logic [7:0] shift_in;
    logic [7:0] shift_out;
    logic       sclk_prev;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt     <= 0;
            shift_in    <= 0;
            shift_out   <= 8'h00;
            data_out    <= 0;
            data_ready  <= 0;
            sclk_prev   <= 0;
            miso        <= 0;
        end else begin
            sclk_prev <= sclk;

            if (~ss) begin  // slave is selected
                if (data_in_valid && bit_cnt == 0) begin
                    shift_out <= data_in;
                end

                // Detect rising edge of SCLK (Mode 0)
                if (sclk == 1 && sclk_prev == 0) begin
                    shift_in <= {shift_in[6:0], mosi};
                    bit_cnt <= bit_cnt + 1;

                    // Shift out MSB first
                    miso <= shift_out[7];
                    shift_out <= {shift_out[6:0], 1'b0};

                    if (bit_cnt == 3'd7) begin
                        data_out   <= {shift_in[6:0], mosi};
                        data_ready <= 1;
                        bit_cnt    <= 0;
                    end else begin
                        data_ready <= 0;
                    end
                end
            end else begin
                // deselected
                bit_cnt    <= 0;
                data_ready <= 0;
                miso       <= 0;
            end
        end
    end

endmodule
