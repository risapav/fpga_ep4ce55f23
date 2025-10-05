// tb_sdram_core.sv - Verzia 1.1 - Pridaný $monitor pre textové ladenie
`timescale 1ns / 1ps
(* default_nettype = "none" *)

module tb_sdram_core;

    // --- Generovanie hodín a resetu ---
    localparam CLK_100MHZ_PERIOD = 10ns;
    logic clk_100mhz = 1'b0;
    logic clk_100mhz_shifted = 1'b1;
    logic rstn_axi;

    always #(CLK_100MHZ_PERIOD / 2) clk_100mhz = ~clk_100mhz;
    always #(CLK_100MHZ_PERIOD / 2) clk_100mhz_shifted = ~clk_100mhz_shifted;

    initial begin
        rstn_axi = 1'b0;
        #(CLK_100MHZ_PERIOD * 20);
        rstn_axi = 1'b1;
    end

    // --- Signály pre prepojenie modulov ---
    logic reader_valid, reader_ready;
    logic [23:0] reader_addr;
    logic writer_valid, writer_ready;
    logic [23:0] writer_addr;
    logic [15:0] writer_data;
    logic resp_valid, resp_last, resp_ready;
    logic [15:0] resp_data;

    wire [15:0] SDRAM_DQ;
    logic [12:0] SDRAM_ADDR;
    logic [1:0]  SDRAM_BA;
    logic        SDRAM_CAS_N, SDRAM_CKE, SDRAM_CS_N;
    logic        SDRAM_WE_N, SDRAM_RAS_N, SDRAM_UDQM, SDRAM_LDQM;

    logic pass_led, fail_led, busy_led;
    logic [3:0] test_state;

    // --- Inštancia #1: Tester ---
    SimpleSdramTester tester (
        .clk_axi(clk_100mhz), .rstn_axi(rstn_axi),
        .reader_valid_o(reader_valid), .reader_ready_i(reader_ready), .reader_addr_o(reader_addr),
        .writer_valid_o(writer_valid), .writer_ready_i(writer_ready), .writer_addr_o(writer_addr), .writer_data_o(writer_data),
        .resp_valid_i(resp_valid), .resp_last_i(resp_last), .resp_data_i(resp_data), .resp_ready_o(resp_ready),
        .test_state_o(test_state), .pass_led_o(pass_led), .fail_led_o(fail_led), .busy_led_o(busy_led)
    );

    // --- Inštancia #2: Driver (Unit Under Test) ---
    SdramDriver sdram_driver (
        .clk_axi(clk_100mhz), .clk_sdram(clk_100mhz),
        .rstn_axi(rstn_axi), .rstn_sdram(rstn_axi),
        .reader_valid(reader_valid), .reader_ready(reader_ready), .reader_addr(reader_addr),
        .writer_valid(writer_valid), .writer_ready(writer_ready), .writer_addr(writer_addr), .writer_data(writer_data),
        .resp_valid(resp_valid), .resp_last(resp_last), .resp_data(resp_data), .resp_ready(resp_ready),
        .error_overflow_o(), .error_underflow_o(), .error_clear_i(1'b0),
        .sdram_addr(SDRAM_ADDR), .sdram_ba(SDRAM_BA), .sdram_cs_n(SDRAM_CS_N),
        .sdram_ras_n(SDRAM_RAS_N), .sdram_cas_n(SDRAM_CAS_N), .sdram_we_n(SDRAM_WE_N),
        .sdram_dq(SDRAM_DQ), .sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}), .sdram_cke(SDRAM_CKE)
    );

    // --- Inštancia #3: SDRAM Model ---
    generic_sdram sdram_model (
        .DQ(SDRAM_DQ),
        .A(SDRAM_ADDR),
        .BA(SDRAM_BA),
        .CLK(clk_100mhz_shifted),
        .rstn(rstn_axi),           // <-- pridané
        .CKE(SDRAM_CKE),
        .CS_n(SDRAM_CS_N),
        .RAS_n(SDRAM_RAS_N),
        .CAS_n(SDRAM_CAS_N),
        .WE_n(SDRAM_WE_N),
        .DQM({SDRAM_UDQM, SDRAM_LDQM})
    );

    // =================================================================
    // == NOVÝ BLOK PRE TEXTOVÉ LADENIE ==
    // =================================================================
    // Pomocný signál pre zobrazenie očakávaných dát
    wire [15:0] expected_data = tester.test_pattern_base + tester.burst_cnt;

    initial begin
        // Tento príkaz bude sledovať signály a vypíše riadok na konzolu VŽDY,
        // keď sa ktorýkoľvek z nich zmení.
        $monitor("[%0t ns] -- TESTER: state=%d, burst_cnt=%d | CONTROLLER: state=%d, burst_cnt=%d | RESPONSE: valid=%b, last=%b, data=%h (exp: %h)",
            $time,
            tester.state_reg,
            tester.burst_cnt,
            sdram_driver.controller.state_reg,
            sdram_driver.controller.burst_cnt,
            resp_valid,
            resp_last,
            resp_data,
            expected_data
        );
    end

endmodule
