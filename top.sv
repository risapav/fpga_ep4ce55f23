// ===================================================================================
// Názov súboru: top.sv
// Verzia: 4.29 - Párová LED diagnostika (J10 / ~J10)
// Dátum: 28. október 2025
//
// Popis:
// Top-level modul s plne zapojenou pipeline (Generátor -> FB -> FIFO -> VGA)
// pre ladenie 'framebuffer_ctrl' v režime 'NORMAL'.
//
// Zmeny vo verzii 4.29:
// - Obnovená diagnostika LED[5:0] pre AXI handshake.
// - Implementovaná párová diagnostika na LED_J10 (FB_Stav) a
//   LED_J11 (~FB_Stav) pre lepšiu vizuálnu kontrolu.
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

    // Interný DQM signál
    logic [sdram_pkg::DATA_WIDTH/8-1:0] sdram_dqm_internal;
    // Pripojenie DQM (spojenie UDQM a LDQM do jedného vektora)
    assign {SDRAM_UDQM, SDRAM_LDQM} = sdram_dqm_internal;


    // ==========================================================================
    // ==                        HODINY A RESETY (SPOLOČNÉ)                      ==
    // ==========================================================================
    logic clk_0, clk_1, clk_2, clk_3;
    logic pll_locked, rstn_global;
    logic rstn_sync_0, rstn_sync_1, rstn_sync_2, rstn_sync_3;

    // POZNÁMKA: Predpokladá sa existencia modulu 'ClkPll'
    ClkPll clkpll_inst (
      .inclk0(SYS_CLK), .areset(~RESET_N),
      // c0=PixelClk, c2=AxiClk, c3=AxiClk shifted
      .c0(clk_0), .c1(clk_1), .c2(clk_2), .c3(clk_3),
      .locked(pll_locked)
      );

    assign rstn_global = RESET_N & pll_locked;

    cdc_reset_synchronizer #( .WIDTH(1), .STAGES(2), .REGISTERED_OUT(1) ) reset_sync_inst0 (
      .clk_i(clk_0), .rst_ni(rstn_global), .rst_no(rstn_sync_0)
      );
    cdc_reset_synchronizer #( .WIDTH(1), .STAGES(2), .REGISTERED_OUT(1) ) reset_sync_inst1 (
      .clk_i(clk_1), .rst_ni(rstn_global), .rst_no(rstn_sync_1)
      );
    cdc_reset_synchronizer #( .WIDTH(1), .STAGES(2), .REGISTERED_OUT(1) ) reset_sync_inst2 (
      .clk_i(clk_2), .rst_ni(rstn_global), .rst_no(rstn_sync_2)
      );
    cdc_reset_synchronizer #( .WIDTH(1), .STAGES(2), .REGISTERED_OUT(1) ) reset_sync_inst3 (
      .clk_i(clk_3), .rst_ni(rstn_global), .rst_no(rstn_sync_3)
      );

    // ==========================================================================
    // ==                        VIDEO PIPELINE S FRAMEBUFFEROM                 ==
    // ==========================================================================
    // Tento blok sa v tejto verzii nepoužíva, ale je tu ponechaný,
    // ak by sme chceli v budúcnosti implementovať podmienenú kompiláciu.
    // generate
    //     if (CTestMode == MODE_VIDEO_PIPELINE) begin : gen_video_pipeline

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
      .USER_WIDTH(axi_pkg::AXI_TUSER_WIDTH )
      ) gen_to_fb_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));

    // Framebuffer -> CDC FIFO (clk_2)
    axi4s_if #(
      .DATA_WIDTH(axi_pkg::AXI_TDATA_WIDTH),
      .USER_WIDTH(axi_pkg::AXI_TUSER_WIDTH )
      ) fb_to_fifo_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));

    // CDC FIFO -> VGA (clk_0)
    axi4s_if #(
      .DATA_WIDTH(axi_pkg::AXI_TDATA_WIDTH),
      .USER_WIDTH(axi_pkg::AXI_TUSER_WIDTH )
      ) fifo_to_vga_if (.ACLK(clk_0), .ARESETn(rstn_sync_0));

    // --- Signály pre VGA a Diagnostiku ---
    localparam int CFifoDepthBits = 8; // Musí zodpovedať FIFO
    localparam int CPtrWidth      = CFifoDepthBits + 1;

    rgb565_t vga_rgb;
    logic vga_hde;
    // logic vga_underrun; // Odstránený, keďže axis_to_vga ho už neposkytuje
    logic cdc_wr_overflow, cdc_rd_underflow;
    logic cdc_internal_rd_empty, cdc_internal_wr_full;
    // Signály pre celé pointery
    logic [CPtrWidth-1:0] local_wr_ptr_gray, local_rd_ptr_gray;
    logic [CPtrWidth-1:0] sync_wr_ptr_gray, sync_rd_ptr_gray;
    // NOVÉ: Interné signály pre pripojenie FB debug výstupov
    logic [7:0] fb_debug_0_internal;
    logic [7:0] fb_debug_1_internal;

    // --- Inštancia 1: Generátor Obrázkov ---
    axis_picture_generator #(
      .H_RES(CHAct),
      .V_RES(CVAct)
      ) u_axis_picture_generator (
        .clk_i(clk_2),
        .rst_ni(rstn_sync_2),
        .mode_i(BSW[2:0]), // Späť na BSW
        .m_axis(gen_to_fb_if) // Výstup do FB
        );

    // --- Inštancia 2: Framebuffer Kontrolér ---
    framebuffer_ctrl #(
      .FRAME_WIDTH(CHAct),
      .FRAME_HEIGHT(CVAct),
      .C_OP_MODE(framebuffer_pkg::NORMAL) // Späť na NORMAL
      ) u_framebuffer (
        .clk(clk_2),
        .clk_sh(clk_3),
        .rstn(rstn_sync_2),
        .s_axis(gen_to_fb_if), // Pripojenie celého rozhrania
        .m_axis(fb_to_fifo_if), // Pripojenie celého rozhrania
        .sdram_dq(SDRAM_DQ),
        .sdram_addr(SDRAM_ADDR),
        .sdram_ba(SDRAM_BA),
        .sdram_cas_n(SDRAM_CAS_N),
        .sdram_cke(SDRAM_CKE),
        .sdram_clk(SDRAM_CLK),
        .sdram_cs_n(SDRAM_CS_N),
        .sdram_we_n(SDRAM_WE_N),
        .sdram_ras_n(SDRAM_RAS_N),
        .sdram_dqm(sdram_dqm_internal), // Pripojenie interného DQM
        .debug_led_0_o(fb_debug_0_internal),
        .debug_led_1_o(fb_debug_1_internal)
    );

    // --- Inštancia 3: AXI Clock Domain Crossing (CDC) FIFO ---
    axis_cdc_fifo #(
        .DATA_WIDTH     ( axi_pkg::AXI_TDATA_WIDTH ),
        .USER_WIDTH     ( axi_pkg::AXI_TUSER_WIDTH  ),
        .FIFO_DEPTH_BITS( CFifoDepthBits )
    ) u_axis_cdc_fifo (
      .s_clk_i(clk_2),
      .s_rst_ni(rstn_sync_2),
      .s_axis(fb_to_fifo_if), // Vstup z FB

      .m_clk_i(clk_0),
      .m_rst_ni(rstn_sync_0),
      .m_axis(fifo_to_vga_if), // Výstup do VGA

      .level_o(),
      .wr_overflow_o(cdc_wr_overflow),
      .rd_underflow_o(cdc_rd_underflow),
      .internal_rd_empty_o(cdc_internal_rd_empty),
      .internal_wr_full_o(cdc_internal_wr_full),
      .local_wr_ptr_gray_o(local_wr_ptr_gray),
      .local_rd_ptr_gray_o(local_rd_ptr_gray),
      .sync_wr_ptr_gray_o (sync_wr_ptr_gray),
      .sync_rd_ptr_gray_o (sync_rd_ptr_gray)
    );

    // --- Inštancia 4: AXI-Stream na VGA Prevodník (Zjednodušený) ---
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
        .s_axis(fifo_to_vga_if), // Vstup z CDC FIFO
        .vga_color_o(vga_rgb), // Pripojenie na vga_rgb
        .vga_hs_o(VGA_HS),
        .vga_vs_o(VGA_VS),
        .hde_o(vga_hde)
    );

    // --- Výstupy ---
    assign VGA_R = vga_rgb.red;
    assign VGA_G = vga_rgb.grn;
    assign VGA_B = vga_rgb.blu;

    // --- NOVÁ PÁROVÁ DIAGNOSTIKA (v4.29) ---
    assign LED[0] = fb_to_fifo_if.TVALID;  // Výstup z FB: VALID
    assign LED[1] = fb_to_fifo_if.TREADY;  // Vstup do FIFO: READY
    assign LED[2] = fifo_to_vga_if.TVALID;  // Výstup z FIFO: VALID
    assign LED[3] = ~LED[0];                // Negácia FB TVALID
    assign LED[4] = ~LED[1];                // Negácia FIFO TREADY In
    assign LED[5] = ~LED[2];                // Negácia FIFO TVALID Out

    // Párová diagnostika pre stav FB
    assign LED_J10 = fb_debug_0_internal;   // Stav FB (BUF_A, BUF_B, ptrs, swap)
    assign LED_J11 = ~fb_debug_0_internal;  // Negovaný stav FB

endmodule

`default_nettype wire

