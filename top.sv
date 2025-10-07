// ===================================================================================
// top.sv - Minimalistický test SDRAM->VGA s FramebufferController
// Verzia: 4.3
// Dátum: 7. október 2025
// ===================================================================================
(* default_nettype = "none" *)

import vga_pkg::*;
import axi_pkg::*;

module top (
    input  logic       SYS_CLK,
    input  logic       RESET_N,
    output logic [4:0] VGA_R,
    output logic [5:0] VGA_G,
    output logic [4:0] VGA_B,
    output logic       VGA_HS,
    output logic       VGA_VS,
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
    output logic [5:0]  LED
);

    //==========================================================================
    // Konfigurácia a PLL
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
    cdc_reset_synchronizer reset_sync_axi_inst  (.clk_i(clk_axi),   .rst_ni(rstn_global), .rst_no(rstn_sync_axi));

    //==========================================================================
    // Signály pre Framebuffer a SDRAM
    //==========================================================================
    logic sdram_reader_valid, sdram_reader_ready;
    logic [23:0] sdram_reader_addr;
    logic sdram_resp_valid, sdram_resp_last, sdram_resp_ready;
    logic [15:0] sdram_resp_data;

    logic fb_is_reading, fb_fifo_full;

    //==========================================================================
    // AXI4-Stream rozhranie
    //==========================================================================
    axi4s_if #(.DATA_WIDTH(16)) axis_fb_if (.ACLK(clk_axi), .ARESETn(rstn_sync_axi));

    //==========================================================================
    // VGA časovanie
    //==========================================================================
    logic hde, vde;
    logic [9:0] pixel_x, pixel_y;
    vga_sync_t vga_sync;
    rgb565_t vga_rgb_out;

    // Pixel coordinates synchronizované do AXI domény
    logic [9:0] pixel_x_sync, pixel_y_sync;
    logic v_blank, v_blank_sync;

    vga_timing_generator vga_timer_inst (
        .clk_i(pixel_clk), .rst_ni(rstn_sync_pixel),
        .sync_o(),
        .hde_o(hde),
        .vde_o(vde),
        .x_o(pixel_x),
        .y_o(pixel_y)
    );

    cdc_two_flop_synchronizer #(.WIDTH(10)) sync_x(.clk_i(clk_axi), .rst_ni(rstn_sync_axi), .d_i(pixel_x), .q_o(pixel_x_sync));
    cdc_two_flop_synchronizer #(.WIDTH(10)) sync_y(.clk_i(clk_axi), .rst_ni(rstn_sync_axi), .d_i(pixel_y), .q_o(pixel_y_sync));
    assign v_blank = ~vde;
    cdc_two_flop_synchronizer #(.WIDTH(1)) sync_v_blank(.clk_i(clk_axi), .rst_ni(rstn_sync_axi), .d_i(v_blank), .q_o(v_blank_sync));

    //==========================================================================
    // FramebufferController (len čítanie)
    //==========================================================================
    FramebufferController #( .H_RES(H_RES), .V_RES(V_RES) )
    fb_ctrl_inst (
        .clk_i(clk_axi), .rst_ni(rstn_sync_axi),
        .pixel_in_valid_i(1'b0),      // zápis vypnutý
        .pixel_in_ready_o(),
        .pixel_in_data_i(16'd0),
        .vga_pixel_valid_o(axis_fb_if.TVALID),
        .vga_pixel_ready_i(axis_fb_if.TREADY),
        .vga_pixel_data_o(axis_fb_if.TDATA),
        .vga_req_x_i(pixel_x_sync),
        .vga_req_y_i(pixel_y_sync),
        .ctrl_start_fill_i(1'b0),
        .ctrl_swap_buffers_i(v_blank_sync),
        .sdram_writer_valid_o(), .sdram_writer_ready_i(1'b0),
        .sdram_writer_addr_o(), .sdram_writer_data_o(),
        .sdram_reader_valid_o(sdram_reader_valid),
        .sdram_reader_ready_i(sdram_reader_ready),
        .sdram_reader_addr_o(sdram_reader_addr),
        .sdram_resp_valid_i(sdram_resp_valid),
        .sdram_resp_last_i(sdram_resp_last),
        .sdram_resp_data_i(sdram_resp_data),
        .sdram_resp_ready_o(sdram_resp_ready),
        .debug_fifo_full_o(fb_fifo_full),
        .status_reading_o(fb_is_reading)
    );

    //==========================================================================
    // SDRAM Driver
    //==========================================================================
    SdramDriver sdram_driver_inst (
        .clk_axi(clk_axi), .clk_sdram(clk_100mhz),
        .rstn_axi(rstn_sync_axi), .rstn_sdram(rstn_sync_axi),
        .reader_valid(sdram_reader_valid), .reader_ready(sdram_reader_ready), .reader_addr(sdram_reader_addr),
        .writer_valid(1'b0), .writer_ready(), .writer_addr(24'd0), .writer_data(16'd0), .writer_dqm_i(2'b00),
        .resp_valid(sdram_resp_valid), .resp_last(sdram_resp_last), .resp_data(sdram_resp_data), .resp_ready(sdram_resp_ready),
        .error_overflow_o(), .error_underflow_o(), .error_clear_i(1'b0),
        .sdram_addr(SDRAM_ADDR), .sdram_ba(SDRAM_BA), .sdram_cs_n(SDRAM_CS_N),
        .sdram_ras_n(SDRAM_RAS_N), .sdram_cas_n(SDRAM_CAS_N), .sdram_we_n(SDRAM_WE_N),
        .sdram_dq(SDRAM_DQ), .sdram_dqm({SDRAM_UDQM, SDRAM_LDQM}), .sdram_cke(SDRAM_CKE)
    );
    assign SDRAM_CLK = clk_100mhz_shifted;

    //==========================================================================
    // AXI->VGA premosťovač
    //==========================================================================
    axis_to_vga #(.C_VGA_MODE(C_VGA_MODE)) u_axis_to_vga (
        .axi_clk_i(clk_axi),
        .axi_rst_ni(rstn_sync_axi),
        .pix_clk_i(pixel_clk),
        .pix_rst_ni(rstn_sync_pixel),
        .s_axis(axis_fb_if),
        .vga_data_o(vga_rgb_out),
        .vga_sync_o(vga_sync),
        .hde_o(),
        .vde_o()
    );

    //==========================================================================
    // Výstupy VGA
    //==========================================================================
    assign VGA_HS = vga_sync.hs;
    assign VGA_VS = vga_sync.vs;
    assign VGA_R  = vga_rgb_out.red;
    assign VGA_G  = vga_rgb_out.grn;
    assign VGA_B  = vga_rgb_out.blu;

    //==========================================================================
    // LED indikácia (log.0 = svieti)
    //==========================================================================
    assign LED[0] = ~pll_locked;        // 0 = PLL locked
    assign LED[1] = ~rstn_sync_axi;     // 0 = AXI reset uvoľnený
    assign LED[2] = ~sdram_reader_valid; // 0 = Framebuffer požaduje čítanie
    assign LED[3] = ~sdram_reader_ready; // 0 = SDRAM driver pripravený čítať
    assign LED[4] = ~sdram_resp_valid;   // 0 = SDRAM driver posiela dáta
    assign LED[5] = ~fb_fifo_full;       // 0 = FIFO plný

endmodule

`default_nettype wire
