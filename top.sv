// ===================================================================================
// Názov súboru: top.sv
// Verzia: 4.0 - Refaktorovaný s podporou testovacích režimov
// Dátum: 12. október 2025
//
// Popis:
// Top-level modul s robustným prepínaním medzi operačnými režimami
// pomocou parametra a generate bloku. Umožňuje jednoduché testovanie
// video pipeline a SDRAM rozhrania bez manuálnych zmien v kóde.
//
// ===================================================================================

(* default_nettype = "none" *)

import vga_pkg::*;       // Obsahuje typy VGA, farby a parametre
import axi_pkg::*;       // AXI definície
import axis_streamer_pkg::*; // Typy pre AXI-Stream streamer
import framebuffer_pkg::*;  // Typy a parametre pre framebuffer

module top (
    // ... porty modulu zostávajú nezmenené ...
    //system
    input  logic       SYS_CLK,
    input  logic       RESET_N,
    //vga output
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS,
    //sdram
    inout  wire [15:0] SDRAM_DQ,
    output logic [12:0] SDRAM_ADDR,
    output logic [1:0]  SDRAM_BA,
    output logic        SDRAM_CAS_N,
    output logic        SDRAM_CKE,
    output logic        SDRAM_CLK,
    output logic        SDRAM_CS_N,
    output logic        SDRAM_WE_N,
    output logic        SDRAM_RAS_N,
    output logic        SDRAM_UDQM,
    output logic        SDRAM_LDQM,
    //diagnostika
    output logic [5:0] LED,
    output logic [7:0] LED_J10,
    output logic [7:0] LED_J11,
    //user input
    input  logic [5:0] BSW
);
    // =========================================================================
    // ==                      HLAVNÉ NASTAVENIA A REŽIMY                     ==
    // =========================================================================
    // NOVÉ: Enum pre definíciu testovacích režimov pre lepšiu čitateľnosť
    typedef enum {
        MODE_VIDEO_PIPELINE,      // 0: Plná video pipeline s framebufferom
        MODE_SDRAM_PHYSICAL_TEST, // 1: Cielený test fyzickej SDRAM
        MODE_SDRAM_LOGIC_TEST     // 2: Pôvodný test logiky radiča (s BRAM)
    } test_mode_e;

    // ZMEŇTE REŽIM PREPINANÍM HODNOTY TOHTO PARAMETRA
    localparam test_mode_e C_TEST_MODE = MODE_VIDEO_PIPELINE;

    // Konfigurácia
    localparam vga_mode_e C_VGA_MODE = VGA_800x600_60;
    localparam int H_RES = get_h_res(C_VGA_MODE);
    localparam int V_RES = get_v_res(C_VGA_MODE);
    localparam int PixelClockHz = get_pixel_clock(C_VGA_MODE);
    localparam int AxiClockHz = 100_000_000;
    localparam int C_AXIS_DATA_WIDTH = 16;

    // ==========================================================================
    // ==                        HODINY A RESETY (SPOLOČNÉ)                      ==
    // ==========================================================================
    logic clk_0, clk_1, clk_2, clk_3;
    logic pll_locked, rstn_global, rstn_sync_0, rstn_sync_1, rstn_sync_2, rstn_sync_3;

    ClkPll clkpll_inst (.inclk0(SYS_CLK), .areset(~RESET_N), .c0(clk_0), .c1(clk_1), .c2(clk_2), .c3(clk_3), .locked(pll_locked));
    assign rstn_global = RESET_N & pll_locked;
    cdc_reset_synchronizer reset_sync_inst0 (.clk_i(clk_0), .rst_ni(rstn_global), .rst_no(rstn_sync_0));
    cdc_reset_synchronizer reset_sync_inst1 (.clk_i(clk_1), .rst_ni(rstn_global), .rst_no(rstn_sync_1));
    cdc_reset_synchronizer reset_sync_inst2 (.clk_i(clk_2), .rst_ni(rstn_global), .rst_no(rstn_sync_2));
    cdc_reset_synchronizer reset_sync_inst3 (.clk_i(clk_3), .rst_ni(rstn_global), .rst_no(rstn_sync_3));

    // ==========================================================================
    // ==                   GENERÁTOR PREPÍNANÝCH REŽIMOV                     ==
    // ==========================================================================
    generate
        // ----------------------------------------------------------------------
        // -- REŽIM 0: Plná video pipeline
        // ----------------------------------------------------------------------
        if (C_TEST_MODE == MODE_VIDEO_PIPELINE) begin : gen_video_pipeline
            axi4s_if #(.DATA_WIDTH(C_AXIS_DATA_WIDTH)) gen_to_fb_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));
            axi4s_if #(.DATA_WIDTH(C_AXIS_DATA_WIDTH)) fb_to_vga_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));
            rgb565_t vga_rgb;
            vga_sync_t vga_sync;
            logic hde, vde, fifo_empty, fifo_full;

            axis_picture_generator #(
              .H_RES(H_RES),
              .V_RES(V_RES),
              .TLAST_MODE(FRAME)
              ) u_axis_picture_generator (
                .clk_i(clk_2),
                .rst_ni(rstn_sync_2),
                .mode_i(BSW[2:0]),
                .m_axis(gen_to_fb_if)
                );

            FramebufferController #(
              .FRAME_WIDTH(H_RES),
              .FRAME_HEIGHT(V_RES)
              ) u_framebuffer (
                .clk(clk_2),
                .clk_sh(clk_3),
                .rstn(rstn_sync_2),

                // -- AXI-Stream vstup (napr. z kamery)
                .s_axis_valid(gen_to_fb_if.TVALID),
                .s_axis_ready(gen_to_fb_if.TREADY),
                .s_axis_data(gen_to_fb_if.TDATA),
                .s_axis_last(gen_to_fb_if.TLAST), // Koniec riadku

                // -- AXI-Stream výstup (napr. pre displej)
                .m_axis_valid(fb_to_vga_if.TVALID),
                .m_axis_ready(fb_to_vga_if.TREADY),
                .m_axis_data(fb_to_vga_if.TDATA),
                .m_axis_last(fb_to_vga_if.TLAST),

                // -- SDRAM rozhranie
                .sdram_dq(SDRAM_DQ),
                .sdram_addr(SDRAM_ADDR),
                .sdram_ba(SDRAM_BA),
                .sdram_cas_n(SDRAM_CAS_N),
                .sdram_cke(SDRAM_CKE),
                .sdram_clk(SDRAM_CLK),
                .sdram_cs_n(SDRAM_CS_N),
                .sdram_we_n(SDRAM_WE_N),
                .sdram_ras_n(SDRAM_RAS_N),
                .sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}),
    // -- Diagnostika
                .debug_led_0_o(LED_J10),
                .debug_led_1_o(LED_J11)
            );

            axis_to_vga #(
              .FIFO_DEPTH(4096),
              .C_VGA_MODE(C_VGA_MODE)
              )u_axis_to_vga (
                .axi_clk_i(clk_2),
                .axi_rst_ni(rstn_sync_2),
                .pix_clk_i(clk_0),
                .pix_rst_ni(rstn_sync_0),
                .s_axis(fb_to_vga_if),
                .vga_data_o(vga_rgb),
                .vga_sync_o(vga_sync),
                .hde_o(hde),
                .vde_o(vde),
                .fifo_full_o(fifo_full),
                .fifo_empty_o(fifo_empty)
            );

            assign VGA_HS = vga_sync.hs;
            assign VGA_VS = vga_sync.vs;
            assign VGA_R = vga_rgb.red;
            assign VGA_G = vga_rgb.grn;
            assign VGA_B = vga_rgb.blu;
/*
            assign LED_J10[0] = fifo_empty;
            assign LED_J10[1] = fifo_full;
            assign LED_J10[2] = hde;
            assign LED_J10[3] = vde;
            assign LED_J10[4] = |gen_to_fb_if.TDATA;
*/
        // ----------------------------------------------------------------------
        // -- REŽIM 1: Test fyzickej SDRAM
        // ----------------------------------------------------------------------
        end else if (C_TEST_MODE == MODE_SDRAM_PHYSICAL_TEST) begin : gen_physical_test
            logic [15:0] read_back_data;
            sdram_physical_tester #(
              .DATA_WIDTH(16)
              ) u_sdram_physical_tester (
                .clk_i(clk_2),
                .clk_sh_i(clk_3),
                .rst_ni(rstn_sync_2),
                .leds_o(LED),
                .read_data_o(read_back_data),
                .sdram_addr(SDRAM_ADDR),
                .sdram_ba(SDRAM_BA),
                .sdram_cs_n(SDRAM_CS_N),
                .sdram_ras_n(SDRAM_RAS_N),
                .sdram_cas_n(SDRAM_CAS_N),
                .sdram_we_n(SDRAM_WE_N),
                .sdram_dq(SDRAM_DQ),
                .sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}),
                .sdram_cke(SDRAM_CKE),
                .sdram_clk(SDRAM_CLK)
            );
            assign LED_J11 = read_back_data[15:8];
            assign LED_J10 = read_back_data[7:0];
            assign VGA_HS = 1'b1;
            assign VGA_VS = 1'b1;
            assign VGA_R = '0;
            assign VGA_G = '0;
            assign VGA_B = '0;

        // ----------------------------------------------------------------------
        // -- REŽIM 2: Test logiky SDRAM radiča (s BRAM)
        // ----------------------------------------------------------------------
        end else if (C_TEST_MODE == MODE_SDRAM_LOGIC_TEST) begin : gen_logic_test
            sdram_ctrl_tester u_tester (
              .clk_i(clk_2),
              .clk_sh_i(clk_3),
              .rst_ni(rstn_sync_2),
              .leds_o(LED_J11)
              );

            // Bezpečné zaparkovanie nepoužitých pinov
            assign SDRAM_DQ = 16'hzzzz;
            assign SDRAM_ADDR = '0;
            assign SDRAM_BA = '0;
            assign SDRAM_CS_N = 1'b1;
            assign SDRAM_RAS_N = 1'b1;
            assign SDRAM_CAS_N = 1'b1;
            assign SDRAM_WE_N = 1'b1;
            assign SDRAM_CKE = 1'b0;
            assign SDRAM_CLK = 1'b0;
            assign SDRAM_UDQM = 1'b0;
            assign SDRAM_LDQM = 1'b0;
            assign VGA_HS = 1'b1;
            assign VGA_VS = 1'b1;
            assign VGA_R = '0;
            assign VGA_G = '0;
            assign VGA_B = '0;
        end
    endgenerate

    // =========================================================================
    // ==               DIAGNOSTIKA HODÍN A TLAČIDIEL (SPOLOČNÁ)              ==
    // =========================================================================
    // Blikanie LED pre overenie hodín necháme aktívne vo všetkých režimoch
/*
    blink_led #(.CLOCK_FREQ_HZ(PixelClockHz)) blink_inst_0 (.clk_i(clk_0), .rst_ni(rstn_sync_0), .led_o(LED[0]));
    blink_led #(.CLOCK_FREQ_HZ(1)) blink_inst_1 (.clk_i(clk_1), .rst_ni(rstn_sync_1), .led_o(LED[1])); // Frekvencia clk_1 je neznáma, dáme 1Hz pre test
    blink_led #(.CLOCK_FREQ_HZ(AxiClockHz)) blink_inst_2 (.clk_i(clk_2), .rst_ni(rstn_sync_2), .led_o(LED[2]));
    blink_led #(.CLOCK_FREQ_HZ(AxiClockHz)) blink_inst_3 (.clk_i(clk_3), .rst_ni(rstn_sync_3), .led_o(LED[3]));
    assign LED[4] = ~BSW[1];
    assign LED[5] = ~BSW[2];
*/
endmodule
