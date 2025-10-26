/**
 * @file        axis_to_vga.sv
 * @brief       AXI-Stream na VGA prevodník s časovaním a registrovaným výstupom.
 * @details     Modul číta AXI4-Stream dáta a generuje farebné (RGB)
 * a synchronizačné (HS, VS) signály pre VGA monitor.
 * Funguje ako master pre VGA časovanie (generuje H/V pulzy)
 * a ako slave pre AXI-Stream (riadi tok dát cez TREADY).
 * Výstupné VGA signály (color, hs, vs) sú registrované pre lepšie časovanie.
 *
 * ZMENY:
 * - Pridané výstupné registre pre vga_color_o, vga_hs_o, vga_vs_o.
 * - Pridané diagnostické výstupy 'hde_o' (Horizontal Data Enable)
 * a 'underrun_o' (indikátor podtečenia vstupných dát).
 *
 * @param H_ACT, H_FP, ...    Parametre VGA časovania pre horizontálu.
 * @param V_ACT, V_FP, ...    Parametre VGA časovania pre vertikálu.
 * @param H_SYNC_POLARITY     Polarita HSync (1=Aktívna HIGH, 0=Aktívna LOW).
 * @param V_SYNC_POLARITY     Polarita VSync.
 * @param OUTPUT_FORMAT       Dátový formát výstupu (888 alebo 565).
 * @param AXI_DATA_WIDTH      Šírka AXI TDATA (musí byť 16 pre 565, 24 pre 888).
 * @param AXI_USER_WIDTH      Šírka AXI TUSER.
 * @param BLANKING_COLOR_...  Farba pre blanking intervaly.
 * @param UNDERRUN_COLOR_...  Farba zobrazená pri podtečení (underrun).
 * @param SYNC_LOSS_COLOR_... Farba zobrazená pri strate AXI synchronizácie (TUSER/TLAST).
 */

`ifndef AXIS_TO_VGA_SV
`define AXIS_TO_VGA_SV

`default_nettype none

import axi_pkg::*;
import vga_pkg::*;

module axis_to_vga #(
    // --- Parametre VGA časovania (napr. z vga_pkg) ---
    parameter int H_ACT = 800, // Horizontal Active
    parameter int H_FP  = 40,  // Horizontal Front Porch
    parameter int H_SP  = 128, // Horizontal Sync Pulse
    parameter int H_BP  = 88,  // Horizontal Back Porch
    parameter int V_ACT = 600, // Vertical Active
    parameter int V_FP  = 1,   // Vertical Front Porch
    parameter int V_SP  = 4,   // Vertical Sync Pulse
    parameter int V_BP  = 23,  // Vertical Back Porch

    // --- Polarita (napr. z vga_pkg) ---
    parameter bit H_SYNC_POLARITY = vga_pkg::PulseActiveHigh,
    parameter bit V_SYNC_POLARITY = vga_pkg::PulseActiveHigh,

    // --- Formát výstupu ---
    parameter int OUTPUT_FORMAT = 565, // 565 (16-bit) alebo 888 (24-bit)

    // --- Parametre AXI Streamu ---
    parameter int AXI_DATA_WIDTH = 16,
    parameter int AXI_USER_WIDTH = 1,

    // --- Farby pre chyby a blanking (závislé od formátu) ---
    parameter logic [23:0] BLANKING_COLOR_888  = 24'h101010,
    parameter logic [23:0] UNDERRUN_COLOR_888  = 24'hFF0000,
    parameter logic [23:0] SYNC_LOSS_COLOR_888 = 24'h00FF00,
    parameter logic [15:0] BLANKING_COLOR_565  = 16'h1082,
    parameter logic [15:0] UNDERRUN_COLOR_565  = 16'hF800,
    parameter logic [15:0] SYNC_LOSS_COLOR_565 = 16'h07E0
)(
    // --- Hodiny a Reset (Pixel Clock Doména) ---
    input  logic clk_i,
    input  logic rst_ni,

    // --- AXI Stream Slave ---
    axi4s_if.slave s_axis,

    // --- VGA Výstup (teraz z registrov) ---
    output logic [ (OUTPUT_FORMAT == 565) ? 15 : 23 : 0 ] vga_color_o,
    output logic vga_hs_o,
    output logic vga_vs_o,

    // --- Diagnostické výstupy ---
    output logic hde_o,
    output logic underrun_o
);

    // --- Lokálne parametre ---
    localparam int CHTotal = H_ACT + H_FP + H_SP + H_BP;
    localparam int CVTotal = V_ACT + V_FP + V_SP + V_BP;

    // --- Signály pre VGA časovanie ---
    logic [LineCounterWidth-1:0] h_count_reg;
    logic [LineCounterWidth-1:0] v_count_reg;
    logic h_sync_comb;
    logic v_sync_comb;
    logic active_area_comb;

    // --- Signály pre monitorovanie AXI Streamu ---
    logic [$clog2(H_ACT)-1:0] axi_x_count_reg;
    logic [$clog2(V_ACT)-1:0] axi_y_count_reg;
    logic is_underrun_comb;
    logic sync_loss_reg;

    // --- Signály pre registrovaný výstup (NOVÉ) ---
    logic [ (OUTPUT_FORMAT == 565) ? 15 : 23 : 0 ] vga_color_next; // Kombinačný vstup do registra farby
    logic vga_hs_next;    // Kombinačný vstup do registra HSync
    logic vga_vs_next;    // Kombinačný vstup do registra VSync

    logic [ (OUTPUT_FORMAT == 565) ? 15 : 23 : 0 ] vga_color_reg; // Registrovaná farba
    logic vga_hs_reg;     // Registrovaný HSync
    logic vga_vs_reg;     // Registrovaný VSync

    // =========================================================================
    // Generátor VGA Časovania (H/V Počítadlá)
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            h_count_reg <= '0;
            v_count_reg <= '0;
        end else begin
            if (h_count_reg == CHTotal - 1) begin
                h_count_reg <= '0;
                if (v_count_reg == CVTotal - 1) begin
                    v_count_reg <= '0;
                end else begin
                    v_count_reg <= v_count_reg + 1'b1;
                end
            end else begin
                h_count_reg <= h_count_reg + 1'b1;
            end
        end
    end

    // Kombinačná logika pre HSync, VSync a Aktívnu Oblasť
    always_comb begin
        h_sync_comb      = (h_count_reg >= H_ACT + H_FP) && (h_count_reg < H_ACT + H_FP + H_SP);
        v_sync_comb      = (v_count_reg >= V_ACT + V_FP) && (v_count_reg < V_ACT + V_FP + V_SP);
        active_area_comb = (h_count_reg < H_ACT) && (v_count_reg < V_ACT);
    end

    // =========================================================================
    // AXI-Stream Handshake a Monitorovanie
    // =========================================================================
    assign s_axis.TREADY = active_area_comb; // Pripravený prijať dáta len v aktívnej oblasti

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            axi_x_count_reg <= '0;
            axi_y_count_reg <= '0;
            sync_loss_reg   <= 1'b0;
        end else begin
            if (h_count_reg == 0 && v_count_reg == 0) begin
                sync_loss_reg <= 1'b0; // Reset chyby na začiatku snímku
            end

            if (s_axis.TVALID && s_axis.TREADY) begin // Ak prebehol platný prenos
                // AXI Počítadlá
                if (axi_x_count_reg == H_ACT - 1) begin
                    axi_x_count_reg <= '0;
                    if (axi_y_count_reg == V_ACT - 1) begin
                        axi_y_count_reg <= '0;
                    end else begin
                        axi_y_count_reg <= axi_y_count_reg + 1'b1;
                    end
                end else begin
                    axi_x_count_reg <= axi_x_count_reg + 1'b1;
                end

                // Detekcia straty synchronizácie
                if (axi_x_count_reg == 0 && axi_y_count_reg == 0 && !s_axis.TUSER) begin
                    sync_loss_reg <= 1'b1;
                end
                if (axi_x_count_reg == H_ACT - 1 && !s_axis.TLAST) begin
                    sync_loss_reg <= 1'b1;
                end
                if (axi_x_count_reg != H_ACT - 1 && s_axis.TLAST) begin
                    sync_loss_reg <= 1'b1;
                end
            end
        end
    end

    assign is_underrun_comb = active_area_comb && !s_axis.TVALID; // Underrun

    // =========================================================================
    // Kombinačná Logika pre Výstupy (pred registráciou)
    // =========================================================================
    generate
        if (OUTPUT_FORMAT == 888) begin : gen_rgb888
            always_comb begin
                if (sync_loss_reg) begin
                    vga_color_next = SYNC_LOSS_COLOR_888;
                end else if (is_underrun_comb) begin
                    vga_color_next = UNDERRUN_COLOR_888;
                end else if (active_area_comb) begin
                    vga_color_next = s_axis.TDATA[23:0];
                end else begin
                    vga_color_next = BLANKING_COLOR_888;
                end
            end
        end else begin : gen_rgb565
            always_comb begin
                if (sync_loss_reg) begin
                    vga_color_next = SYNC_LOSS_COLOR_565;
                end else if (is_underrun_comb) begin
                    vga_color_next = UNDERRUN_COLOR_565;
                end else if (active_area_comb) begin
                  vga_color_next = vga_pkg::BLUE; // Modrá pre 565
//                    vga_color_next = s_axis.TDATA[15:0];
                end else begin
                    vga_color_next = BLANKING_COLOR_565;
                end
            end
        end
    endgenerate

    // Kombinačné signály pre HSync a VSync (vrátane polarity)
    assign vga_hs_next = h_sync_comb ^ ~H_SYNC_POLARITY;
    assign vga_vs_next = v_sync_comb ^ ~V_SYNC_POLARITY;

    // =========================================================================
    // Registrácia Výstupných Signálov (NOVÉ)
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            // Reset výstupov na bezpečné hodnoty
            vga_color_reg <= '0; // Čierna farba
            vga_hs_reg    <= 1'b1 ^ ~H_SYNC_POLARITY; // Neaktívny HSync
            vga_vs_reg    <= 1'b1 ^ ~V_SYNC_POLARITY; // Neaktívny VSync
        end else begin
            // Preklopenie vypočítaných hodnôt
            vga_color_reg <= vga_color_next;
            vga_hs_reg    <= vga_hs_next;
            vga_vs_reg    <= vga_vs_next;
        end
    end

    // =========================================================================
    // Finálne Priradenie Výstupov (teraz z registrov)
    // =========================================================================
    assign vga_color_o = vga_color_reg;
    assign vga_hs_o    = vga_hs_reg;
    assign vga_vs_o    = vga_vs_reg;

    // Diagnostické výstupy zostávajú kombinačné
    assign hde_o       = active_area_comb;
    assign underrun_o  = is_underrun_comb;

endmodule

`default_nettype wire

`endif // AXIS_TO_VGA_SV

