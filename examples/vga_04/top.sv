`default_nettype none

import vga_pkg::*;

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

    //==========================================================================
    // KONFIGURÁCIA VGA režimu
    //==========================================================================
localparam vga_mode_e C_VGA_MODE = VGA_1680x1050_60;

// Zavolajte funkciu iba RAZ a uložte výsledok do konštantnej štruktúry
localparam vga_params_t C_VGA_PARAMS = get_vga_params(C_VGA_MODE);


    //==========================================================================
    // PLL a RESET logika (generovanie pixelového hodinového signálu)
    //==========================================================================
    logic pixel_clk;
    logic pll_locked;
    logic pix_rstn_sync;

    ClkPll ClkPll_inst (
        .inclk0 (SYS_CLK),
        .areset (~RESET_N),
        .c0     (pixel_clk),
        .locked (pll_locked)
    );

    assign pix_rstn_sync = RESET_N & pll_locked;

    //==========================================================================
    // VGA CONTROLLER – zodpovedný za generovanie sync signálov a DE
    //==========================================================================
    vga_data_t generated_data, data_out;
    vga_sync_t sync_out;
    logic de, hde, vde;
    logic vga_line_end, vga_frame_end;

    vga_ctrl #(
        .BLANKING_COLOR(YELLOW)
    ) vga_inst (
		.clk_i       (pixel_clk),
		.rst_ni      (pix_rstn_sync),
		.enable_i    (1'b1),  // Vždy povolené
		.h_line_i    (C_VGA_PARAMS.h_line),
		.v_line_i    (C_VGA_PARAMS.v_line),
		.fifo_data_i   (generated_data),
		.hde_o (hde),
		.vde_o (vde),
		.dat_o (data_out),
		.syn_o (sync_out),
		.eol_o (vga_line_end),
		.eof_o (vga_frame_end)
    );

    // Výstup VGA signálov
    assign VGA_HS = sync_out.hs;
    assign VGA_VS = sync_out.vs;
    assign VGA_R  = data_out.red;
    assign VGA_G  = data_out.grn;
    assign VGA_B  = data_out.blu;

    //==========================================================================
    // GENERÁTOR OBRAZU – výpočet pixelových súradníc a farby
    //==========================================================================
    logic [LineCounterWidth-1:0] pixel_x, pixel_y;

    vga_pixel_xy #(
        .MAX_COUNTER_H(MaxPosCounterX),
        .MAX_COUNTER_V(MaxPosCounterY)
    ) coord_inst (
        .clk_i		(pixel_clk),
        .rst_ni   (pix_rstn_sync),
        .enable_i (hde && vde),
        .eol_i  	(vga_line_end),
        .eof_i 	(vga_frame_end),
        .x_o      (pixel_x),
        .y_o      (pixel_y)
    );

    picture_gen #(
        .MAX_COUNTER_H(MaxPosCounterX),
        .MAX_COUNTER_V(MaxPosCounterY),
        .MaxModes(8)
    ) image_gen_inst (
        .clk_i      (pixel_clk),
        .rst_ni     (pix_rstn_sync),
		  .enable_i(1'b1),
        .x_i  (pixel_x),
        .y_i  (pixel_y),
        .de_i (hde && vde),
        .mode_i     (BSW[2:0]),  // prepínače určujú režim
        .data_o (generated_data)
    );
	 
//assign generated_data = RED;
    //==========================================================================
    // 7-SEGMENTOVÝ DISPLEJ – multiplexovanie 3 číslic
    //==========================================================================
    logic [3:0] digit0 = 4'd1, digit1 = 4'd2, digit2 = 4'd3;
/*
localparam int ONE_MS_TICKS = (C_VGA_PARAMS.pixel_clock_hz == 0) ? 1 : C_VGA_PARAMS.pixel_clock_hz / 1000;



    logic [$clog2(ONE_MS_TICKS)-1:0] ms_counter;
    logic [1:0] seg_sel;

    always_ff @(posedge pixel_clk) begin
        if (!pix_rstn_sync) begin
            ms_counter <= 'd0;
            seg_sel    <= 2'd0;
        end else if (ms_counter == ONE_MS_TICKS - 1) begin
            ms_counter <= 'd0;
            seg_sel    <= seg_sel + 1;
        end else begin
            ms_counter <= ms_counter + 1;
        end
    end

    // Výber číslice a segmentového výstupu
    always_comb begin
        case (seg_sel)
            2'd0:   begin SMG_DIG = 3'b110; SMG_SEG = seg_decoder(digit0); end
            2'd1:   begin SMG_DIG = 3'b101; SMG_SEG = seg_decoder(digit1); end
            2'd2:   begin SMG_DIG = 3'b011; SMG_SEG = seg_decoder(digit2); end
            default:begin SMG_DIG = 3'b111; SMG_SEG = 8'hFF;               end
        endcase
    end

    // Funkcia pre dekódovanie čísla na 7-segmentové výstupy (common anode)
    function automatic [7:0] seg_decoder(input logic [3:0] val);
        case (val)
            4'h0: return 8'hC0; 4'h1: return 8'hF9;
            4'h2: return 8'hA4; 4'h3: return 8'hB0;
            4'h4: return 8'h99; 4'h5: return 8'h92;
            4'h6: return 8'h82; 4'h7: return 8'hF8;
            4'h8: return 8'h80; 4'h9: return 8'h90;
            default: return 8'hFF;
        endcase
    endfunction
*/
    //==========================================================================
    // LED diagnostika – blikajúca LED a indikácia stavu prepínačov
    //==========================================================================
    logic led0_reg;
/*	 
localparam int BLINK_DIVIDER = (C_VGA_PARAMS.pixel_clock_hz == 0) ? 1 : C_VGA_PARAMS.pixel_clock_hz / 2;

    logic [$clog2(BLINK_DIVIDER)-1:0] blink_counter_reg;

    always_ff @(posedge pixel_clk) begin
        if (!pix_rstn_sync) begin
            blink_counter_reg <= 'd0;
            led0_reg          <= 1'b0;
        end else if (blink_counter_reg == BLINK_DIVIDER - 1) begin
            blink_counter_reg <= 'd0;
            led0_reg          <= ~led0_reg;
        end else begin
            blink_counter_reg <= blink_counter_reg + 1;
        end
    end
*/
    assign LED = {
        3'b000,         // LED[5:3]: voľné
        ~BSW[2:1],      // LED[2:1]: stav prepínačov (invertovaný)
//        led0_reg        // LED[0]: blikanie
1'b1
    };

endmodule
