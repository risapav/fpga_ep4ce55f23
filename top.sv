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

    output logic [7:0] SEG7_J10,

    inout logic [15:0] DRAM_DQ,
    output logic [12:0] DRAM_ADDR,
    output logic [1:0] DRAM_BA,
    output logic DRAM_CAS_N,
    output logic DRAM_CKE,
    //  DRAM_CLK
    output logic DRAM_CS_N,
    output logic DRAM_WE_N,
    output logic DRAM_RAS_N,
    output logic DRAM_UDQM,
    output logic DRAM_LDQM,

    output logic [3:0] HDMI_P_J11
);

    //==========================================================================
    // KONFIGURÁCIA VGA režimu
    //==========================================================================
  //localparam vga_mode_e C_VGA_MODE = VGA_640x480_60;
  localparam vga_mode_e C_VGA_MODE = VGA_800x600_60;
  //localparam vga_mode_e C_VGA_MODE = VGA_1024x768_60;
  //localparam vga_mode_e C_VGA_MODE = VGA_1280x1024_60;


  localparam int PixelClockHz = get_pixel_clock(C_VGA_MODE);

    //==========================================================================
    // PLL a RESET logika (generovanie pixelového hodinového signálu)
    //==========================================================================
    logic pixel_clk, pixel_clk5;
    logic pll_locked;
    logic rstn_sync;

    ClkPll clkpll_inst (
        .inclk0 (SYS_CLK),
        .areset (~RESET_N),
        .c0     (pixel_clk),
        .c1     (pixel_clk5),
        .locked (pll_locked)
    );

    assign rstn_sync = RESET_N & pll_locked;

    //==========================================================================
    // ==                 Hlavné moduly a ich prepojenie                   ==
    //==========================================================================
    wire enable;
    assign enable = 1;

    // --- Signály pre prepojenie modulov ---
    rgb565_t   generated_data; // Dáta z generátora obrazu
    rgb565_t   vga_data_out;   // Finálne dáta z VGA radiča
    vga_sync_t sync;   // Finálne sync signály z VGA radiča
    wire hde, vde, eol, eof;
    wire [LineCounterWidth-1:0] pixel_x, pixel_y; // Súradnice z generátora

    // --- Logika pre výber časovacích parametrov (Simulácia vs. Syntéza) ---
    // Tento blok zabezpečí, že kód je kompatibilný s Icarusom aj s Quartusom.
    line_t h_line_params;
    line_t v_line_params;

`ifdef __ICARUS__
    // Pre simuláciu (Icarus) zadáme parametre manuálne
    initial begin
        h_line_params = '{640, 16, 96, 48, PulseActiveLow};
        v_line_params = '{480, 10, 2, 33, PulseActiveLow};
    end
`else
    // Pre syntézu (Quartus) použijeme funkciu z balíčka
  vga_params_t vga_params = get_vga_params(C_VGA_MODE);
  assign h_line_params = vga_params.h_line;
  assign v_line_params = vga_params.v_line;

`endif

    // --- Inštancia VGA radiča (časovanie + dátová cesta) ---
    vga_ctrl vga_inst (
        .clk_i        (pixel_clk),
        .rst_ni       (rstn_sync),
        .enable_i     (enable), // Radič beží neustále
        .h_line_i     (h_line_params),
        .v_line_i     (v_line_params),
        .fifo_data_i  (generated_data),
        .fifo_empty_i (1'b0), // Zdroj dát (generátor) nie je nikdy prázdny
        .hde_o        (hde),
        .vde_o        (vde),
        .dat_o        (vga_data_out),
        .syn_o        (sync),
        .eol_o        (eol),
        .eof_o        (eof)
    );

    // --- Inštancia generátora súradníc ---
    vga_pixel_xy coord_inst (
        .clk_i    (pixel_clk),
        .rst_ni   (rstn_sync),
        .enable_i (enable),
        .eol_i    (eol),
        .eof_i    (eof),
        .x_o      (pixel_x),
        .y_o      (pixel_y)
    );

//`define SIMPLE_TEST

`ifdef SIMPLE_TEST
    localparam FRAME_WIDTH = 50;

    function logic is_inside_frame(
        input logic [TIMING_WIDTH-1:0] x,
        input logic [TIMING_WIDTH-1:0] y,
        input VGA_params_t             params
    );
        return
            (x > FRAME_WIDTH && x < (params.h_line.visible_area - FRAME_WIDTH)) &&
            (y > FRAME_WIDTH && y < (params.v_line.visible_area - FRAME_WIDTH));
    endfunction

    logic de;
    assign de = vga_hde && vga_vde;

    always_comb begin
        generated_data = BLUE;
        if (de && is_inside_frame(pixel_x, pixel_y, vga_params))
            generated_data = YELLOW;
    end

`else

    // --- Inštancia generátora obrazu ---
    // OPRAVA: Všetky porty sú teraz správne pripojené podľa definície modulu.
    picture_gen image_gen_inst (
        .clk_i    (pixel_clk),
        .rst_ni   (rstn_sync),
        .enable_i (enable),
        .h_line_i (h_line_params),
        .v_line_i (v_line_params),
        .x_i      (pixel_x),
        .y_i      (pixel_y),
        .de_i     (hde && vde), // Data Enable je kombinácia H a V
        .mode_i   (BSW[2:0]),  // 3 prepínače určujú režim
        .data_o   (generated_data)
    );

`endif

// HDMI
  rgb888_t rgb888_data_comb;
  rgb888_t rgb888_data_reg;

  rgb565_to_rgb888 color_inst (
    .rgb565_i (generated_data),
    .rgb888_o (rgb888_data_comb)
  );

  // Pipeline register pre dáta idúce do HDMI modulu
  always_ff @(posedge pixel_clk) begin
    if (!rstn_sync) begin
      rgb888_data_reg <= '0;
    end else begin
      rgb888_data_reg <= rgb888_data_comb;
    end
  end

  //============================================================
  // HDMI Transmitter
  //============================================================
  hdmi_tx_top #(
    .DDRIO(1)
  ) u_hdmi_tx (
    .clk_i          (pixel_clk),
    .clk_x_i        (pixel_clk5),
    .rst_ni         (rstn_sync),

    .hsync_i        (sync.hs),
    .vsync_i        (sync.vs),

    .video_i        (rgb888_data_reg), // OPRAVA: Použijeme registrované dáta
    .video_valid_i  (hde && vde),

    // OPRAVA: Nepoužívané audio/packet vstupy pripojíme na konštantnú nulu
    .audio_valid_i  (1'b0),
    .packet_valid_i (1'b0),
    .audio_i        (tmds_data_t'(0)),
    .packet_i       (tmds_data_t'(0)),

    // Pripojenie na finálne výstupné porty
    .hdmi_p_o       (HDMI_P_J11)
  );

    //==========================================================================
    // ==                       PRIRADENIE VÝSTUPOV                          ==
    //==========================================================================
    assign VGA_HS = sync.hs;
    assign VGA_VS = sync.vs;
    assign VGA_R  = vga_data_out.red;
    assign VGA_G  = vga_data_out.grn;
    assign VGA_B  = vga_data_out.blu;

//assign generated_data = RED;
    //==========================================================================
    // 7-SEGMENTOVÝ DISPLEJ – multiplexovanie 3 číslic
    //==========================================================================
    localparam int NUM_DIGITS = 3;

    logic [3:0] digits_array [NUM_DIGITS-1:0] = '{4'd1, 4'd2, 4'd3}; // A B C
    logic       dots_array   [NUM_DIGITS-1:0] = '{1'b0, 1'b1, 1'b0};     // iba stredná má bodku

    seven_seg_mux #(
        .NUM_DIGITS(NUM_DIGITS),
        .CLOCK_FREQ_HZ(50_000_000),
        .DIGIT_REFRESH_HZ(200),
        .COMMON_ANODE(1) // alebo 0 pre spoločnú katódu
    ) seg_mux_inst (
        .clk_i(pixel_clk),
        .rst_ni(rstn_sync),
        .digits_i(digits_array),
        .dots_i(dots_array),
        .digit_sel_o(SMG_DIG),
        .segment_sel_o(SMG_SEG),
        .current_digit_o() // nepoužité
    );

    logic [2:0] digits_array_2 [1:0] = '{4'd1, 4'd2}; // A B C
    logic       dots_array_2   [1:0] = '{1'b0, 1'b1};     // iba stredná má bodku

    seven_seg_mux #(
        .NUM_DIGITS(2),
        .CLOCK_FREQ_HZ(50_000_000),
        .DIGIT_REFRESH_HZ(200),
        .COMMON_ANODE(1) // alebo 0 pre spoločnú katódu
    ) seg_mux_inst_2 (
        .clk_i(pixel_clk),
        .rst_ni(rstn_sync),
        .digits_i(digits_array_2),
        .dots_i(dots_array_2),
        .digit_sel_o(SEG7_J10[6:0]),
        .segment_sel_o(SEG7_J10[7:7]),
        .current_digit_o() // nepoužité
    );

    //==========================================================================
    // LED diagnostika – blikajúca LED a indikácia stavu prepínačov
    //==========================================================================
    logic led0_reg;

    blink_led #(
        .CLOCK_FREQ_HZ(PixelClockHz),  // musíš definovať PixelClockHz ako integer
        .BLINK_HZ(1)                     // blikanie 1 Hz, môžeš upraviť
    ) blink_inst (
        .clk_i(pixel_clk),
        .rst_ni(rstn_sync),
        .led_o(led0_reg)
    );

    assign LED = {
        3'b000,         // LED[5:3]: voľné
        ~BSW[2:1],      // LED[2:1]: stav prepínačov (invertovaný)
        led0_reg        // LED[0]: blikanie
    };

endmodule
