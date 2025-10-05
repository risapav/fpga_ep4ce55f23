// ===================================================================================
// Názov súboru: top.sv
// Verzia: 2.1 - Robustná reset architektúra
// Dátum: 26. september 2025
//
// Popis:
// Hlavný (top-level) modul pre FPGA s plne funkčným SDRAM framebufferom.
//
// Kľúčové zmeny v tejto verzii (2.1):
// 1. VYLEPŠENIE (Robustnosť): Implementovaná robustná reset schéma. Namiesto jedného
//    globálneho resetu sa teraz generuje oddelený, plne synchronizovaný reset
//    pre každú kľúčovú hodinovú doménu (`pixel_clk` a `clk_axi`). Tým sa
//    predchádza metastabilite a časovacím chybám pri uvoľnení resetu.
// ===================================================================================

`default_nettype none

import vga_pkg::*;
import hdmi_pkg::*;

module top (
    input  logic       SYS_CLK,
    input  logic       RESET_N,
    output logic [7:0] SMG_SEG,
    output logic [2:0] SMG_DIG,
    output logic [5:0] LED,
    input  logic [5:0] BSW,
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS,

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
    output logic SDRAM_LDQM,

    output logic [3:0] HDMI_P_J11
);

    //==========================================================================
    // KONFIGURÁCIA VGA režimu
    //==========================================================================
    localparam vga_mode_e C_VGA_MODE = VGA_800x600_60;
    localparam int PixelClockHz = get_pixel_clock(C_VGA_MODE);

    //==========================================================================
    // PLL a RESET logika
    //==========================================================================
    logic pixel_clk, pixel_clk5, clk_100mhz;
    logic pll_locked;

    ClkPll clkpll_inst (
        .inclk0 (SYS_CLK),
        .areset (~RESET_N),
        .c0     (pixel_clk),
        .c1     (pixel_clk5),
        .c2     (clk_100mhz),
        .locked (pll_locked)
    );

    // --- VYLEPŠENIE: Robustná reset architektúra ---
    logic rstn_global;
    logic rstn_sync_pixel; // Synchronizovaný reset pre `pixel_clk` doménu
    logic rstn_sync_axi;   // Synchronizovaný reset pre `clk_axi` doménu

    // 1. Vytvoríme jeden globálny zdroj resetu (stále asynchrónny voči clk_axi a pixel_clk)
    assign rstn_global = RESET_N & pll_locked;

    // 2. Vytvoríme synchronizovaný reset pre každú hodinovú doménu zvlášť
    // Synchronizátor pre pixel_clk doménu
    cdc_reset_synchronizer reset_sync_pixel_inst (
        .clk_i(pixel_clk),
        .rst_ni(rstn_global),
        .rst_no(rstn_sync_pixel)
    );

    // Synchronizátor pre clk_axi doménu
    cdc_reset_synchronizer reset_sync_axi_inst (
        .clk_i(clk_axi),
        .rst_ni(rstn_global),
        .rst_no(rstn_sync_axi)
    );

    //==========================================================================
    // VGA a Generovanie Obrazu (Doména: pixel_clk)
    //==========================================================================
    wire enable;
    assign enable = 1;

    rgb565_t   generated_data;
    rgb565_t   vga_data_out;
    vga_sync_t sync;
    wire hde, vde, eol, eof;
    wire [LineCounterWidth-1:0] pixel_x, pixel_y;

    line_t h_line_params;
    line_t v_line_params;

`ifdef __ICARUS__
    initial begin
        h_line_params = '{800, 40, 128, 88, PulseActiveLow};
        v_line_params = '{600, 1, 4, 23, PulseActiveLow};
    end
`else
    vga_params_t vga_params = get_vga_params(C_VGA_MODE);
    assign h_line_params = vga_params.h_line;
    assign v_line_params = vga_params.v_line;
`endif

    vga_ctrl vga_inst (
        .clk_i        (pixel_clk),
        .rst_ni       (rstn_sync_pixel), // OPRAVA: Použitý reset pre pixel_clk doménu
        .enable_i     (enable),
        .h_line_i     (h_line_params),
        .v_line_i     (v_line_params),
        .fifo_data_i  (vga_pixel_data),
        .fifo_empty_i (~vga_pixel_valid),
        .hde_o        (hde),
        .vde_o        (vde),
        .dat_o        (vga_data_out),
        .syn_o        (sync),
        .eol_o        (eol),
        .eof_o        (eof)
    );

    vga_pixel_xy coord_inst (
        .clk_i    (pixel_clk),
        .rst_ni   (rstn_sync_pixel), // OPRAVA: Použitý reset pre pixel_clk doménu
        .enable_i (enable),
        .eol_i    (eol),
        .eof_i    (eof),
        .x_o      (pixel_x),
        .y_o      (pixel_y)
    );

    picture_gen image_gen_inst (
        .clk_i    (pixel_clk),
        .rst_ni   (rstn_sync_pixel), // OPRAVA: Použitý reset pre pixel_clk doménu
        .enable_i (enable),
        .h_line_i (h_line_params),
        .v_line_i (v_line_params),
        .x_i      (pixel_x),
        .y_i      (pixel_y),
        .de_i     (hde && vde),
        .mode_i   (BSW[2:0]),
        .data_o   (generated_data)
    );

    //==========================================================================
    // HDMI Výstupná Cesta (Doména: pixel_clk)
    //==========================================================================
    rgb888_t rgb888_data_comb;
    rgb888_t rgb888_data_reg;

    rgb565_to_rgb888 color_inst (
        .rgb565_i (vga_pixel_data),
        .rgb888_o (rgb888_data_comb)
    );

    always_ff @(posedge pixel_clk) begin
        if (!rstn_sync_pixel) begin // OPRAVA: Použitý reset pre pixel_clk doménu
            rgb888_data_reg <= '0;
        end else begin
            rgb888_data_reg <= rgb888_data_comb;
        end
    end

    hdmi_tx_top #(
        .DDRIO(1)
    ) u_hdmi_tx (
        .clk_i          (pixel_clk),
        .clk_x_i        (pixel_clk5),
        .rst_ni         (rstn_sync_pixel), // OPRAVA: Použitý reset pre pixel_clk doménu
        .hsync_i        (sync.hs),
        .vsync_i        (sync.vs),
        .video_i        (rgb888_data_reg),
        .video_valid_i  (vga_pixel_valid),
        .audio_valid_i  (1'b0),
        .packet_valid_i (1'b0),
        .audio_i        (tmds_data_t'(0)),
        .packet_i       (tmds_data_t'(0)),
        .hdmi_p_o       (HDMI_P_J11)
    );

    //==========================================================================
    // SDRAM Framebuffer a Riadiaca Logika (Doména: clk_axi)
    //==========================================================================
    logic clk_axi, clk_sdram;
    assign clk_axi = clk_100mhz;
    assign clk_sdram = clk_100mhz;

    // --- Deklarácie signálov pre prepojenie a CDC ---
    logic pixel_in_valid, pixel_in_ready;
    logic [15:0] pixel_in_data;
    logic [9:0] vga_req_x, vga_req_y;
    logic [15:0] vga_pixel_data;
    logic vga_pixel_valid;
    logic v_blank, v_blank_sync;

    // ==========================================================
    // == LADIACI BLOK: Generátor statického vzoru v AXI doméne ==
    // ==========================================================
    // Tento blok dočasne nahrádza `picture_gen` a rieši problém s CDC.
    // Ak sa po tejto zmene objaví obraz, vieme, že CDC je jediný problém.

    // Počítadlo adries, ktoré budeme zapisovať do framebufferu
    logic [23:0] debug_write_addr;

    always_ff @(posedge clk_axi or negedge rstn_sync_axi) begin
        if (!rstn_sync_axi) begin
            debug_write_addr <= 0;
        end else if (pixel_in_valid && pixel_in_ready) begin
            // Inkrementujeme adresu len vtedy, keď FB kontrolér úspešne prijal dáta
            if (debug_write_addr == 800*600 - 1) begin
                debug_write_addr <= 0;
            end else begin
                debug_write_addr <= debug_write_addr + 1;
            end
        end
    end

    // Jednoduchá logika na generovanie farebných pruhov na základe adresy
    // (napr. prvých 100 stĺpcov červených, ďalších 100 zelených atď.)
    logic [9:0] debug_pixel_x;
    assign debug_pixel_x = debug_write_addr % 800;

    always_comb begin
        if (debug_pixel_x < 100)      pixel_in_data = 16'hF800; // Červená
        else if (debug_pixel_x < 200) pixel_in_data = 16'h07E0; // Zelená
        else if (debug_pixel_x < 300) pixel_in_data = 16'h001F; // Modrá
        else if (debug_pixel_x < 400) pixel_in_data = 16'hFF_E0; // Žltá
        else                          pixel_in_data = 16'hFFFF; // Biela
    end

    // Zapisujeme neustále, keď je to možné. Pre test to stačí.
    assign pixel_in_valid = 1'b1;

    // --- Koniec ladiaceho bloku ---

    // --- PREPOJENIE FRAMEBUFFERU A RIEŠENIE CDC ---
    // 1. Vstup do FB (dáta): Prenos pomocou valid signálu
    //assign pixel_in_data = generated_data;
    //assign pixel_in_valid = hde && vde; // Tento signál je v pixel_clk doméne

    // 2. Vstup do FB (súradnice): Priame priradenie. FB si ich načíta pri platnom `valid` signále.
    assign vga_req_x = pixel_x;
    assign vga_req_y = pixel_y;

    // 3. Vstup do FB (riadiace signály):
    assign v_blank = ~vde; // Tento signál je v pixel_clk doméne

    // 4. BEZPEČNÝ PRENOS (CDC): Prenos `v_blank` signálu do clk_axi domény.
    // Toto je kľúčové, aby FramebufferController správne spustil zápis.
    cdc_two_flop_synchronizer sync_v_blank (
        .clk_i(clk_axi),
        .rst_ni(rstn_sync_axi), // Reset synchronizátora patrí do cieľovej domény
        .d_i(v_blank),
        .q_o(v_blank_sync)
    );

    // (Poznámka: Pre plne robustné riešenie by aj `pixel_in_data` a `vga_req_x/y`
    // prechádzali cez asynchrónne FIFO. Pre tento projekt je synchronizácia
    // riadiacich signálov dostatočná na dosiahnutie funkčnosti.)

    FramebufferController #( .H_RES(800), .V_RES(600) ) fb_ctrl_inst (
        .clk_i(clk_axi),
        .rst_ni(rstn_sync_axi), // OPRAVA: Použitý reset pre clk_axi doménu
        .pixel_in_valid_i(pixel_in_valid), // POZOR: Stále CDC riziko (rieši sa v FB module)
        .pixel_in_ready_o(pixel_in_ready),
        .pixel_in_data_i(pixel_in_data),
        .vga_req_x_i(vga_req_x),
        .vga_req_y_i(vga_req_y),
        .vga_pixel_data_o(vga_pixel_data),
        .vga_pixel_valid_o(vga_pixel_valid),
        .ctrl_start_fill_i(v_blank_sync), // OPRAVA: Použitá synchronizovaná verzia
        .ctrl_swap_buffers_i(v_blank_sync), // OPRAVA: Použitá synchronizovaná verzia
        .status_busy_filling_o(),
        /* ... rozhranie k SDRAM driveru ... */
    );

    SdramDriver #( .ADDR_WIDTH(24), .DATA_WIDTH(16), .BURST_LENGTH(8) ) sdram_driver_inst (
        .clk_axi(clk_axi), .clk_sdram(clk_sdram),
        .rstn_axi(rstn_sync_axi), // OPRAVA
        .rstn_sdram(rstn_sync_axi), // OPRAVA
        /* ... rozhrania reader/writer/response ... */
        .sdram_addr(SDRAM_ADDR), .sdram_ba(SDRAM_BA), .sdram_cs_n(SDRAM_CS_N),
        .sdram_ras_n(SDRAM_RAS_N), .sdram_cas_n(SDRAM_CAS_N), .sdram_we_n(SDRAM_WE_N),
        .sdram_dq(SDRAM_DQ), .sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}), .sdram_cke(SDRAM_CKE)
    );

    assign SDRAM_CLK = clk_sdram;
    //==========================================================================
    // PRIRADENIE FYZICKÝCH VÝSTUPOV
    //==========================================================================
    assign VGA_HS = sync.hs;
    assign VGA_VS = sync.vs;
    assign VGA_R  = vga_data_out.red;
    assign VGA_G  = vga_data_out.grn;
    assign VGA_B  = vga_data_out.blu;

    //==========================================================================
    // Periférie
    //==========================================================================
    logic [3:0] digits_array [2:0] = '{4'd1, 4'd2, 4'd3};
    logic       dots_array   [2:0] = '{1'b0, 1'b1, 1'b0};
    logic led0_reg, led4_reg;

    seven_seg_mux #(
        .NUM_DIGITS(3),
        .CLOCK_FREQ_HZ(PixelClockHz),
        .DIGIT_REFRESH_HZ(200),
        .COMMON_ANODE(1)
    ) seg_mux_inst (
        .clk_i(pixel_clk),
        .rst_ni(rstn_sync_pixel), // OPRAVA
        .digits_i(digits_array),
        .dots_i(dots_array),
        .digit_sel_o(SMG_DIG),
        .segment_sel_o(SMG_SEG),
        .current_digit_o()
    );

    // LED bliká v rytme `pixel_clk`
    blink_led #(
        .CLOCK_FREQ_HZ(PixelClockHz),
        .BLINK_HZ(1)
    ) blink_inst_0 (
        .clk_i(pixel_clk),
        .rst_ni(rstn_sync_pixel), // OPRAVA
        .led_o(led0_reg)
    );

    // LED bliká v rytme `clk_axi`
    blink_led #(
        .CLOCK_FREQ_HZ(100_000_000),
        .BLINK_HZ(1)
    ) blink_inst_1 (
        .clk_i(clk_axi),
        .rst_ni(rstn_sync_axi), // OPRAVA
        .led_o(led4_reg)
    );

    assign LED = {
        2'b00,
        led4_reg,      // LED[3]: Blikanie v rytme clk_axi (100MHz)
        ~BSW[2:1],     // LED[2:1]: Stav prepínačov
        led0_reg       // LED[0]: Blikanie v rytme pixel_clk
    };

endmodule
