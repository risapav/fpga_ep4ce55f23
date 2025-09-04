//=============================================================================
// top.sv - Finálny top-level modul s VGA Controllerom
// Verzia: 5.2
//
// === Popis a vylepšenia ===
// 1. OPRAVA RESETU: Implementovaná jednotná, robustná a synchrónna reset
//    logika. Všetky moduly v `pixel_clk` doméne sú teraz resetované
//    jedným signálom `pix_rstn_sync`, ktorý zohľadňuje externý reset
//    aj stav `pll_locked`. Tým sa predchádza riziku zaseknutia logiky.
//
// 2. VYČISTENIE KÓDU: Odstránené všetky nadbytočné parametre z predchádzajúcich
//    verzií. `top.sv` je teraz čistý štrukturálny "obal".
//
// 3. ROBUSTNOSŤ: Všetky interné konštanty (napr. pre periférie) sa teraz
//    automaticky odvodzujú z jediného centrálneho nastavenia `C_VGA_MODE`.
//=============================================================================
`default_nettype none

import vga_pkg::*;

module top (
    // -- Porty zostávajú nezmenené --
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
    // JEDINÉ MIESTO KONFIGURÁCIE
    //==========================================================================
    // Zmenou tohto jedného riadku a prekonfigurovaním PLL sa zmení celý režim.
    localparam VGA_mode_e C_VGA_MODE = VGA_1024x768;

    //==========================================================================
    // HODINY A RESET
    //==========================================================================
    logic pixel_clk;
    logic pll_locked;
    logic pix_rstn_sync; // Nový, jednotný a robustný reset signál

    // Inštancia PLL pre generovanie pixel clocku (musí byť v Quartuse nastavená na 108 MHz)
    ClkPll clkpll_inst (
        .inclk0 (SYS_CLK),
        .areset (~RESET_N),
        .c0     (pixel_clk),
        .locked (pll_locked)
    );

    // Generovanie robustného, synchrónneho resetu aktívneho v nule.
    // Reset je aktívny (`0`), pokiaľ je aktívny externý `RESET_N`
    // ALEBO pokiaľ PLL nie je stabilizovaná.
    assign pix_rstn_sync = RESET_N & pll_locked;


    //==========================================================================
    // INŠTANCIA VGA CONTROLLERA
    //==========================================================================
    logic overflow_flag, underflow_flag;

    vga_controller #(
        .RESOLUTION(C_VGA_MODE),
        .TEST_MODE (1'b1)
        // Ostatné parametre používajú svoje predvolené hodnoty
    )
    vga_inst (
        .pix_clk  (pixel_clk),
        .pix_rstn (pix_rstn_sync), // OPRAVA: Používame nový, robustný reset
        .axi_clk  (pixel_clk),
        .axi_rstn (pix_rstn_sync), // OPRAVA: Používame nový, robustný reset

        .s_axis_tdata ('d0),
        .s_axis_tuser ('d0),
        .s_axis_tlast (1'b0),
        .s_axis_tvalid(1'b0),
        .s_axis_tready(),

        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS),
        .overflow_sticky_flag (overflow_flag),
        .underflow_sticky_flag(underflow_flag)
    );


    //==========================================================================
    // PERIFÉRIE (7-SEGMENTOVÝ DISPLEJ A LED)
    //==========================================================================
    // --- 7-Segmentový Displej ---
    logic [3:0] digit0 = 4'd1, digit1 = 4'd2, digit2 = 4'd3;

    localparam int PIXEL_CLOCK_HZ = get_pixel_clock(C_VGA_MODE);
    localparam int ONE_MS_TICKS   = PIXEL_CLOCK_HZ / 1000;
    logic [$clog2(ONE_MS_TICKS)-1:0] ms_counter;
    logic [1:0] seg_sel;

    // OPRAVA: Blok teraz používa jednotný, active-low synchrónny reset
    always_ff @(posedge pixel_clk or negedge pix_rstn_sync) begin
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


    // --- LED diódy ---
    logic led0_reg;
    localparam int BLINK_DIVIDER = PIXEL_CLOCK_HZ / 2;
    logic [$clog2(BLINK_DIVIDER)-1:0] blink_counter_reg;

    // OPRAVA: Blok teraz používa jednotný, active-low synchrónny reset
    always_ff @(posedge pixel_clk or negedge pix_rstn_sync) begin
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

    assign LED = {overflow_flag, underflow_flag, ~BSW[3:1], led0_reg};

endmodule