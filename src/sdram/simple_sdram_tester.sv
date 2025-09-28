// SimpleSdramTester.sv - Verzia 2.0 - Finálna, robustná verzia FSM
(* default_nettype = "none" *)

module SimpleSdramTester #(
    parameter ADDR_WIDTH   = 24,
    parameter DATA_WIDTH   = 16,
    parameter BURST_LENGTH = 8
)(
    input  logic                   clk_axi,
    input  logic                   rstn_axi,
    output logic                   reader_valid_o,
    input  logic                   reader_ready_i,
    output logic [ADDR_WIDTH-1:0]  reader_addr_o,
    output logic                   writer_valid_o,
    input  logic                   writer_ready_i,
    output logic [ADDR_WIDTH-1:0]  writer_addr_o,
    output logic [DATA_WIDTH-1:0]  writer_data_o,
    input  logic                   resp_valid_i,
    input  logic                   resp_last_i,
    input  logic [DATA_WIDTH-1:0]  resp_data_i,
    output logic                   resp_ready_o,
    output logic [3:0]             test_state_o,
    output logic                   pass_led_o,
    output logic                   fail_led_o,
    output logic                   busy_led_o
);

    typedef enum logic [3:0] {
        S_IDLE, S_START_DELAY,
        S_WRITE_ADDR, S_WRITE_DATA, S_WAIT_INTERNAL,
        S_READ_REQ, S_READ_AND_COMPARE, // Zjednodušené stavy
        S_PASS, S_FAIL
    } state_t;

    state_t state_reg, state_next;
    logic [$clog2(BURST_LENGTH):0] burst_cnt;
    logic clear_burst_cnt, inc_burst_cnt;
    logic [DATA_WIDTH-1:0] test_pattern_base = 16'hA500;

    always_ff @(posedge clk_axi or negedge rstn_axi) begin
        if (!rstn_axi) begin
            state_reg <= S_IDLE;
            burst_cnt <= '0;
        end else begin
            state_reg <= state_next;
            if (clear_burst_cnt)    burst_cnt <= '0;
            else if (inc_burst_cnt) burst_cnt <= burst_cnt + 1;
        end
    end

    always_comb begin
        state_next      = state_reg;
        clear_burst_cnt = 1'b0; inc_burst_cnt   = 1'b0;
        reader_valid_o = 1'b0; reader_addr_o = 24'h1000;
        writer_valid_o = 1'b0; writer_addr_o = 24'h1000; writer_data_o = '0;
        resp_ready_o   = 1'b0;
        pass_led_o     = 1'b0; fail_led_o      = 1'b0; busy_led_o      = 1'b0;
        test_state_o   = state_reg;

        case(state_reg)
            S_IDLE:          state_next = S_START_DELAY;
            S_START_DELAY:   state_next = S_WRITE_ADDR; // Zjednodušené, čakáme na reset

            S_WRITE_ADDR: begin
                busy_led_o = 1'b1; writer_valid_o = 1'b1;
                if (writer_ready_i) begin
                    state_next = S_WRITE_DATA;
                    clear_burst_cnt = 1'b1;
                end
            end

            S_WRITE_DATA: begin
                busy_led_o = 1'b1; writer_valid_o = 1'b1;
                writer_data_o = test_pattern_base + burst_cnt;
                if (writer_ready_i) begin
                    inc_burst_cnt = 1'b1;
                    if (burst_cnt == BURST_LENGTH - 1) state_next = S_WAIT_INTERNAL;
                end
            end

            S_WAIT_INTERNAL: state_next = S_READ_REQ;

            S_READ_REQ: begin
                busy_led_o = 1'b1; reader_valid_o = 1'b1;
                if (reader_ready_i) begin
                    state_next = S_READ_AND_COMPARE;
                    clear_burst_cnt = 1'b1;
                end
            end

            S_READ_AND_COMPARE: begin
                busy_led_o = 1'b1;
                resp_ready_o = 1'b1; // Sme stále pripravení prijímať dáta

                if (resp_valid_i) begin
                    // Porovnanie prebieha pre aktuálnu hodnotu burst_cnt
                    if (resp_data_i != (test_pattern_base + burst_cnt)) begin
                        state_next = S_FAIL;
                    // Ak je toto posledné slovo (podľa `resp_last_i`) a dáta sú správne...
                    end else if (resp_last_i) begin
                        state_next = S_PASS; // ... test prešiel!
                    // Ak to nie je posledné slovo a dáta sú správne, pokračujeme
                    end else begin
                        inc_burst_cnt = 1'b1;
                    end
                end
            end

            S_PASS: pass_led_o = 1'b1;
            S_FAIL: fail_led_o = 1'b1;

            default: state_next = S_IDLE;
        endcase
    end
endmodule
