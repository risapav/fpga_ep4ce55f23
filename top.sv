// ===================================================================================
// Názov súboru: top.sv
// Verzia: 4.26 - Rozšírená diagnostika pointerov na LED_J10/J11
// Dátum: 26. október 2025
//
// Popis:
// Top-level modul s dočasne zakomentovaným framebufferom
// pre priame testovanie axis_picture_generator -> axis_cdc_fifo -> axis_to_vga.
//
// Zmeny vo verzii 4.10:
// - Pripojené celé Gray pointery (spodných 8b) z CDC FIFO
//   na LED diódy LED_J10 a LED_J11 pre detailnú diagnostiku.
// - Upravené priradenie LED[5:0].
// ===================================================================================

`default_nettype none

import vga_pkg::*;       // Obsahuje typy VGA, farby a parametre
import axi_pkg::*;       // AXI definície
//import axis_streamer_pkg::*; // Typy pre AXI-Stream streamer
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
    inout  wire [sdram_pkg::DATA_WIDTH-1:0] SDRAM_DQ, // Použitie scope
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0]  SDRAM_ADDR,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] SDRAM_BA,
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

    // Konfigurácia
    localparam vga_mode_e CVgaMode = VGA_800x600_60;
    localparam int CPixelClockHz = get_pixel_clock(CVgaMode);
    localparam int CAxiClockHz = 100_000_000;

    // ==========================================================================
    // ==                        HODINY A RESETY (SPOLOČNÉ)                      ==
    // ==========================================================================
    logic clk_0, clk_1, clk_2, clk_3;
    logic pll_locked, rstn_global, rstn_sync_0, rstn_sync_1, rstn_sync_2, rstn_sync_3;

    // POZNÁMKA: Predpokladá sa existencia modulu 'ClkPll'
    ClkPll clkpll_inst (
      .inclk0(SYS_CLK), .areset(~RESET_N),
      // c0=PixelClk, c2=AxiClk, c3=AxiClk shifted
      .c0(clk_0), .c1(clk_1), .c2(clk_2), .c3(clk_3),
      .locked(pll_locked)
      );

    assign rstn_global = RESET_N & pll_locked;

    cdc_reset_synchronizer reset_sync_inst0 (
      .clk_i(clk_0), .rst_ni(rstn_global), .rst_no(rstn_sync_0)
      );
    cdc_reset_synchronizer reset_sync_inst1 (
      .clk_i(clk_1), .rst_ni(rstn_global), .rst_no(rstn_sync_1)
      );
    cdc_reset_synchronizer reset_sync_inst2 (
      .clk_i(clk_2), .rst_ni(rstn_global), .rst_no(rstn_sync_2)
      );
    cdc_reset_synchronizer reset_sync_inst3 (
      .clk_i(clk_3), .rst_ni(rstn_global), .rst_no(rstn_sync_3)
      );

    // ==========================================================================
    // ==                        VIDEO PIPELINE S FRAMEBUFFEROM                 ==
    // ==========================================================================

    // --- VGA Parametre (načítané z vga_pkg) ---
    localparam int CHAct = get_h_res(CVgaMode);
    localparam int CHFp  = get_h_fp(CVgaMode);
    localparam int CHSp  = get_h_sp(CVgaMode);
    localparam int CHBp  = get_h_bp(CVgaMode);
    localparam bit CHSyncPol = get_h_pol(CVgaMode);
    localparam int CVAct = get_v_res(CVgaMode);
    localparam int CVFp  = get_v_fp(CVgaMode);
    localparam int CVSp  = get_v_sp(CVgaMode);
    localparam int CVBp  = get_v_bp(CVgaMode);
    localparam bit CVSyncPol = get_v_pol(CVgaMode);

    // --- AXI Stream Rozhrania ---
    // Generátor -> Framebuffer (clk_2)
    axi4s_if #(
      .DATA_WIDTH(axi_pkg::AXI_TDATA_WIDTH),
      .USER_WIDTH(axi_pkg::AXI_TUSER_WIDTH)
      ) gen_to_fb_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));

    // Framebuffer -> CDC FIFO (clk_2)
    axi4s_if #(
      .DATA_WIDTH(axi_pkg::AXI_TDATA_WIDTH),
      .USER_WIDTH(axi_pkg::AXI_TUSER_WIDTH)
      ) fb_to_fifo_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));

    // CDC FIFO -> VGA (clk_0)
    axi4s_if #(
      .DATA_WIDTH(axi_pkg::AXI_TDATA_WIDTH),
      .USER_WIDTH(axi_pkg::AXI_TUSER_WIDTH)
      ) fifo_to_vga_if (.ACLK(clk_0), .ARESETn(rstn_sync_0));

    // --- Signály pre VGA a Diagnostiku ---
    localparam int CFifoDepthBits = 8; // Musí zodpovedať FIFO
    localparam int CPtrWidth      = CFifoDepthBits + 1;

    rgb565_t vga_rgb;
    logic vga_hde, vga_underrun;
    logic cdc_wr_overflow, cdc_rd_underflow;
    logic cdc_internal_rd_empty, cdc_internal_wr_full;
    // Signály pre celé pointery
    logic [CPtrWidth-1:0] local_wr_ptr_gray, local_rd_ptr_gray;
    logic [CPtrWidth-1:0] sync_wr_ptr_gray, sync_rd_ptr_gray;

    // --- Inštancia 1: Generátor Obrázkov ---
    axis_picture_generator #(
      .H_RES(CHAct),
      .V_RES(CVAct)
      ) u_axis_picture_generator (
        .clk_i(clk_2),
        .rst_ni(rstn_sync_2),
        .mode_i(BSW[2:0]),
        .m_axis(gen_to_fb_if)
        );

    // --- Inštancia 2: Framebuffer Kontrolér ---
    framebuffer_ctrl #(
      .FRAME_WIDTH(CHAct),
      .FRAME_HEIGHT(CVAct),
      .C_OP_MODE(framebuffer_pkg::NORMAL) // Použitie typu z balíčka
      ) u_framebuffer (
        // Pripojenie explicitných hodín a resetu
        .clk(clk_2),        // Pripojenie AXI hodín
        .clk_sh(clk_3),     // Pripojenie posunutých hodín
        .rstn(rstn_sync_2), // Pripojenie AXI resetu

        // Pripojenie celých AXI rozhraní
        .s_axis(gen_to_fb_if),  // Vstup z Generátora
        .m_axis(fb_to_fifo_if), // Výstup do FIFO

        // SDRAM rozhranie
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
        // Diagnostika
        .debug_led_0_o(LED_J10),
        .debug_led_1_o(LED_J11)
    );


    // --- Inštancia 3: AXI Clock Domain Crossing (CDC) FIFO ---
    axis_cdc_fifo #(
        .DATA_WIDTH     ( axi_pkg::AXI_TDATA_WIDTH ),
        .USER_WIDTH     ( axi_pkg::AXI_TUSER_WIDTH ),
        .FIFO_DEPTH_BITS( CFifoDepthBits )
    ) u_axis_cdc_fifo (
      .s_clk_i(clk_2),
      .s_rst_ni(rstn_sync_2),
      .s_axis(fb_to_fifo_if),

      .m_clk_i(clk_0),
      .m_rst_ni(rstn_sync_0),
      .m_axis(fifo_to_vga_if),

      .level_o(),
      .wr_overflow_o(cdc_wr_overflow),
      .rd_underflow_o(cdc_rd_underflow),
      .internal_rd_empty_o(cdc_internal_rd_empty),
      .internal_wr_full_o(cdc_internal_wr_full),
      // Pripojenie celých pointerov
      .local_wr_ptr_gray_o(local_wr_ptr_gray),
      .local_rd_ptr_gray_o(local_rd_ptr_gray),
      .sync_wr_ptr_gray_o (sync_wr_ptr_gray),
      .sync_rd_ptr_gray_o (sync_rd_ptr_gray)
    );

    // --- Inštancia 4: AXI-Stream na VGA Prevodník ---
    axis_to_vga #(
      .H_ACT ( CHAct ),
      .H_FP  ( CHFp ),
      .H_SP  ( CHSp ),
      .H_BP  ( CHBp ),
      .V_ACT ( CVAct ),
      .V_FP  ( CVFp ),
      .V_SP  ( CVSp ),
      .V_BP  ( CVBp ),
      .H_SYNC_POLARITY ( CHSyncPol ),
      .V_SYNC_POLARITY ( CVSyncPol ),
      .OUTPUT_FORMAT ( 565 ),
      .AXI_DATA_WIDTH ( axi_pkg::AXI_TDATA_WIDTH ),
      .AXI_USER_WIDTH ( axi_pkg::AXI_TUSER_WIDTH )
      ) u_axis_to_vga (
        .clk_i(clk_0),
        .rst_ni(rstn_sync_0),
        .s_axis(fifo_to_vga_if),
        .vga_color_o(vga_rgb),
        .vga_hs_o(VGA_HS),
        .vga_vs_o(VGA_VS),
        .hde_o(vga_hde)

    );

    // --- Výstupy ---
    assign VGA_R = vga_rgb.red;
    assign VGA_G = vga_rgb.grn;
    assign VGA_B = vga_rgb.blu;

endmodule

`default_nettype wire