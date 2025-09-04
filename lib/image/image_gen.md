Jasné, tu je návrh modulu `image_gen.sv`, ktorý generuje rôzne testovacie obrazce na základe vstupných súradníc a prepínateľného režimu. Tento modul predpokladá, že máte k dispozícii `vga_pkg` definujúci `VGA_data_t` (RGB565 štruktúru) a základné farby.

### Súbor: `image_gen.sv`

```systemverilog
`timescale 1ns / 1ns
`default_nettype none

import vga_pkg::*;

//==========================================================================
// Modul: ImageGenerator
// Popis: Generuje rôzne testovacie obrazce (šachovnica, prechody)
//        na základe aktuálnych X/Y súradníc.
//==========================================================================

module ImageGenerator #(
    parameter int X_WIDTH = 11,
    parameter int Y_WIDTH = 11,
    parameter int MODE_WIDTH = 3 // Šírka pre výber režimu (napr. 8 režimov)
)(
    // Vstupy zo systému
    input logic clk,
    input logic rstn,

    // Vstupy z PixelCoordinates modulu
    input logic [X_WIDTH-1:0] pixel_x,
    input logic [Y_WIDTH-1:0] pixel_y,
    input logic               de,         // Data Enable (aktívna oblasť)

    // Riadenie režimu (napr. z prepínačov BSW)
    input logic [MODE_WIDTH-1:0] mode,

    // Výstup: RGB dáta pre aktuálny pixel
    output VGA_data_t         data_out
);

    // Definícia režimov generátora
    typedef enum logic [MODE_WIDTH-1:0] {
        MODE_CHECKER_SMALL  = 0, // Malá šachovnica
        MODE_CHECKER_LARGE  = 1, // Veľká šachovnica
        MODE_H_GRADIENT     = 2, // Horizontálny prechod (farebný)
        MODE_V_GRADIENT     = 3, // Vertikálny prechod (čiernobiely)
        MODE_CROSSHAIR      = 4, // Kríž v strede
        MODE_COLOR_BARS     = 5  // Vertikálne farebné pruhy
    } Mode_e;

    // Interné signály pre jednotlivé farebné zložky
    logic [4:0] r_val;
    logic [5:0] g_val;
    logic [4:0] b_val;

    // Veľkosť štvorca pre šachovnicu (nastavené bitom súradnice)
    localparam int CHECKER_SIZE_SMALL = 3; // 2^3 = 8x8 pixelov
    localparam int CHECKER_SIZE_LARGE = 5; // 2^5 = 32x32 pixelov

    always_comb begin
        // Predvolené hodnoty (napr. čierna)
        r_val = 5'b0;
        g_val = 6'b0;
        b_val = 5'b0;

        // Generovanie obrazca podľa zvoleného režimu
        case (Mode_e'(mode))

            // =============================================================
            // Režim 0: Malá šachovnica (8x8)
            // =============================================================
            MODE_CHECKER_SMALL: begin
                // XOR bitov X a Y určuje farbu štvorca
                if (pixel_x[CHECKER_SIZE_SMALL] ^ pixel_y[CHECKER_SIZE_SMALL]) begin
                    // Biely štvorec
                    r_val = 5'h1F;
                    g_val = 6'h3F;
                    b_val = 5'h1F;
                end else begin
                    // Čierny štvorec (už nastavené ako default)
                end
            end

            // =============================================================
            // Režim 1: Veľká šachovnica (32x32)
            // =============================================================
            MODE_CHECKER_LARGE: begin
                if (pixel_x[CHECKER_SIZE_LARGE] ^ pixel_y[CHECKER_SIZE_LARGE]) begin
                    // Modrý štvorec
                    r_val = 5'h00;
                    g_val = 6'h00;
                    b_val = 5'h1F;
                end else begin
                    // Žltý štvorec (R+G)
                    r_val = 5'h1F;
                    g_val = 6'h3F;
                    b_val = 5'h00;
                end
            end

            // =============================================================
            // Režim 2: Horizontálny prechod (Farebný)
            // =============================================================
            MODE_H_GRADIENT: begin
                // Použijeme najvyššie bity X súradnice pre farby
                // R (5 bitov), G (6 bitov), B (5 bitov)
                r_val = pixel_x[X_WIDTH-1 -: 5];
                g_val = pixel_x[X_WIDTH-1 -: 6];
                b_val = pixel_x[X_WIDTH-1 -: 5];
            end

            // =============================================================
            // Režim 3: Vertikálny prechod (Čiernobiely)
            // =============================================================
            MODE_V_GRADIENT: begin
                // Použijeme najvyššie bity Y súradnice
                // Pre čiernobielu musia byť R, G, B rovnaké.
                // Použijeme 6 najvyšších bitov Y pre G, a 5 pre R a B.
                r_val = pixel_y[Y_WIDTH-1 -: 5];
                g_val = pixel_y[Y_WIDTH-1 -: 6];
                b_val = pixel_y[Y_WIDTH-1 -: 5];
            end

            // =============================================================
            // Režim 4: Kríž v strede
            // =============================================================
            MODE_CROSSHAIR: begin
                // Zobrazí biely kríž, ak je X alebo Y blízko stredu obrazovky
                // Stred je približne (h_visible/2) a (v_visible/2).
                // Keďže nepoznáme presné rozlíšenie, použijeme stred rozsahu X_WIDTH/Y_WIDTH.
                if ( (pixel_x >= (1<<(X_WIDTH-1))-2 && pixel_x <= (1<<(X_WIDTH-1))+2) ||
                     (pixel_y >= (1<<(Y_WIDTH-1))-2 && pixel_y <= (1<<(Y_WIDTH-1))+2) ) begin
                    r_val = 5'h1F; // Biely kríž
                    g_val = 6'h3F;
                    b_val = 5'h1F;
                end else begin
                    r_val = 5'h08; // Tmavosivý podklad
                    g_val = 6'h10;
                    b_val = 5'h08;
                end
            end

            // =============================================================
            // Režim 5: Vertikálne farebné pruhy (Color Bars)
            // =============================================================
            MODE_COLOR_BARS: begin
                // Rozdelíme obrazovku na 8 pruhov podľa najvyšších 3 bitov X
                case (pixel_x[X_WIDTH-1 -: 3])
                    3'd0: data_out = WHITE;
                    3'd1: data_out = YELLOW;
                    3'd2: data_out = CYAN;
                    3'd3: data_out = GREEN;
                    3'd4: data_out = PURPLE;
                    3'd5: data_out = RED;
                    3'd6: data_out = BLUE;
                    3'd7: data_out = BLACK;
                endcase
                // V tomto režime priraďujeme priamo data_out, nie r_val/g_val/b_val
                return; // Ukončíme always_comb blok skôr
            end

            // =============================================================
            // Default: Jednoduchá farba (napr. modrá)
            // =============================================================
            default: begin
                data_out = BLUE;
                return;
            end

        endcase

        // Zabalenie R, G, B hodnôt do výstupnej štruktúry (RGB565)
        // Toto sa nevykoná, ak režim použil 'return' (napr. COLOR_BARS)
        data_out.red = r_val;
        data_out.grn = g_val;
        data_out.blu = b_val;

    end

endmodule
```

### Ako integrovať `ImageGenerator` do `top.sv`

Ak chcete tento generátor použiť vo vašom `top.sv`, musíte urobiť niekoľko zmien:

1.  **Inštancovať `PixelCoordinates`:** Potrebujete súradnice `pixel_x` a `pixel_y`.
2.  **Inštancovať `ImageGenerator`:** Pripojiť súradnice a prepínače (`BSW`) na výber režimu.
3.  **Pripojiť výstup generátora k VGA modulu:** Nahradiť pevnú farbu výstupom z generátora.

**Príklad integrácie v `top.sv`:**

```systemverilog
// ... v module top.sv ...

//==========================================================================
// VGA CONTROLLER a GENERÁTOR OBRAZU
//==========================================================================

Line_t  h_line, v_line;
VGA_data_t generated_data; // Dáta z generátora
VGA_data_t data_out;
VGA_sync_t sync_out;
logic      de;
logic [10:0] pixel_x, pixel_y; // Predpokladáme 11 bitov pre súradnice

// Získanie časovania (môže byť mimo always_comb, ak je C_VGA_MODE konštanta)
initial begin
   get_vga_timing(C_VGA_MODE, h_line, v_line);
end

// 1. Inštancia generátora súradníc
PixelCoordinates #(
    .X_WIDTH(11),
    .Y_WIDTH(11)
) coord_inst (
    .clk    (pixel_clk),
    .rstn   (pix_rstn_sync),
    .de     (de), // Riadené Data Enable signálom z Vga modulu
    .x      (pixel_x),
    .y      (pixel_y)
);

// 2. Inštancia generátora obrazcov
ImageGenerator #(
    .X_WIDTH(11),
    .Y_WIDTH(11),
    .MODE_WIDTH(3)
) image_gen_inst (
    .clk      (pixel_clk),
    .rstn     (pix_rstn_sync),
    .pixel_x  (pixel_x),
    .pixel_y  (pixel_y),
    .de       (de),
    .mode     (BSW[2:0]), // Použijeme 3 prepínače na výber režimu
    .data_out (generated_data)
);

// 3. Inštancia VGA modulu
Vga #(
     .BLANKING_COLOR(YELLOW)
) vga_inst (
     .clk     (pixel_clk),
     .rstn    (pix_rstn_sync),
     .enable  (1'b1), // Vždy povolené
     .h_line  (h_line),
     .v_line  (v_line),
     .data_in (generated_data), // Vstup sú dáta z ImageGenerator
     .de      (de),
     .data_out(data_out),
     .sync_out(sync_out)
);

// ... zvyšok top modulu ...
```
