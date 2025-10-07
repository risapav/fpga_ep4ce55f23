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
    output logic       VGA_VS
);

  // =========================================================================
  // Lokálne parametre pre VGA režim
  // =========================================================================
  localparam vga_mode_e C_VGA_MODE = VGA_800x600_60;
  localparam int H_RES = get_h_res(C_VGA_MODE);        // Horizontálne rozlíšenie
  localparam int V_RES = get_v_res(C_VGA_MODE);        // Vertikálne rozlíšenie
  localparam int PixelClockHz = get_pixel_clock(C_VGA_MODE);

  localparam int CounterWidthX = $clog2(H_RES);        // Šírka počítadla X
  localparam int CounterWidthY = $clog2(V_RES);        // Šírka počítadla Y
  // =========================================================================
  // Clocks & Reset
  // =========================================================================
  logic pixel_clk, pixel_clk5, clk_100mhz;
  logic pll_locked;
  logic clk_axi;

  logic rstn_global, rstn_sync_pixel, rstn_sync_axi;

  // =========================================================================
  // VGA časovanie
  // =========================================================================
  vga_params_t vga_params;
  line_t h_line_params;
  line_t v_line_params;

  assign vga_params = get_vga_params(C_VGA_MODE);
  assign h_line_params = vga_params.h_line;
  assign v_line_params = vga_params.v_line;

  // =========================================================================
  // Video counters & pixel data
  // =========================================================================
  logic [CounterWidthX-1:0] x_pix;
  logic [CounterWidthY-1:0] y_pix;
  logic de;               // data enable
  logic hde, vde;         // horizontálna a vertikálna enable
  rgb565_t rgb_pixel;     // pixel generovaný picture_gen
  rgb565_t vga_rgb;       // pixel po premosťovači AXI → VGA
  vga_sync_t sync;        // synchronizačné signály HS/VS

  logic enable;
  assign enable = 1'b1;   // generovanie povolené

  // =========================================================================
  // AXI4-Stream interface (slave)
  // =========================================================================

  axi4s_if #(.DATA_WIDTH(16), .USER_WIDTH(1)) s_axis_if     (.ACLK(clk_axi), .ARESETn(rstn_sync_axi));

  // =========================================================================
  // PLL Inštancia pre generovanie pixel_clk a clk_axi
  // =========================================================================
  ClkPll clkpll_inst (
      .inclk0 (SYS_CLK),
      .areset (~RESET_N),
      .c0     (pixel_clk),
      .c1     (pixel_clk5),
      .c2     (clk_100mhz),
      .locked (pll_locked)
  );

  assign rstn_global = RESET_N & pll_locked;
  assign clk_axi      = clk_100mhz; // AXI doména

  // Reset synchronizácia pre rôzne domény
  cdc_reset_synchronizer reset_sync_pixel_inst (
      .clk_i(pixel_clk), .rst_ni(rstn_global), .rst_no(rstn_sync_pixel)
  );

  cdc_reset_synchronizer reset_sync_axi_inst (
      .clk_i(clk_axi), .rst_ni(rstn_global), .rst_no(rstn_sync_axi)
  );

  // =========================================================================
  // Frame streamer - generuje x_pix/y_pix
  // =========================================================================
  axis_picture_generator #(
      .H_RES(H_RES),
      .V_RES(V_RES),
      .DATA_WIDTH(16),
      .USER_WIDTH(1)
  ) u_axis_picture_generator (
    .clk_i(clk_axi),
    .rst_ni(rstn_sync_axi),

    .mode_i(BSW[2:0]),
    .de_i(enable),

    .m_axis(s_axis_if)

  );

  // =========================================================================
  // AXI → VGA premosťovač
  // =========================================================================
  axis_to_vga #(
      .FIFO_DEPTH(4096),
      .C_VGA_MODE(C_VGA_MODE)
  ) u_axis_to_vga (
      .axi_clk_i(clk_axi),
      .axi_rst_ni(rstn_sync_axi),
      .pix_clk_i(pixel_clk),
      .pix_rst_ni(rstn_sync_pixel),
      .s_axis(s_axis_if),
      .vga_data_o(vga_rgb),
      .vga_sync_o(sync),
      .hde_o(hde),
      .vde_o(vde)
  );

  // =========================================================================
  // Priradenie výstupov na fyzické piny
  // =========================================================================
  assign VGA_HS = sync.hs;
  assign VGA_VS = sync.vs;
  assign VGA_R  = vga_rgb.red;
  assign VGA_G  = vga_rgb.grn;
  assign VGA_B  = vga_rgb.blu;

  // =========================================================================
  // LED a 7-segment indikácia (voliteľné, vizuálna kontrola)
  // =========================================================================
  logic [3:0] digits_array [2:0] = '{4'd1, 4'd2, 4'd3};
  logic       dots_array   [2:0] = '{1'b0, 1'b1, 1'b0};
  logic led0_reg, led4_reg;

  seven_seg_mux #(
      .NUM_DIGITS(3), .CLOCK_FREQ_HZ(PixelClockHz), .DIGIT_REFRESH_HZ(200), .COMMON_ANODE(1)
  ) seg_mux_inst (
      .clk_i(pixel_clk), .rst_ni(rstn_sync_pixel),
      .digits_i(digits_array), .dots_i(dots_array),
      .digit_sel_o(SMG_DIG), .segment_sel_o(SMG_SEG), .current_digit_o()
  );

  blink_led #( .CLOCK_FREQ_HZ(PixelClockHz), .BLINK_HZ(1) ) blink_inst_0 (
      .clk_i(pixel_clk), .rst_ni(rstn_sync_pixel), .led_o(led0_reg)
  );

  blink_led #( .CLOCK_FREQ_HZ(100_000_000), .BLINK_HZ(1) ) blink_inst_1 (
      .clk_i(clk_axi), .rst_ni(rstn_sync_axi), .led_o(led4_reg)
  );

  assign LED = {2'b00, led4_reg, ~BSW[2:1], led0_reg};

endmodule

