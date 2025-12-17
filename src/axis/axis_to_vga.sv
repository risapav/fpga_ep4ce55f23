/**
 * @file        axis_to_vga.sv
 * @brief       AXI-Stream na VGA prevodník s časovaním a registrovaným výstupom.
 * @details     Modul číta AXI4-Stream dáta a generuje VGA signály.
 * Implementuje slave rozhranie s back-pressure riadeným aktívnou oblasťou.
 * Všetky výstupy sú registrované pre čisté časovanie.
 *
 * @param H_ACT              Aktívne pixely horizontálne.
 * @param H_FP               Front Porch horizontálne.
 * @param H_SP               Sync Pulse horizontálne.
 * @param H_BP               Back Porch horizontálne.
 * @param V_ACT              Aktívne riadky vertikálne.
 * @param V_FP               Front Porch vertikálne.
 * @param V_SP               Sync Pulse vertikálne.
 * @param V_BP               Back Porch vertikálne.
 * @param H_SYNC_POLARITY    Polarita HSync (1=Active High).
 * @param V_SYNC_POLARITY    Polarita VSync (1=Active High).
 * @param OUTPUT_FORMAT      Formát farby (565 alebo 888).
 * @param AXI_DATA_WIDTH     Šírka vstupu (16 alebo 24+).
 * @param BLANKING_COLOR_888 Farba pozadia pre 888.
 * @param BLANKING_COLOR_565 Farba pozadia pre 565.
 */

`ifndef AXIS_TO_VGA_SV
`define AXIS_TO_VGA_SV

`default_nettype none

import axi_pkg::*;
import vga_pkg::*;

module axis_to_vga #(
    // --- Parametre VGA časovania ---
    parameter int H_ACT = 800,
    parameter int H_FP  = 40,
    parameter int H_SP  = 128,
    parameter int H_BP  = 88,
    parameter int V_ACT = 600,
    parameter int V_FP  = 1,
    parameter int V_SP  = 4,
    parameter int V_BP  = 23,

    // --- Parametre polarity ---
    parameter bit H_SYNC_POLARITY = vga_pkg::PulseActiveHigh,
    parameter bit V_SYNC_POLARITY = vga_pkg::PulseActiveHigh,

    // --- Konfigurácia ---
    parameter int OUTPUT_FORMAT = 565, // 565 alebo 888
    parameter int AXI_DATA_WIDTH = 16,
    parameter int AXI_USER_WIDTH = 1,

    // --- Farby ---
    parameter logic [23:0] BLANKING_COLOR_888 = 24'h101010,
    parameter logic [15:0] BLANKING_COLOR_565 = 16'h1082
)(
    // --- Hodiny a Reset ---
    input  wire logic clk_i,
    input  wire logic rst_ni, // Asynchrónny reset

    // --- AXI Stream Slave ---
    axi4s_if.slave    s_axis,

    // --- VGA Výstup ---
    output logic [(OUTPUT_FORMAT == 565 ? 15 : 23):0] vga_color_o,
    output logic                                      vga_hs_o,
    output logic                                      vga_vs_o,
    output logic                                      hde_o
);

    // -------------------------------------------------------------------------
    // 1. Konštanty a Signály
    // -------------------------------------------------------------------------
    localparam int CHTotal = H_ACT + H_FP + H_SP + H_BP;
    localparam int CVTotal = V_ACT + V_FP + V_SP + V_BP;
    
    // Šírka výstupnej farby
    localparam int ColorWidth = (OUTPUT_FORMAT == 565) ? 16 : 24;

    // Počítadlá
    logic [vga_pkg::LineCounterWidth-1:0] h_count_reg;
    logic [vga_pkg::LineCounterWidth-1:0] v_count_reg;

    // Kombinačná logika
    logic h_sync_comb;
    logic v_sync_comb;
    logic active_area_comb;

    // Pipeline (Next & Reg)
    logic [ColorWidth-1:0] vga_color_next;
    logic                  vga_hs_next;
    logic                  vga_vs_next;
    logic                  vga_de_next; // Data Enable Next

    logic [ColorWidth-1:0] vga_color_reg;
    logic                  vga_hs_reg;
    logic                  vga_vs_reg;
    logic                  vga_de_reg;  // Data Enable Reg

    // -------------------------------------------------------------------------
    // 2. Generátor VGA Časovania
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
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

    always_comb begin
        // Sync pulzy
        h_sync_comb = (h_count_reg >= H_ACT + H_FP) && (h_count_reg < H_ACT + H_FP + H_SP);
        v_sync_comb = (v_count_reg >= V_ACT + V_FP) && (v_count_reg < V_ACT + V_FP + V_SP);
        
        // Aktívna oblasť (Video on)
        active_area_comb = (h_count_reg < H_ACT) && (v_count_reg < V_ACT);
    end

    // -------------------------------------------------------------------------
    // 3. AXI-Stream Handshake
    // -------------------------------------------------------------------------
    // Prijímame dáta len v aktívnej oblasti
    assign s_axis.TREADY = active_area_comb;

    // -------------------------------------------------------------------------
    // 4. Spracovanie Dát a Synchronizácie
    // -------------------------------------------------------------------------
    
    // Výber formátu farby
    generate
        if (OUTPUT_FORMAT == 888) begin : gen_rgb888
            always_comb begin
                if (active_area_comb && s_axis.TVALID) begin
                    vga_color_next = s_axis.TDATA[23:0];
                end else begin
                    vga_color_next = BLANKING_COLOR_888;
                end
            end
        end else begin : gen_rgb565
            always_comb begin
                if (active_area_comb && s_axis.TVALID) begin
                    vga_color_next = s_axis.TDATA[15:0];
                end else begin
                    vga_color_next = BLANKING_COLOR_565;
                end
            end
        end
    endgenerate

    // Aplikácia polarity
    assign vga_hs_next = h_sync_comb ^ ~H_SYNC_POLARITY;
    assign vga_vs_next = v_sync_comb ^ ~V_SYNC_POLARITY;
    assign vga_de_next = active_area_comb;

    // -------------------------------------------------------------------------
    // 5. Registrácia Výstupov (Output Stage)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            vga_color_reg <= '0;
            vga_hs_reg    <= 1'b1 ^ ~H_SYNC_POLARITY; // Default inactive
            vga_vs_reg    <= 1'b1 ^ ~V_SYNC_POLARITY; // Default inactive
            vga_de_reg    <= 1'b0;
        end else begin
            vga_color_reg <= vga_color_next;
            vga_hs_reg    <= vga_hs_next;
            vga_vs_reg    <= vga_vs_next;
            vga_de_reg    <= vga_de_next;
        end
    end

    // -------------------------------------------------------------------------
    // 6. Mapovanie Výstupov
    // -------------------------------------------------------------------------
    assign vga_color_o = vga_color_reg;
    assign vga_hs_o    = vga_hs_reg;
    assign vga_vs_o    = vga_vs_reg;
    assign hde_o       = vga_de_reg; // Teraz je HDE synchrónne s dátami

endmodule

`default_nettype wire

`endif // AXIS_TO_VGA_SV
