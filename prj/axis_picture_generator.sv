/**
 * @file        axis_picture_generator.sv
 * @brief       Generátor testovacích obrazcov pre AXI4-Stream.
 * @details     Tento modul generuje rôzne statické a animované obrazce
 * a posiela ich ako AXI4-Stream video dáta vo formáte RGB565.
 * Podporuje rôzne režimy voliteľné vstupom `mode_i`.
 *
 * Zmeny:
 * - OPRAVA (Timing): Pridaný ŠTVRTÝ stupeň pipeline (S0->S1->S2->S3->S4).
 * - OPRAVA (Timing v2): Nahradené pomalé operácie DELENIE (/) a MODULO (%)
 * v kombinačnej logike medzi S1 a S2 za rýchle operácie NÁSOBENIA
 * (s konštantou) a AND (bitová maska), aby sa vyriešil setup time violation.
 * - OPRAVA (Logika v4 - Patch 1, 2, 3):
 * 1. Opravená fixed-point konštanta pre 'COLOR_BARS' na 3276 (z 3277).
 * 2. Opravený výber bitov pre 'DIAG_SCROLL' na nižšie (farebné) bity.
 * 3. Opravený výber bitov pre 'GRADIENT' na rôzne bity pre R/G/B.
 * - OPRAVA (Syntax v5 - Quartus Error 10170):
 * 1. Odstránený bitový výber z výrazu v zátvorke (napr. (x >> 2)[9:4]).
 * 2. Pridané dočasné premenné (napr. x_shifted_g) na uloženie
 * posunutého výsledku pred vykonaním bitového výberu.
 * - OPRAVA (Prenositeľnosť v6):
 * 1. Nahradená statická konštanta 'C_RECIP_HRES_DIV8_Q18'
 * funkciou 'calc_recip_div8_q18(H_RES)', ktorá počíta
 * hodnotu dynamicky na základe parametra H_RES.
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
    axi4s_if.master m_axis
);

    // ---------------------------
    // Lokálne parametre a typy
    // ---------------------------
    localparam int CLog2HRes = $clog2(H_RES);
    localparam int CLog2VRes = $clog2(V_RES);
    localparam int CModeWidth = $clog2(NUM_MODES);

    localparam int CCheckerSizeSmall = 3;
    localparam int CCheckerSizeLarge = 5;
    localparam int CAnimWidth = 8;

    // --- OPRAVA (Prenositeľnosť v6): Konštanty pre fixed-point násobenie ---

    // Funkcia pre automatický výpočet Q18 konštanty pre (x * 8) / H_RES
    // Vypočíta ((2^18) * 8 / H_RES) so správnym zaokrúhlením.
    function automatic int calc_recip_div8_q18 (input int unsigned hres);
        return ( (1 << 18) * 8 + (hres/2) ) / hres;
    endfunction

    // PATCH #1: Nahradenie statickej hodnoty dynamickým výpočtom
    localparam int C_RECIP_HRES_DIV8_Q18 = calc_recip_div8_q18(H_RES);
    localparam int C_Q_SHIFT = 18; // Shift pre Q18

    // Pre MODE_MOVING_BAR: % 64
    localparam int C_MOD_64_MASK = 6'h3F; // 6 bitov (0-63)
    // --- Koniec opravy ---

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

    typedef struct packed {
      logic [4:0] red;
      logic [5:0] grn;
      logic [4:0] blu;
    } rgb565_t;

    localparam rgb565_t
        CColorBlack    = 16'h0000,
        CColorWhite    = 16'hFFFF,
        CColorRed      = 16'hF800,
        CColorGreen    = 16'h07E0,
        CColorBlue     = 16'h001F,
        CColorYellow   = 16'hFFE0,
        CColorCyan     = 16'h07FF,
        CColorMagenta  = 16'hF81F,
        CColorOrange   = 16'hFC00,
        CColorDarkGray = 16'h8410;

    localparam rgb565_t CColorPalette [0:7] = '{
        CColorRed, CColorOrange, CColorYellow, CColorGreen,
        CColorCyan, CColorBlue, CColorMagenta, CColorWhite
    };

    // ---------------------------
    // Interné signály a registre
    // ---------------------------

    // --- Stupeň 0 (Počítadlá) ---
    logic [CLog2HRes-1:0] x_reg, x_next;
    logic [CLog2VRes-1:0] y_reg, y_next;
    logic [CModeWidth-1:0] mode_q;
    logic [CAnimWidth-1:0] scroll_offset;

    logic can_advance;
    logic active_area_comb;
    logic start_of_frame_comb;
    logic end_of_line_comb;

    // --- Stupeň 1 (Registre) ---
    logic [CLog2HRes-1:0] x_s1_reg;
    logic [CLog2VRes-1:0] y_s1_reg;
    logic [CModeWidth-1:0] mode_q_s1_reg;
    logic [CAnimWidth-1:0] scroll_offset_s1_reg;
    logic    active_area_s1_reg;
    logic    eol_s1_reg;
    logic    sof_s1_reg;

    // --- Stupeň 2 (Pomalé výpočty) ---
    logic [3:0] bar_idx_comb_raw; // 4 bity pre detekciu pretečenia (>=8)
    logic [CLog2HRes+CLog2VRes:0] sum_xy_comb;
    logic bar_on_comb;
    // Registre Stupňa 2
    logic [2:0] bar_idx_s2_reg; // Finálny 3-bitový index
    logic [CLog2HRes+CLog2VRes:0] sum_xy_s2_reg;
    logic bar_on_s2_reg;
    // Oneskorené signály (synchronizované so Stupňom 2)
    logic [CLog2HRes-1:0] x_s2_reg;
    logic [CLog2VRes-1:0] y_s2_reg;
    logic [CModeWidth-1:0] mode_q_s2_reg;
    logic    active_area_s2_reg;
    logic    eol_s2_reg;
    logic    sof_s2_reg;

    // --- Stupeň 3 (Multiplexor) ---
    rgb565_t pixel_data_s3_comb;
    // Registre Stupňa 3
    logic    active_area_s3_reg;
    logic    eol_s3_reg;
    logic    sof_s3_reg;
    rgb565_t pixel_data_s3_reg;

    // --- Stupeň 4 (Finálne výstupné registre) ---
    logic                  tvalid_reg_out;
    logic                  tlast_reg_out;
    logic [USER_WIDTH-1:0] tuser_reg_out;
    rgb565_t               pixel_data_reg_out;


    // ---------------------------
    // Stupeň 0: Počítadlá súradníc (X, Y)
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

    always_comb begin
        x_next = x_reg;
        y_next = y_reg;
        if (x_reg == H_RES - 1) begin
            x_next = '0;
            y_next = (y_reg == V_RES - 1) ? '0 : y_reg + 1'b1;
        end else begin
            x_next = x_reg + 1'b1;
        end
    end

    assign active_area_comb    = (x_reg < H_RES) && (y_reg < V_RES);
    assign start_of_frame_comb = (x_reg == 0) && (y_reg == 0);
    assign end_of_line_comb    = (x_reg == H_RES - 1);

    // ---------------------------
    // Stupeň 0: Registre pre režim a animáciu
    // ---------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            mode_q        <= '0;
            scroll_offset <= '0;
        end else if (can_advance) begin
            mode_q <= mode_i;
            if ((x_reg == H_RES - 1) && (y_reg == V_RES - 1)) begin
                scroll_offset <= scroll_offset + 1'b1;
            end
        end
    end

    // ---------------------------
    // Pipeline Stupeň 1: Registrácia vstupov pre pomalé výpočty
    // ---------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            x_s1_reg           <= '0;
            y_s1_reg           <= '0;
            mode_q_s1_reg      <= '0;
            scroll_offset_s1_reg <= '0;
            active_area_s1_reg <= 1'b0;
            eol_s1_reg         <= 1'b0;
            sof_s1_reg         <= 1'b0;
        end else if (can_advance) begin
            x_s1_reg           <= x_reg;
            y_s1_reg           <= y_reg;
            mode_q_s1_reg      <= mode_q;
            scroll_offset_s1_reg <= scroll_offset;
            active_area_s1_reg <= active_area_comb;
            eol_s1_reg         <= end_of_line_comb && active_area_comb;
            sof_s1_reg         <= start_of_frame_comb && active_area_comb;
        end
    end

    // ---------------------------
    // Kombinačná logika pre pomalé operácie (Vstup do Stupňa 2)
    // Používa signály zo Stupňa 1
    // ---------------------------
    always_comb begin
        logic [CLog2HRes + C_Q_SHIFT - 1:0] bar_idx_product;
        logic [CLog2HRes + CAnimWidth : 0] sum_mod_comb;

        // 1. Farebné pruhy (Q18)
        bar_idx_product = x_s1_reg * C_RECIP_HRES_DIV8_Q18; // Použitie dynamickej konštanty
        bar_idx_comb_raw = 4'(bar_idx_product >> C_Q_SHIFT);

        // 2. Pohyblivý pruh (Maska)
        sum_mod_comb = x_s1_reg + scroll_offset_s1_reg;
        bar_on_comb = (sum_mod_comb & C_MOD_64_MASK) < 16;

        // 3. Diagonálny posuv (Sčítanie)
        sum_xy_comb = x_s1_reg + y_s1_reg + scroll_offset_s1_reg;
    end

    // ---------------------------
    // Pipeline Stupeň 2: Registrácia pomalých výpočtov a prenesenie signálov
    // ---------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            bar_idx_s2_reg <= '0;
            sum_xy_s2_reg  <= '0;
            bar_on_s2_reg  <= 1'b0;
            x_s2_reg           <= '0;
            y_s2_reg           <= '0;
            mode_q_s2_reg      <= '0;
            active_area_s2_reg <= 1'b0;
            eol_s2_reg         <= 1'b0;
            sof_s2_reg         <= 1'b0;
        end else if (can_advance) begin
            // Zachytenie VÝSLEDKOV pomalých výpočtov
            // Saturácia indexu farebných pruhov
            bar_idx_s2_reg <= (bar_idx_comb_raw >= 8) ? 3'd7 : 3'(bar_idx_comb_raw);
            sum_xy_s2_reg  <= sum_xy_comb;
            bar_on_s2_reg  <= bar_on_comb;
            // Prenesenie oneskorených signálov (z S1)
            x_s2_reg           <= x_s1_reg;
            y_s2_reg           <= y_s1_reg;
            mode_q_s2_reg      <= mode_q_s1_reg;
            active_area_s2_reg <= active_area_s1_reg;
            eol_s2_reg         <= eol_s1_reg;
            sof_s2_reg         <= sof_s1_reg;
        end
    end

    // ---------------------------
    // Pipeline Stupeň 3: Kombinačný MUX (teraz rýchly)
    // Používa signály zo Stupňa 2
    // ---------------------------
    always_comb begin
        pixel_data_s3_comb = CColorBlack;

        if (active_area_s2_reg) begin
            unique case (mode_e'(mode_q_s2_reg))

                MODE_CHECKER_SMALL: begin
                    pixel_data_s3_comb = (x_s2_reg[CCheckerSizeSmall] ^ y_s2_reg[CCheckerSizeSmall]) ? CColorWhite : CColorBlack;
                end

                MODE_CHECKER_LARGE: begin
                    pixel_data_s3_comb = (x_s2_reg[CCheckerSizeLarge] ^ y_s2_reg[CCheckerSizeLarge]) ? CColorBlue : CColorYellow;
                end

                MODE_COLOR_BARS: begin
                    pixel_data_s3_comb = CColorPalette[bar_idx_s2_reg];
                end

                MODE_CROSSHAIR: begin
                    logic is_vert_line, is_horiz_line;
                    logic [CLog2HRes-1:0] center_x;
                    logic [CLog2VRes-1:0] center_y;
                    center_x = H_RES >> 1;
                    center_y = V_RES >> 1;
                    is_vert_line = (x_s2_reg >= center_x - 1) && (x_s2_reg <= center_x + 1);
                    is_horiz_line = (y_s2_reg >= center_y - 1) && (y_s2_reg <= center_y + 1);
                    pixel_data_s3_comb = (is_vert_line || is_horiz_line) ? CColorWhite : CColorBlue;
                end

                // --- OPRAVA (Logika v4 - Patch 3) ---
                MODE_H_GRADIENT: begin
                    logic [CLog2HRes-1:0] x_shifted_g, x_shifted_b;
                    pixel_data_s3_comb.red =  x_s2_reg[9:5];

                    x_shifted_g = x_s2_reg >> 2;
                    pixel_data_s3_comb.grn = x_shifted_g[9:4];

                    x_shifted_b = x_s2_reg >> 4;
                    pixel_data_s3_comb.blu = x_shifted_b[9:5];
                end

                MODE_V_GRADIENT: begin
                    logic [CLog2VRes-1:0] y_shifted_g, y_shifted_b;
                    pixel_data_s3_comb.red =  y_s2_reg[8:4];

                    y_shifted_g = y_s2_reg >> 2;
                    pixel_data_s3_comb.grn = y_shifted_g[8:3];

                    y_shifted_b = y_s2_reg >> 3;
                    pixel_data_s3_comb.blu = y_shifted_b[8:4];
                end
                // --- Koniec opravy ---

                // --- OPRAVA (Logika v4 - Patch 2) ---
                MODE_DIAG_SCROLL: begin
                    pixel_data_s3_comb.red = sum_xy_s2_reg[4 +: 5];
                    pixel_data_s3_comb.grn = sum_xy_s2_reg[3 +: 6];
                    pixel_data_s3_comb.blu = sum_xy_s2_reg[2 +: 5];
                end
                // --- Koniec opravy ---

                MODE_MOVING_BAR: begin
                    pixel_data_s3_comb = bar_on_s2_reg ? CColorRed : CColorBlack;
                end

                default:
                   pixel_data_s3_comb = CColorOrange;
            endcase
        end
    end

    // ---------------------------
    // Pipeline Stupeň 3: Registrácia MUX výstupu
    // ---------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            active_area_s3_reg <= 1'b0;
            eol_s3_reg         <= 1'b0;
            sof_s3_reg         <= 1'b0;
            pixel_data_s3_reg  <= '0;
        end else if (can_advance) begin
            active_area_s3_reg <= active_area_s2_reg;
            eol_s3_reg         <= eol_s2_reg;
            sof_s3_reg         <= sof_s2_reg;
            pixel_data_s3_reg  <= pixel_data_s3_comb;
        end
    end

    // ---------------------------
    // Pipeline Stupeň 4: Finálne výstupné registre
    // ---------------------------
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            tvalid_reg_out     <= 1'b0;
            tlast_reg_out      <= 1'b0;
            tuser_reg_out      <= '0;
            pixel_data_reg_out <= '0;
        end else if (can_advance) begin
            tvalid_reg_out     <= active_area_s3_reg;
            tlast_reg_out      <= eol_s3_reg;
            tuser_reg_out      <= {USER_WIDTH{sof_s3_reg}};
            pixel_data_reg_out <= pixel_data_s3_reg;
        end
    end

    // ---------------------------
    // Riadenie toku (Handshake)
    // ---------------------------
    assign can_advance = m_axis.TREADY || !tvalid_reg_out;

    // ---------------------------
    // Výstupy AXI4-Stream
    // ---------------------------
    assign m_axis.TVALID = tvalid_reg_out;
    assign m_axis.TDATA  = pixel_data_reg_out;
    assign m_axis.TLAST  = tlast_reg_out;
    assign m_axis.TUSER  = tuser_reg_out;

    assign m_axis.TKEEP  = (KEEP_WIDTH > 0) ? {KEEP_WIDTH{1'b1}} : '0;
    assign m_axis.TID    = (ID_WIDTH > 0)   ? {ID_WIDTH{1'b0}}   : '0;
    assign m_axis.TDEST  = (DEST_WIDTH > 0) ? {DEST_WIDTH{1'b0}} : '0;

endmodule

`default_nettype wire

`endif // AXIS_PICTURE_GENERATOR_SV

