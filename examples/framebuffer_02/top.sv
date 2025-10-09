// ===================================================================================
// Názov súboru: top.sv
// Verzia: 3.1 - Minimal AXI-Stream → VGA test
// Dátum: 5. október 2025
//
// Popis:
// Upravený top-level modul pre FPGA pre účely testovania AXI-Stream generovaného
// priamo picture_gen modulom a premosťovača axis_to_vga.
// SDRAM a framebuffer logika sú odstránené pre jednoduchý test.
//
// ===================================================================================

(* default_nettype = "none" *)

import vga_pkg::*;       // Obsahuje typy VGA, farby a parametre
import axi_pkg::*;       // AXI definície
import axis_streamer_pkg::*; // Typy pre AXI-Stream streamer

module top (
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
  // nastavenia
  localparam vga_mode_e C_VGA_MODE = VGA_800x600_60;
  localparam int H_RES = get_h_res(C_VGA_MODE);
  localparam int V_RES = get_v_res(C_VGA_MODE);

  localparam int PixelClockHz = get_pixel_clock(C_VGA_MODE);
  localparam int AxiClockHz = 100_000_000;

  localparam int C_AXIS_DATA_WIDTH = 16; // Zmeň šírku iba tu

  //==========================================================================
  // Konfigurácia a PLL
  //==========================================================================
  logic clk_0, clk_1, clk_2, clk_3;
  logic pll_locked, rstn_global, rstn_sync_0, rstn_sync_1, rstn_sync_2, rstn_sync_3;

  ClkPll clkpll_inst (
      .inclk0(SYS_CLK),
      .areset(~RESET_N),
      .c0(clk_0),
      .c1(clk_1),
      .c2(clk_2),
      .c3(clk_3),
      .locked(pll_locked)
  );

  assign rstn_global = RESET_N & pll_locked;
  // cdc reset
  cdc_reset_synchronizer reset_sync_inst0 (.clk_i(clk_0), .rst_ni(rstn_global), .rst_no(rstn_sync_0));
  cdc_reset_synchronizer reset_sync_inst1 (.clk_i(clk_1), .rst_ni(rstn_global), .rst_no(rstn_sync_1));
  cdc_reset_synchronizer reset_sync_inst2 (.clk_i(clk_2), .rst_ni(rstn_global), .rst_no(rstn_sync_2));
  cdc_reset_synchronizer reset_sync_inst3 (.clk_i(clk_3), .rst_ni(rstn_global), .rst_no(rstn_sync_3));

  // =========================================================================
  // AXI4-Stream interface (slave)
  // =========================================================================

 // 1. Z generátora do framebufferu
  axi4s_if #(.DATA_WIDTH(C_AXIS_DATA_WIDTH)) gen_to_fb_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));
  // 2. Z framebufferu do VGA premosťovača
  axi4s_if #(.DATA_WIDTH(C_AXIS_DATA_WIDTH)) fb_to_vga_if (.ACLK(clk_2), .ARESETn(rstn_sync_2));


  // =========================================================================
  // Frame streamer - generuje axi stream
  // =========================================================================

  axis_picture_generator #(
      .H_RES(H_RES),
      .V_RES(V_RES),
      .TLAST_MODE(FRAME) // TLAST sa aktivuje iba na konci celého snímku
  ) u_axis_picture_generator (
      .clk_i(clk_2),
      .rst_ni(rstn_sync_2),

      .mode_i(BSW[2:0]),

      .m_axis(gen_to_fb_if)
  );

  // =========================================================================
  // NOVÝ MODUL: Framebuffer Controller
  // =========================================================================
  framebuffer_ctrl #(
    .H_RES(H_RES),
    .V_RES(V_RES)
  ) u_framebuffer (
      // Hodiny a resety
      .axi_clk_i(clk_2),
      .axi_rst_ni(rstn_sync_2),

      .sdram_clk_i(clk_3),
      .sdram_rst_ni(rstn_sync_3),

      // Streamy
      .s_axis_video_in(gen_to_fb_if),     // Vstup z generátora
      .m_axis_video_out(fb_to_vga_if),    // Výstup do VGA premosťovača

      // Pripojenie na fyzické SDRAM piny
      .SDRAM_DQ(SDRAM_DQ), .SDRAM_ADDR(SDRAM_ADDR), .SDRAM_BA(SDRAM_BA),
      .SDRAM_CAS_N(SDRAM_CAS_N), .SDRAM_CKE(SDRAM_CKE), .SDRAM_CLK(SDRAM_CLK),
      .SDRAM_CS_N(SDRAM_CS_N), .SDRAM_WE_N(SDRAM_WE_N), .SDRAM_RAS_N(SDRAM_RAS_N),
      .SDRAM_UDQM(SDRAM_UDQM), .SDRAM_LDQM(SDRAM_LDQM),

      // Diagnostika
      .debug_led_o(LED_J11)
  );


  // =========================================================================
  // AXI → VGA premosťovač
  // =========================================================================
  rgb565_t vga_rgb;       // VGA RGB výstup
  vga_sync_t vga_sync;    // VGA synchro HS/VS výstup
  logic hde, vde;         // aktívna oblasť
  logic fifo_empty, fifo_full;

  axis_to_vga #(
      .FIFO_DEPTH(4096),
      .C_VGA_MODE(C_VGA_MODE)
  ) u_axis_to_vga (
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

  // --- Pripojenie na fyzické piny VGA ---
  assign VGA_HS = vga_sync.hs;
  assign VGA_VS = vga_sync.vs;
  assign VGA_R  = vga_rgb.red;
  assign VGA_G  = vga_rgb.grn;
  assign VGA_B  = vga_rgb.blu;

// Pripoj hde a vde na diagnostické LED
assign LED_J10[1] = fifo_full;
assign LED_J10[0] = fifo_empty;

  // =========================================================================
  // diagnostika funkčnosti pll a button volieb s výstupom do LED
  // =========================================================================
  blink_led #(.CLOCK_FREQ_HZ(PixelClockHz), .BLINK_HZ(1))
  blink_inst_0 (.clk_i(clk_0), .rst_ni(rstn_sync_0), .led_o(LED[0]));

  blink_led #(.CLOCK_FREQ_HZ(PixelClockHz*5), .BLINK_HZ(1))
  blink_inst_1 (.clk_i(clk_1), .rst_ni(rstn_sync_1), .led_o(LED[1]));

  blink_led #(.CLOCK_FREQ_HZ(AxiClockHz), .BLINK_HZ(1))
  blink_inst_2 (.clk_i(clk_2), .rst_ni(rstn_sync_2), .led_o(LED[2]));

  blink_led #(.CLOCK_FREQ_HZ(AxiClockHz), .BLINK_HZ(1))
  blink_inst_3 (.clk_i(clk_3), .rst_ni(rstn_sync_3), .led_o(LED[3]));

  assign LED[4] = ~BSW[1];
  assign LED[5] = ~BSW[2];

endmodule

