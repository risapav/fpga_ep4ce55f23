`ifndef VGA_IMAGE_GEN
`define VGA_IMAGE_GEN

`timescale 1ns/1ns
`default_nettype none

import vga_pkg::*;

// =============================================================================
// == Modul: ImageGenerator
// == Popis: Generuje testovacie obrazce, ktoré sa automaticky prispôsobujú
// ==        rozlíšeniu definovanému v parametri C_VGA_MODE.
// =============================================================================
module image_gen #(
    // Šírka vstupného signálu pre výber režimu. 3 bity = 8 režimov.
    parameter int MODE_WIDTH = 3
)(
    // --- Vstupy zo systému ---
    input  logic clk_i,        // Vstupný hodinový signál (pixel clock)
    input  logic rst_ni,       // Synchrónny reset, aktívny v L
    input  logic enable_i,     // Povolenie činnosti modulu

    // --- Vstupy pre VLASTNÉ časovanie ---
    input  line_t     h_line_i,
    input  line_t     v_line_i,

    // --- Vstupy súradníc (typicky z modulu PixelCoordinates) ---
    input  logic [TIMING_WIDTH-1:0] x_i,
    input  logic [TIMING_WIDTH-1:0] y_i,

    // Data Enable signál indikuje, kedy je pixel v aktívnej (viditeľnej) oblasti.
    input  logic               de_i,

    // Vstup na riadenie režimu (napr. pripojený na prepínače na doske)
    input  logic [MODE_WIDTH-1:0] mode_i,

    // --- Výstup ---
    // Vypočítané RGB565 dáta pre aktuálny pixel
    output vga_data_t         data_o
);

    // Ostatné lokálne parametre
    localparam int CHECKER_SIZE_SMALL = 3; // 8x8 px
    localparam int CHECKER_SIZE_LARGE = 5; // 32x32 px
    localparam int ANIM_WIDTH = 8;

    // Prehľadný zoznam dostupných režimov generátora.
    typedef enum logic [MODE_WIDTH-1:0] {
        MODE_CHECKER_SMALL  = 3'd0, // Malá šachovnica (8x8 px)
        MODE_CHECKER_LARGE  = 3'd1, // Veľká šachovnica (32x32 px)
        MODE_H_GRADIENT     = 3'd2, // Horizontálny farebný prechod
        MODE_V_GRADIENT     = 3'd3, // Vertikálny čiernobiely prechod
        MODE_COLOR_BARS     = 3'd4, // Vertikálne farebné pruhy (SMPTE)
        MODE_CROSSHAIR      = 3'd5, // Zameriavací kríž v strede
        MODE_DIAG_SCROLL    = 3'd6, // Pohyblivé diagonálne pruhy
        MODE_MOVING_BAR     = 3'd7  // moving bar
    } mode_e;

    // =========================================================================
    // ==               Sekvenčná logika pre animované obrazce              ==
    // =========================================================================

    logic de_q1, de_q2;          // o 1 takt oneskorený DE signál


    // == Detekcia začiatku snímky ==
    wire frame_start = (de_q1 && !de_q2 && y_i == '0);

    // Nový always_ff blok pre registráciu výstupu
    VGA_data_t data_next;

    always_ff @(posedge clk_i) begin
        if (!rst_ni)
            data_o <= BLACK;
        else if (de_i) // Farbu priradíme len vo viditeľnej oblasti
            data_o <= data_next;
        else
            data_o <= BLACK; // Mimo viditeľnej oblasti posielame čiernu
    end

    // --- Sekvenčná logika pre animáciu (bez zmeny) ---
    logic [ANIM_WIDTH-1:0] scroll_offset;
    logic [MODE_WIDTH-1:0] mode_q;

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            mode_q        <= '0;
            scroll_offset <= '0;
        end else if (enable_i) begin
            mode_q <= mode_i;

            // Detekcia konca snímky pre plynulú animáciu
            if (x_i == h_line_i.visible_area-1 && y_i == v_line_i.visible_area-1) begin
                scroll_offset <= scroll_offset++;
            end
        end
    end

    // =========================================================================
    // ==        KOMBINAČNÁ LOGIKA - DYNAMICKÝ GENERÁTOR OBRAZCOV            ==
    // =========================================================================
    always_comb begin : generate_output
        data_next = BLACK;

        case (mode_e'(mode_q))

            // Tieto režimy sú prirodzene flexibilné a nepotrebujú zmenu
            MODE_CHECKER_SMALL: data_next =
                (x_i[CHECKER_SIZE_SMALL] ^ y_i[CHECKER_SIZE_SMALL]) ? WHITE : BLACK;
            MODE_CHECKER_LARGE: data_next =
                (x_i[CHECKER_SIZE_LARGE] ^ y_i[CHECKER_SIZE_LARGE]) ? BLUE : YELLOW;

            MODE_H_GRADIENT: begin
                logic [4:0] r;
                logic [5:0] g;
                logic [4:0] b;
                // Pre červenú zložku (5 bitov) zoberieme bity 10 až 6
                r = x_i[10:6];//x_i[TIMING_WIDTH-1 -: 5]
                // Pre zelenú (6 bitov) zoberieme bity 9 až 4 (mierne posunuté)
                g = x_i[9:4];//x_i[TIMING_WIDTH-1 -: 6]
                // Pre modrú (5 bitov) zoberieme bity 8 až 3 (opäť posunuté)
                b = x_i[8:3];//x_i[TIMING_WIDTH-1 -: 5]

                data_next = {r, g, b};
            end

            MODE_V_GRADIENT: begin
                logic [4:0] r;
                logic [5:0] g;
                logic [4:0] b;
                // Pre červenú zložku (5 bitov) zoberieme bity 10 až 6
                r = y_i[10:6];//y_i[TIMING_WIDTH-1 -: 5]
                // Pre zelenú (6 bitov) zoberieme bity 9 až 4 (mierne posunuté)
                g = y_i[9:4];//y_i[TIMING_WIDTH-1 -: 6]
                // Pre modrú (5 bitov) zoberieme bity 8 až 3 (opäť posunuté)
                b = y_i[8:3];//y_i[TIMING_WIDTH-1 -: 5]

                data_next = {r, g, b};
            end

            MODE_DIAG_SCROLL:   begin
                logic [4:0] r;
                logic [5:0] g;
                logic [4:0] b;
                logic [TIMING_WIDTH:0] sum;
                sum = x_i + y_i + scroll_offset;
                // Pre červenú zložku (5 bitov) zoberieme bity 10 až 6
                r = sum[10:6]; //sum[TIMING_WIDTH -: 5]
                // Pre zelenú (6 bitov) zoberieme bity 9 až 4 (mierne posunuté)
                g = sum[9:4]; //sum[TIMING_WIDTH -: 6]
                // Pre modrú (5 bitov) zoberieme bity 8 až 3 (opäť posunuté)
                b = sum[8:3]; //sum[TIMING_WIDTH -: 5]

                data_next = {r, g, b};
            end

            MODE_MOVING_BAR:    begin
                if (((x_i + scroll_offset) & 8'h3F) < 16) data_next = RED;
                else data_next = BLACK;
            end

            // --- DYNAMICKÁ LOGIKA PRE FAREBNÉ PRUHY ---
            MODE_COLOR_BARS: begin
                // Vyhneme sa hardvérovej deličke použitím násobenia.
                // Podmienka `x_i < C_WIDTH / 8` je ekvivalentná `x_i * 8 < C_WIDTH`.
                // Násobenie 8 je len bitový posun doľava o 3, čo je hardvérovo triviálne.
                logic [TIMING_WIDTH+2:0] x_times_8;
                x_times_8 = x_i << 3;

                if      (x_times_8 < h_line_i.visible_area * 1) data_next = WHITE;
                else if (x_times_8 < h_line_i.visible_area * 2) data_next = YELLOW;
                else if (x_times_8 < h_line_i.visible_area * 3) data_next = CYAN;
                else if (x_times_8 < h_line_i.visible_area * 4) data_next = GREEN;
                else if (x_times_8 < h_line_i.visible_area * 5) data_next = PURPLE;
                else if (x_times_8 < h_line_i.visible_area * 6) data_next = RED;
                else if (x_times_8 < h_line_i.visible_area * 7) data_next = BLUE;
                else                                            data_next = BLACK;
            end

            // --- DYNAMICKÁ LOGIKA PRE ZAMERIAVACÍ KRÍŽ ---
            MODE_CROSSHAIR: begin
                logic [TIMING_WIDTH-1:0] center_x, center_y;
                logic is_on_x_line, is_on_y_line;

                // Stred vypočítame bitovým posunom doprava (delenie dvomi)
                center_x = h_line_i.visible_area >> 1;
                center_y = v_line_i.visible_area >> 1;

                // Podmienka pre vykreslenie čiary
                is_on_y_line = (y_i > (center_y - 2)) && (y_i < (center_y + 2));
                is_on_x_line = (x_i > (center_x - 2)) && (x_i < (center_x + 2));

                if (is_on_x_line || is_on_y_line)
                    data_next = WHITE;
                else
                    data_next = DARK_GRAY;
            end

            default: data_next = ORANGE;

        endcase
    end
endmodule

`endif //VGA_IMAGE_GEN
