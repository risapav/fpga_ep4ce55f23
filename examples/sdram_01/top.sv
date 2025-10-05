// ===================================================================================
// Názov súboru: top.sv
// Verzia: 2.2 - Testovací Režim pre SDRAM
// Dátum: 26. september 2025
//
// Popis:
// Táto verzia modulu `top` je špeciálne upravená na jednoduché hardvérové
// otestovanie funkčnosti SDRAM subsystému. Všetka logika pre VGA, HDMI a
// FramebufferController je dočasne odstránená a nahradená modulom `SimpleSdramTester`.
// Výsledky testu sú vizualizované na LED diódach a 7-segmentovom displeji.
// ===================================================================================

(* default_nettype = "none" *)

module top (
    input  logic       SYS_CLK,
    input  logic       RESET_N,
    output logic [7:0] SMG_SEG,
    output logic [2:0] SMG_DIG,
    output logic [5:0] LED,
    input  logic [5:0] BSW,

    // VGA/HDMI porty nie sú v tomto teste aktívne riadené
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS,
    output logic [3:0] HDMI_P_J11,

    // SDRAM porty sú kľúčové pre tento test
    inout wire [15:0] SDRAM_DQ,
    output logic [12:0] SDRAM_ADDR,
    output logic [1:0] SDRAM_BA,
    output logic SDRAM_CAS_N,
    output logic SDRAM_CKE,
    output logic SDRAM_CLK,
    output logic SDRAM_CS_N,
    output logic SDRAM_WE_N,
    output logic SDRAM_RAS_N,
    output logic SDRAM_UDQM,
    output logic SDRAM_LDQM
);

    //==========================================================================
    // PLL a RESET logika (Zostáva bezo zmeny)
    //==========================================================================
    logic pixel_clk, pixel_clk5, clk_100mhz, clk_100mhz_shifted;
    logic pll_locked;
    logic rstn_global, rstn_sync_axi;

    // Pre jednoduchosť testu potrebujeme len clk_axi (100MHz)
    ClkPll clkpll_inst (
        .inclk0 (SYS_CLK), .areset (~RESET_N),
        .c0(pixel_clk), .c1(pixel_clk5), .c2(clk_100mhz), .c3(clk_100mhz_shifted), .locked(pll_locked)
    );

    assign rstn_global = RESET_N & pll_locked;

    cdc_reset_synchronizer reset_sync_axi_inst (
        .clk_i(clk_100mhz), .rst_ni(rstn_global), .rst_no(rstn_sync_axi)
    );
//


    //==========================================================================
    // === SDRAM TESTOVACIA LOGIKA ===
    //==========================================================================

    // --- Signály pre prepojenie Testera a Drivera ---
    logic reader_valid, reader_ready;
    logic [23:0] reader_addr;
    logic writer_valid, writer_ready;
    logic [23:0] writer_addr;
    logic [15:0] writer_data;
    logic resp_valid, resp_last, resp_ready;
    logic [15:0] resp_data;

    // Signály pre vizualizáciu z testera
    logic [3:0] test_state;
    logic pass_led, fail_led, busy_led;

    // --- Inštancia nášho nového testera ---
    SimpleSdramTester sdram_tester_inst (
        .clk_axi(clk_100mhz),
        .rstn_axi(rstn_sync_axi),
        .reader_valid_o(reader_valid),   .reader_ready_i(reader_ready), .reader_addr_o(reader_addr),
        .writer_valid_o(writer_valid),   .writer_ready_i(writer_ready), .writer_addr_o(writer_addr), .writer_data_o(writer_data),
        .resp_valid_i(resp_valid),     .resp_last_i(resp_last),     .resp_data_i(resp_data),     .resp_ready_o(resp_ready),
        .test_state_o(test_state),
        .pass_led_o(pass_led),
        .fail_led_o(fail_led),
        .busy_led_o(busy_led)
    );

    // --- Inštancia SDRAM Drivera ---
    SdramDriver #(
        .ADDR_WIDTH(24), .DATA_WIDTH(16), .BURST_LENGTH(8)
    ) sdram_driver_inst (
        .clk_axi(clk_100mhz), .clk_sdram(clk_100mhz),
        .rstn_axi(rstn_sync_axi), .rstn_sdram(rstn_sync_axi), // V tomto teste použijeme jeden reset
        .reader_valid(reader_valid), .reader_ready(reader_ready), .reader_addr(reader_addr),
        .writer_valid(writer_valid), .writer_ready(writer_ready), .writer_addr(writer_addr), .writer_data(writer_data),
        .resp_valid(resp_valid), .resp_last(resp_last), .resp_data(resp_data), .resp_ready(resp_ready),
        .error_overflow_o(), .error_underflow_o(), .error_clear_i(1'b0),
        .sdram_addr(SDRAM_ADDR), .sdram_ba(SDRAM_BA), .sdram_cs_n(SDRAM_CS_N),
        .sdram_ras_n(SDRAM_RAS_N), .sdram_cas_n(SDRAM_CAS_N), .sdram_we_n(SDRAM_WE_N),
        .sdram_dq(SDRAM_DQ), .sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}), .sdram_cke(SDRAM_CKE)
    );

    // Pripojenie hodín na fyzický pin SDRAM
    assign SDRAM_CLK = clk_100mhz_shifted;

    //==========================================================================
    // Vizuálna Spätná Väzba Testu
    //==========================================================================

    // --- Priradenie LED diód ---
    assign LED[0] = pass_led; // Zelená pre úspech
    assign LED[1] = fail_led; // Červená pre zlyhanie
    assign LED[2] = busy_led; // Žltá počas testu
    assign LED[5:3] = 3'b0;   // Zvyšok vypnutý

    // --- Priradenie 7-segmentového displeja ---
    // Zobrazíme stav FSM na prvej číslici sprava
    assign SMG_DIG = 3'b110; // Aktivácia prvej číslice (pre spoločnú anódu)

    // Potrebujeme dekodér, ktorý prevedie 4-bitové číslo stavu na 7-segmentový kód
    seven_seg_decoder seg_decoder_inst (
        .hex_i(test_state), // 4-bitový stav z testera
        .seg_o(SMG_SEG)     // 8-bitový výstup na segmenty
    );

    //==========================================================================
    // Nepoužité výstupy (nastavíme na bezpečnú hodnotu)
    //==========================================================================
    assign VGA_R = 0; assign VGA_G = 0; assign VGA_B = 0;
    assign VGA_HS = 1; assign VGA_VS = 1; // Neaktívne hodnoty
    assign HDMI_P_J11 = 4'b0;

endmodule

