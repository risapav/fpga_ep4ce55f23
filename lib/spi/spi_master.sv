module spi_master #(
    parameter CLK_DIV = 4  // clock divider for SCLK (must be >=2)
)(
    input  logic       clk,
    input  logic       rst,

    // Control interface
    input  logic       start,         // začiatok prenosu
    input  logic [7:0] data_in,       // dátový vstup (MOSI)
    output logic [7:0] data_out,      // dátový výstup (MISO)
    output logic       done,          // signál konca prenosu

    // SPI interface
    output logic       sclk,          // SPI Clock
    output logic       mosi,          // Master Out Slave In
    input  logic       miso,          // Master In Slave Out
    output logic       ss             // Slave Select (aktivovaný LOW)
);

    typedef enum logic [1:0] {
        IDLE, START, TRANSFER, DONE
    } state_t;

    state_t state;
    logic [7:0] shift_reg;
    logic [2:0] bit_cnt;
    logic [15:0] clk_div_cnt;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            sclk       <= 0;
            ss         <= 1;
            done       <= 0;
            mosi       <= 0;
            data_out   <= 0;
            shift_reg  <= 0;
            bit_cnt    <= 0;
            clk_div_cnt <= 0;
        end else begin
            case (state)
                IDLE: begin
                    sclk <= 0;
                    ss   <= 1;
                    done <= 0;
                    if (start) begin
                        shift_reg <= data_in;
                        bit_cnt <= 3'd7;
                        clk_div_cnt <= 0;
                        ss <= 0;
                        state <= START;
                    end
                end

                START: begin
                    if (clk_div_cnt == CLK_DIV/2 - 1) begin
                        sclk <= ~sclk;
                        clk_div_cnt <= 0;
                        if (sclk == 0) begin
                            mosi <= shift_reg[7];
                        end else begin
                            shift_reg <= {shift_reg[6:0], miso};
                            if (bit_cnt == 0) begin
                                state <= DONE;
                                data_out <= {shift_reg[6:0], miso};
                            end else begin
                                bit_cnt <= bit_cnt - 1;
                            end
                        end
                    end else begin
                        clk_div_cnt <= clk_div_cnt + 1;
                    end
                end

                DONE: begin
                    sclk <= 0;
                    ss   <= 1;
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
