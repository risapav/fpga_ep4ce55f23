/**
 * @file        axis_picture_generator.sv
 * @brief       Generátor testovacích obrazcov pre AXI4-Stream.
 * @details     Tento modul generuje rôzne statické a animované obrazce
 * a posiela ich ako AXI4-Stream video dáta vo formáte RGB565.
 * Podporuje rôzne režimy voliteľné vstupom `mode_i`.
 *
 * Zmeny:
 * - Odstránené použitie '$bits' pri inkrementácii pre lepšiu kompatibilitu.
 * - Opravená syntax '{0} na '0.
 *
 * @param H_RES          Horizontálne rozlíšenie (počet pixelov).
 * @param V_RES          Vertikálne rozlíšenie (počet riadkov).
 * @param DATA_WIDTH     Šírka AXI-Stream TDATA (mala by byť 16 pre RGB565).
 * @param USER_WIDTH     Šírka AXI-Stream TUSER.
 * @param KEEP_WIDTH     Šírka AXI-Stream TKEEP (automaticky = DATA_WIDTH/8).
 * @param ID_WIDTH       Šírka AXI-Stream TID (0 = nepoužíva sa).
 * @param DEST_WIDTH     Šírka AXI-Stream TDEST (0 = nepoužíva sa).
 * @param NUM_MODES      Počet podporovaných režimov obrazcov.
 */
`ifndef AXIS_PICTURE_GENERATOR_SV
`define AXIS_PICTURE_GENERATOR_SV

`default_nettype none

import axi_pkg::*; // Import centrálnych AXI parametrov

module axis_picture_generator #(
    // --- Rozlíšenie ---
    parameter int unsigned H_RES = 640,
    parameter int unsigned V_RES = 480,

    // --- AXI4-Stream parametre (mali by zodpovedať axi_pkg) ---
    parameter int unsigned DATA_WIDTH = axi_pkg::AXI_TDATA_WIDTH,
    parameter int unsigned USER_WIDTH = axi_pkg::AXI_TUSER_WIDTH,
    parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int unsigned ID_WIDTH   = 0,
    parameter int unsigned DEST_WIDTH = 0,

    // --- Počet režimov obrazcov ---
    parameter int unsigned NUM_MODES  = 8
)(
    // --- Hodiny a Reset ---
    input  logic clk_i,
    input  logic rst_ni,

    // --- Vstup: výber režimu ---
    input  logic [$clog2(NUM_MODES)-1:0] mode_i,

    // --- AXI4-Stream výstup ---
    // Použije 'master' modport z 'axi4s_if' definovaného v axi_interfaces.sv
    axi4s_if.master m_axis
);

    // ---------------------------
    // Lokálne parametre a typy
    // ---------------------------
    localparam int CLog2HRes = $clog2(H_RES); // Šírka pre X súradnicu
    localparam int CLog2VRes = $clog2(V_RES); // Šírka pre Y súradnicu
    localparam int CModeWidth = $clog2(NUM_MODES); // Šírka pre 'mode_i' a 'mode_q'

    // Veľkosti pre checkerboard vzory
    localparam int CCheckerSizeSmall = 3; // Bit index (2^3 = 8 pixelov)
    localparam int CCheckerSizeLarge = 5; // Bit index (2^5 = 32 pixelov)
    // Šírka registra pre animáciu posunu
    localparam int CAnimWidth = 8;

    // Enum pre režimy (lepšia čitateľnosť kódu)
    typedef enum logic [CModeWidth-1:0] {
        MODE_CHECKER_SMALL  = 3'd0,
        MODE_CHECKER_LARGE  = 3'd1,
        MODE_H_GRADIENT     = 3'd2,
        MODE_V_GRADIENT     = 3'd3,
        MODE_COLOR_BARS     = 3'd4,
        MODE_CROSSHAIR      = 3'd5,
        MODE_DIAG_SCROLL    = 3'd6,
        MODE_MOVING_BAR     = 3'd7
    } mode_e;

    // Typ pre RGB565 farbu
    typedef struct packed {
      logic [4:0] red;
      logic [5:0] grn;
      logic [4:0] blu;
    } rgb565_t;

    // Preddefinované farby
    localparam rgb565_t
        CColorBlack    = 16'h0000,
        CColorWhite    = 16'hFFFF,
        CColorRed      = 16'hF800,
        CColorGreen    = 16'h07E0,
        CColorBlue     = 16'h001F,
        CColorYellow   = 16'hFFE0,
        CColorCyan     = 16'h07FF,
        CColorMagenta  = 16'hF81F, // Purple
        CColorOrange   = 16'hFC00,
        CColorDarkGray = 16'h8410;

    // Paleta pre farebné pásy
    localparam rgb565_t CColorPalette [0:7] = '{
        CColorRed, CColorOrange, CColorYellow, CColorGreen,
        CColorCyan, CColorBlue, CColorMagenta, CColorWhite
    };

    // ---------------------------
    // Interné signály a registre
    // ---------------------------
    // Počítadlá súradníc
    logic [CLog2HRes-1:0] x_reg, x_next;
    logic [CLog2VRes-1:0] y_reg, y_next;

    // Riadiace signály
    logic can_advance;         // Môže sa počítadlo posunúť? (TREADY je 1 alebo nie sme validní)
    logic active_area_comb;    // Kombinačný signál: Sme v aktívnej oblasti obrazu?
    logic start_of_frame_comb; // Kombinačný signál: Sme na začiatku snímku (0,0)?
    logic end_of_line_comb;    // Kombinačný signál: Sme na konci riadku?

    // Výstupné AXI registre (pipeline stage)
    logic                  tvalid_reg;
    logic                  tlast_reg;
    logic [USER_WIDTH-1:0] tuser_reg;
    rgb565_t               pixel_data_reg; // Registrovaný pixel

    // Register pre režim a animáciu
    logic [CModeWidth-1:0] mode_q;        // Registrovaný vstup 'mode_i'
    logic [CAnimWidth-1:0] scroll_offset; // Register pre posun animácie

    // Kombinačný signál pre ďalší pixel
    rgb565_t pixel_data_next;

    // ---------------------------
    // Počítadlá súradníc (X, Y)
    // ---------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            x_reg <= '0;
            y_reg <= '0;
        end else if (can_advance) begin
            x_reg <= x_next;
            y_reg <= y_next;
        end
    end

    // Kombinačná logika pre výpočet ďalších súradníc
    always_comb begin
        x_next = x_reg;
        y_next = y_reg;
        if (can_advance) begin // Posúvame sa len ak môžeme
            if (x_reg == H_RES - 1) begin // Koniec riadku
                x_next = '0;
                y_next = (y_reg == V_RES - 1) ? '0 : y_reg + 1'b1; // Posun Y alebo reset Y
            end else begin // V rámci riadku
                x_next = x_reg + 1'b1; // Posun X
                // y_next zostáva y_reg
            end
        end
    end

    // Pomocné kombinačné signály pre polohu
    assign active_area_comb    = (x_reg < H_RES) && (y_reg < V_RES); // Platné súradnice
    assign start_of_frame_comb = (x_reg == 0) && (y_reg == 0);      // Pixel (0,0)
    assign end_of_line_comb    = (x_reg == H_RES - 1);            // Posledný pixel v riadku

    // ---------------------------
    // Registre pre režim a animáciu
    // ---------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            mode_q        <= '0;
            scroll_offset <= '0;
        end else if (can_advance) begin
            mode_q <= mode_i;
            if ((x_reg == H_RES - 1) && (y_reg == V_RES - 1)) begin
                scroll_offset <= scroll_offset + 1'b1; // Odstránené $bits
            end
        end
    end

    // ---------------------------
    // Pipeline registre pre AXI výstup
    // ---------------------------
    // Tieto registre oneskorujú výstup o jeden takt, čo je bežné pre AXI stream.
    // Dôležité: Vstupom do týchto registrov sú kombinačné signály (napr. active_area_comb).

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            tvalid_reg     <= 1'b0;
            tlast_reg      <= 1'b0;
            tuser_reg      <= '0;
            pixel_data_reg <= '0;
        end else if (can_advance) begin
            tvalid_reg     <= active_area_comb;
            tlast_reg      <= end_of_line_comb && active_area_comb;
            tuser_reg      <= {USER_WIDTH{start_of_frame_comb && active_area_comb}};
            pixel_data_reg <= pixel_data_next;
        end
    end

    // ---------------------------
    // Riadenie toku (Handshake)
    // ---------------------------
    // Môžeme posunúť počítadlá a pipeline, ak je downstream modul pripravený (TREADY=1)
    // alebo ak aktuálne nevysielame platné dáta (TVALID=0).
    assign can_advance = m_axis.TREADY || !tvalid_reg;

    // ---------------------------
    // Kombinačná logika: Generovanie pixelových dát
    // ---------------------------
    always_comb begin
        // Prednastavenie na čiernu (pre blanking intervaly)
        pixel_data_next = CColorBlack;

        if (active_area_comb) begin // Generujeme farbu len pre aktívnu oblasť
            unique case (mode_e'(mode_q)) // Použijeme registrovaný režim 'mode_q'

                // --- Malý checkerboard (8x8) ---
                MODE_CHECKER_SMALL: begin
                    pixel_data_next = (x_reg[CCheckerSizeSmall] ^ y_reg[CCheckerSizeSmall]) ? CColorWhite : CColorBlack;
                end

                // --- Veľký checkerboard (32x32) ---
                MODE_CHECKER_LARGE: begin
                    pixel_data_next = (x_reg[CCheckerSizeLarge] ^ y_reg[CCheckerSizeLarge]) ? CColorBlue : CColorYellow;
                end

                // --- Farebné pásy (vertikálne) ---
                MODE_COLOR_BARS: begin
                    logic [2:0] bar_idx;
                    // Rozdelí šírku obrazovky na 8 rovnakých pásov
                    bar_idx = 3'((x_reg * 8) / H_RES);
                    pixel_data_next = CColorPalette[bar_idx];
                end

                // --- Kríž v strede ---
                MODE_CROSSHAIR: begin
                    logic is_vert_line, is_horiz_line;
                    logic [CLog2HRes-1:0] center_x;
                    logic [CLog2VRes-1:0] center_y;
                    center_x = H_RES >> 1; // Stred X
                    center_y = V_RES >> 1; // Stred Y
                    // Vertikálna čiara (3 pixely široká)
                    is_vert_line = (x_reg >= center_x - 1) && (x_reg <= center_x + 1);
                    // Horizontálna čiara (3 pixely široká)
                    is_horiz_line = (y_reg >= center_y - 1) && (y_reg <= center_y + 1);
                    pixel_data_next = (is_vert_line || is_horiz_line) ? CColorWhite : CColorBlue;
                end

                // --- Horizontálny gradient ---
                MODE_H_GRADIENT: begin
                    // Použijeme horné bity X súradnice pre farby
                    pixel_data_next.red = x_reg[CLog2HRes-1 : CLog2HRes-5]; // 5 bitov
                    pixel_data_next.grn = x_reg[CLog2HRes-1 : CLog2HRes-6]; // 6 bitov
                    pixel_data_next.blu = x_reg[CLog2HRes-1 : CLog2HRes-5]; // 5 bitov
                end

                // --- Vertikálny gradient ---
                MODE_V_GRADIENT: begin
                    // Použijeme horné bity Y súradnice pre farby
                    pixel_data_next.red = y_reg[CLog2VRes-1 : CLog2VRes-5]; // 5 bitov
                    pixel_data_next.grn = y_reg[CLog2VRes-1 : CLog2VRes-6]; // 6 bitov
                    pixel_data_next.blu = y_reg[CLog2VRes-1 : CLog2VRes-5]; // 5 bitov
                end

                // --- Diagonálny posuv (animovaný) ---
                MODE_DIAG_SCROLL: begin
                    logic [CLog2HRes+CLog2VRes:0] sum_xy; // Šírka dostatočná pre x+y+offset
                    sum_xy = x_reg + y_reg + scroll_offset; // Posúva sa diagonálne
                    // Použijeme bity zo súčtu pre farby
                    pixel_data_next.red = sum_xy[CAnimWidth+4 : CAnimWidth];   // 5 bitov
                    pixel_data_next.grn = sum_xy[CAnimWidth+5 : CAnimWidth];   // 6 bitov
                    pixel_data_next.blu = sum_xy[CAnimWidth+4 : CAnimWidth];   // 5 bitov
                end

                // --- Pohyblivý vertikálny pruh (animovaný) ---
                MODE_MOVING_BAR: begin
                    logic bar_on;
                    // Vytvorí pruh široký 16 pixelov, ktorý sa posúva každých 64 pixelov
                    bar_on = ((x_reg + scroll_offset) % 64) < 16;
                    pixel_data_next = bar_on ? CColorRed : CColorBlack;
                end

                // --- Predvolený režim (ak by nastala chyba) ---
                default: begin
                   pixel_data_next = CColorOrange; // Oranžová ako indikátor chyby
                end
            endcase
        end
    end

    // ---------------------------
    // Výstupy AXI4-Stream
    // ---------------------------
    // Pripojíme výstupy z pipeline registrov
    assign m_axis.TVALID = tvalid_reg;
    assign m_axis.TDATA  = pixel_data_reg; // Dáta sú z registra
    assign m_axis.TLAST  = tlast_reg;
    assign m_axis.TUSER  = tuser_reg;

    // Voliteľné signály (nastavené na konštantné hodnoty, ak sú povolené)
    assign m_axis.TKEEP  = (KEEP_WIDTH > 0) ? {KEEP_WIDTH{1'b1}} : '0; // Vždy platné všetky bajty
    assign m_axis.TID    = (ID_WIDTH > 0)   ? {ID_WIDTH{1'b0}}   : '0; // ID = 0
    assign m_axis.TDEST  = (DEST_WIDTH > 0) ? {DEST_WIDTH{1'b0}} : '0; // DEST = 0

endmodule

`default_nettype wire

`endif // AXIS_PICTURE_GENERATOR_SV

