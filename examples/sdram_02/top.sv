// ===================================================================================
// Názov súboru: top.sv
// Verzia: 4.0 - Finálna architektúra s plnou integráciou Framebufferu
// Dátum: 6. október 2025
//
// Popis:
// Finálny top-level modul, ktorý integruje generátor obrazu, framebuffer
// so SDRAM a VGA výstupnú cestu. Architektúra je opravená na základe
// detailnej analýzy pre robustné prechody medzi hodinovými doménami (CDC)
// a správne prepojenie AXI-Stream rozhraní.
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
    output logic SDRAM_LDQM
);

    //==========================================================================
    // KONFIGURÁCIA, PLL a RESET
    //==========================================================================
    localparam vga_mode_e C_VGA_MODE = VGA_800x600_60;
    localparam int H_RES = get_h_res(C_VGA_MODE);
    localparam int V_RES = get_v_res(C_VGA_MODE);
    localparam int PixelClockHz = get_pixel_clock(C_VGA_MODE);

    logic pixel_clk, pixel_clk5, clk_100mhz, clk_100mhz_shifted;
    logic pll_locked, rstn_global, rstn_sync_pixel, rstn_sync_axi;
    logic clk_axi;

    assign clk_axi = clk_100mhz;

    ClkPll clkpll_inst (
        .inclk0(SYS_CLK),
        .areset(~RESET_N),
        .c0(pixel_clk),
        .c1(pixel_clk5),
        .c2(clk_100mhz),
        .c3(clk_100mhz_shifted),
        .locked(pll_locked)
    );
    assign rstn_global = RESET_N & pll_locked;
    cdc_reset_synchronizer reset_sync_pixel_inst(.clk_i(pixel_clk), .rst_ni(rstn_global), .rst_no(rstn_sync_pixel));
    cdc_reset_synchronizer reset_sync_axi_inst(.clk_i(clk_axi), .rst_ni(rstn_global), .rst_no(rstn_sync_axi));

    //==========================================================================
    // Deklarácie Signálov
    //==========================================================================
    // --- Signály pre prepojenie FB a SDRAM Drivera ---
    logic sdram_writer_valid, sdram_writer_ready;
    logic [23:0] sdram_writer_addr;
    logic [15:0] sdram_writer_data;
    logic sdram_reader_valid, sdram_reader_ready;
    logic [23:0] sdram_reader_addr;
    logic sdram_resp_valid, sdram_resp_last, sdram_resp_ready;
    logic [15:0] sdram_resp_data;

    // --- Signály pre VGA cestu (pixel_clk doména) ---
    vga_sync_t vga_sync;
    wire hde, vde;
    logic [9:0] pixel_x, pixel_y;
    rgb565_t vga_rgb_out;

    // --- Signály pre CDC (prechod medzi doménami) ---
    logic [9:0] pixel_x_sync, pixel_y_sync;
    logic v_blank, v_blank_sync;

// cieľ projektu:
// axis_picture_generator → FramebufferController → SdramDriver
//                                           ↓
//                                       axis_to_vga → VGA

    //==========================================================================
    // AXI4-Stream Rozhrania
    //==========================================================================
    // OPRAVA: Dve oddelené AXI4-Stream rozhrania pre každý dátový tok.

    // 1. Rozhranie pre tok: axis_picture_generator -> FramebufferController
    axi4s_if #(.DATA_WIDTH(16), .USER_WIDTH(1)) axis_gen_if (.ACLK(clk_axi), .ARESETn(rstn_sync_axi));

    // 2. Rozhranie pre tok: FramebufferController -> axis_to_vga
    axi4s_if #(.DATA_WIDTH(16), .USER_WIDTH(1)) axis_fb_if (.ACLK(clk_axi), .ARESETn(rstn_sync_axi));


    //==========================================================================
    // Inštancie Modulov
    //==========================================================================

    // --- 1. Generátor Obrazu (produkuje AXI-Stream) ---
    axis_picture_generator #( .H_RES(H_RES), .V_RES(V_RES) )
    u_picture_generator (
        .clk_i(clk_axi), .rst_ni(rstn_sync_axi),
        .mode_i(BSW[2:0]),
        .m_axis(axis_gen_if) // Pripojenie na prvé AXI rozhranie
    );

logic fb_is_reading; // Ladiaci signál z framebufferu
logic fb_fifo_full;  // Ladiaci signál z framebufferu

    // --- 2. Framebuffer Controller (zapisuje/číta z SDRAM) ---
    FramebufferController #( .H_RES(H_RES), .V_RES(V_RES) )
    fb_ctrl_inst (
        .clk_i(clk_axi), .rst_ni(rstn_sync_axi),
        // Vstupná strana (prijíma dáta z generátora)
        .pixel_in_valid_i(axis_gen_if.TVALID),
        .pixel_in_ready_o(axis_gen_if.TREADY),
        .pixel_in_data_i(axis_gen_if.TDATA),
        // Výstupná strana (posiela dáta do VGA premosťovača)
        .vga_pixel_valid_o(axis_fb_if.TVALID),
//        .vga_pixel_ready_i(axis_fb_if.TREADY),
        .vga_pixel_data_o(axis_fb_if.TDATA),
        // Požiadavky na čítanie z VGA domény (synchronizované)
        .vga_req_x_i(pixel_x_sync),
        .vga_req_y_i(pixel_y_sync),
        // Riadenie bufferov
    .ctrl_start_fill_i(1'b0), // OPRAVA: Zápis je natvrdo vypnutý
    .ctrl_swap_buffers_i(v_blank_sync), // Prepínanie bufferov necháme aktívne
        // Rozhranie k SDRAM Driveru
        .sdram_writer_valid_o(sdram_writer_valid),
        .sdram_writer_ready_i(sdram_writer_ready),
        .sdram_writer_addr_o(sdram_writer_addr),
        .sdram_writer_data_o(sdram_writer_data),

        .sdram_reader_valid_o(sdram_reader_valid),
        .sdram_reader_ready_i(sdram_reader_ready),
        .sdram_reader_addr_o(sdram_reader_addr),

        .sdram_resp_valid_i(sdram_resp_valid),
        .sdram_resp_last_i(sdram_resp_last),
        .sdram_resp_data_i(sdram_resp_data),
        .sdram_resp_ready_o(sdram_resp_ready),

        .debug_fifo_full_o(fb_fifo_full), // Ladiaci výstup
        .status_reading_o(fb_is_reading) // Pripojte nový ladiaci výstup
    );

    // --- 3. SDRAM Driver ---
    SdramDriver sdram_driver_inst (
        .clk_axi(clk_axi),
        .clk_sdram(clk_100mhz),
        .rstn_axi(rstn_sync_axi),
        .rstn_sdram(rstn_sync_axi),
        .reader_valid(sdram_reader_valid), .reader_ready(sdram_reader_ready), .reader_addr(sdram_reader_addr),
        .writer_valid(sdram_writer_valid), .writer_ready(sdram_writer_ready),
        .writer_addr(sdram_writer_addr), .writer_data(sdram_writer_data), .writer_dqm_i(2'b00),
        .resp_valid(sdram_resp_valid), .resp_last(sdram_resp_last), .resp_data(sdram_resp_data), .resp_ready(sdram_resp_ready),
        .error_overflow_o(), .error_underflow_o(), .error_clear_i(1'b0),
        .sdram_addr(SDRAM_ADDR), .sdram_ba(SDRAM_BA), .sdram_cs_n(SDRAM_CS_N),
        .sdram_ras_n(SDRAM_RAS_N), .sdram_cas_n(SDRAM_CAS_N), .sdram_we_n(SDRAM_WE_N),
        .sdram_dq(SDRAM_DQ), .sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}), .sdram_cke(SDRAM_CKE)
    );
    assign SDRAM_CLK = clk_100mhz_shifted; // Alebo fázovo posunutý variant

    // --- 4. AXI -> VGA Premosťovač (teraz prijíma dáta z framebufferu) ---
    axis_to_vga #( .C_VGA_MODE(C_VGA_MODE) )
    u_axis_to_vga (
        .axi_clk_i(clk_axi), .axi_rst_ni(rstn_sync_axi),
        .pix_clk_i(pixel_clk), .pix_rst_ni(rstn_sync_pixel),
        .s_axis(axis_fb_if), // Pripojenie na druhé AXI rozhranie
        .vga_data_o(vga_rgb_out), .vga_sync_o(vga_sync), .hde_o(hde), .vde_o(vde)
    );

    // --- 5. VGA Generátor súradníc (beží v pixel_clk doméne) ---
    vga_pixel_xy #(
      .MAX_COUNTER_H(H_RES),
      .MAX_COUNTER_V(V_RES)
      ) coord_inst (
        .clk_i(pixel_clk),
        .rst_ni(rstn_sync_pixel),
        .enable_i(1'b1),
        .eol_i(~hde),
        .eof_i(~vde),
        .x_o(pixel_x),
        .y_o(pixel_y)
    );

    // --- CDC (Cross-Domain Crossing) Signály ---
    cdc_two_flop_synchronizer #(.WIDTH(10)) sync_x(.clk_i(clk_axi), .rst_ni(rstn_sync_axi), .d_i(pixel_x), .q_o(pixel_x_sync));
    cdc_two_flop_synchronizer #(.WIDTH(10)) sync_y(.clk_i(clk_axi), .rst_ni(rstn_sync_axi), .d_i(pixel_y), .q_o(pixel_y_sync));
    assign v_blank = ~vde;
    cdc_two_flop_synchronizer #(.WIDTH(1)) sync_v_blank(.clk_i(clk_axi), .rst_ni(rstn_sync_axi), .d_i(v_blank), .q_o(v_blank_sync));

    // --- Fyzické Výstupy a Periférie ---
    assign VGA_HS = vga_sync.hs; assign VGA_VS = vga_sync.vs;
    assign VGA_R  = vga_rgb_out.red; assign VGA_G  = vga_rgb_out.grn; assign VGA_B  = vga_rgb_out.blu;


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

//  assign LED = {1'b1, fb_fifo_full, fb_is_reading, pixel_y_sync[2:1], led0_reg};

  assign LED[0] = led0_reg;
  assign LED[1] = pixel_y_sync[1];
  assign LED[2] = pixel_y_sync[2];

  assign LED[3] = fb_is_reading;
  assign LED[4] = fb_fifo_full;

endmodule

