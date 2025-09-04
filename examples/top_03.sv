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
    // KONFIGURÁCIA
    //==========================================================================
    localparam VGA_mode_e C_VGA_MODE = VGA_1024x768_60;

    //==========================================================================
    // PLL a RESET logika
    //==========================================================================
    logic pixel_clk;
    logic pll_locked;
    logic pix_rstn_sync;

    ClkPll clkpll_inst (
        .inclk0 (SYS_CLK),
        .areset (~RESET_N),
        .c0     (pixel_clk),
        .locked (pll_locked)
    );

    assign pix_rstn_sync = RESET_N & pll_locked;

    //==========================================================================
    // VGA CONTROLLER (nová verzia - VgaCtrl)
    //==========================================================================

	Line_t  h_line, v_line;
	VGA_data_t data_in;
	VGA_data_t data_out;
	VGA_sync_t sync_out;
	logic      de;  // data enable

	logic enable;

   always_comb begin
        get_vga_timing(C_VGA_MODE, h_line, v_line);
		  data_in = BLUE;
		  enable = '1;
    end

	// Inštancia modulu Vga
	Vga #(
		 .BLANKING_COLOR(YELLOW)  // žltá
	) vga_inst (
		 .clk      (pixel_clk),
		 .rstn     (pix_rstn_sync),
		 .enable   (enable),         // aktívny pixel (enable)
		 .h_line   (h_line),
		 .v_line   (v_line),
		 .data_in  (data_in),   // vstupné RGB dáta
		 .de       (de),
		 .data_out (data_out),
		 .sync_out (sync_out)
	);

	// Výstupné signály VGA synchronizácie
	assign VGA_HS = sync_out.hs;
	assign VGA_VS = sync_out.vs;

	// Výstupné RGB z data_out
	assign VGA_R = data_out.red;
	assign VGA_G = data_out.grn;
	assign VGA_B = data_out.blu;	 


    //==========================================================================
    // 7-SEGMENTOVÝ DISPLEJ
    //==========================================================================
    logic [3:0] digit0 = 4'd1, digit1 = 4'd2, digit2 = 4'd3;

    localparam int PIXEL_CLOCK_HZ = get_pixel_clock(C_VGA_MODE);
    localparam int ONE_MS_TICKS   = (PIXEL_CLOCK_HZ == 0) ? 1 : PIXEL_CLOCK_HZ / 1000;
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

    always_comb begin
        case (seg_sel)
            2'd0:   begin SMG_DIG = 3'b110; SMG_SEG = seg_decoder(digit0); end
            2'd1:   begin SMG_DIG = 3'b101; SMG_SEG = seg_decoder(digit1); end
            2'd2:   begin SMG_DIG = 3'b011; SMG_SEG = seg_decoder(digit2); end
            default:begin SMG_DIG = 3'b111; SMG_SEG = 8'hFF; end
        endcase
    end

    function automatic [7:0] seg_decoder(input logic [3:0] val);
        case (val)
             4'h0:return 8'hC0; 4'h1:return 8'hF9; 4'h2:return 8'hA4; 4'h3:return 8'hB0;
             4'h4:return 8'h99; 4'h5:return 8'h92; 4'h6:return 8'h82; 4'h7:return 8'hF8;
             4'h8:return 8'h80; 4'h9:return 8'h90; default: return 8'hFF;
        endcase
    endfunction

    //==========================================================================
    // LED diagnostika (momentálne jednoduchá aktivita)
    //==========================================================================
    logic led0_reg;
    localparam int BLINK_DIVIDER = (PIXEL_CLOCK_HZ == 0) ? 1 : PIXEL_CLOCK_HZ / 2;
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

    assign LED = {
        3'b000,         // LED[5:3] nepoužité zatiaľ
        ~BSW[2:1],      // LED[2:1]: prepínače
        led0_reg        // LED[0]: indikátor aktivity
    };

endmodule
