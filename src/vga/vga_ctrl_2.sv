`ifndef VGA_CTRL_REFACTORED_FIXED
`define VGA_CTRL_REFACTORED_FIXED

`timescale 1ns/1ns
(* default_nettype = "none" *)

import vga_pkg::*;

module vga_ctrl #(
    parameter vga_data_t BLANKING_COLOR = BLUE,
    parameter vga_data_t UNDERRUN_COLOR = PURPLE,
    parameter int MAX_COUNTER_H = 2047,
    parameter int MAX_COUNTER_V = 2047
)(
    // --- Vstupy ---
    input  wire logic clk_i,
    input  wire logic rst_ni,
    input  wire logic enable_i,
    input  line_t     h_line_i,
    input  line_t     v_line_i,
    input  vga_data_t fifo_data_i,
    input  wire logic fifo_empty_i,

    // --- Výstupy ---
    output logic      hde_o,
    output logic      vde_o,
    output vga_data_t dat_o,
    output vga_sync_t syn_o,
    output logic      eol_o,
    output logic      eof_o,
    output logic      fifo_rd_en_o
);

    // =========================================================================
    // ==         LOKÁLNE PREMENNÉ PRE JEDNODUCHŠÍ PRÍSTUP K ČASOVANIU        ==
    // =========================================================================
    // Vytiahneme si hodnoty zo štruktúr do lokálnych premenných pre lepšiu čitateľnosť.

    // Horizontálne časovanie
    logic [$clog2(MAX_COUNTER_H)-1:0] h_active, h_fp, h_sync, h_bp, h_total;
    // Vertikálne časovanie
    logic [$clog2(MAX_COUNTER_V)-1:0] v_active, v_fp, v_sync, v_bp, v_total;

    // Priradenie hodnôt zo vstupných štruktúr
    assign h_active = h_line_i.visible_area;
    assign h_fp     = h_line_i.front_porch;
    assign h_sync   = h_line_i.sync_pulse;
    assign h_bp     = h_line_i.back_porch;
    assign h_total  = h_active + h_fp + h_sync + h_bp;

    assign v_active = v_line_i.visible_area;
    assign v_fp     = v_line_i.front_porch;
    assign v_sync   = v_line_i.sync_pulse;
    assign v_bp     = v_line_i.back_porch;
    assign v_total  = v_active + v_fp + v_sync + v_bp;
    // =========================================================================
    // ==                     ČÍTAČE A RIADIACE SIGNÁLY                     ==
    // =========================================================================
    logic [$clog2(MAX_COUNTER_H)-1:0] h_count;
    logic [$clog2(MAX_COUNTER_V)-1:0] v_count;
    logic hde_d, vde_d, hsyn_d, vsyn_d, eol_d;

    // =========================================================================
    // ==                    SEKVENČNÁ LOGIKA ČÍTAČOV                       ==
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            h_count <= '0;
            v_count <= '0;
        end else if (enable_i) begin
            if (h_count == h_total - 1) begin
                h_count <= '0;
            end else begin
                h_count <= h_count + 1;
            end

            if (h_count == h_total - 1) begin
                if (v_count == v_total - 1) begin
                    v_count <= '0;
                end else begin
                    v_count <= v_count + 1;
                end
            end
        end
    end

    // =========================================================================
    // ==                    KOMBINAČNÁ LOGIKA ČASOVANIA                    ==
    // =========================================================================
    assign hde_d = (h_count >= (h_sync + h_bp)) && (h_count < (h_sync + h_bp + h_active));
    assign vde_d = (v_count >= (v_sync + v_bp)) && (v_count < (v_sync + v_bp + v_active));
    assign hsyn_d = (h_count < h_sync);
    assign vsyn_d = (v_count < v_sync);
    assign eol_d = (h_count == h_total - 1);

    // =========================================================================
    // ==         ZMENA #1: INTELIGENTNÉ RIADENIE ČÍTANIA Z FIFO            ==
    // =========================================================================
    // Čítame z FIFO, len ak máme zobrazovať pixel A ZÁROVEŇ vo FIFO niečo je.
    // Týmto sa zabráni desynchronizácii.
    assign fifo_rd_en_o = hde_d && vde_d && !fifo_empty_i;

    // =========================================================================
    // ==        ZMENA #2: ROBUSTNÁ VÝSTUPNÁ VRSTVA S PAMÄŤOU FARBY         ==
    // =========================================================================
    vga_data_t vga_data_reg; // Register, ktorý si pamätá poslednú platnú farbu

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            hde_o <= 1'b0;
            vde_o <= 1'b0;
            syn_o <= '{hs: 1'b1, vs: 1'b1};
            eol_o <= 1'b0;
            eof_o <= 1'b0;
            vga_data_reg <= BLANKING_COLOR;
        end else if (enable_i) begin
            // Registrujeme riadiace signály (bez zmeny)
            hde_o <= hde_d;
            vde_o <= vde_d;
            eol_o <= eol_d;
            eof_o <= eol_d && (v_count == v_total - 1);
            syn_o.hs <= (hsyn_d != h_line_i.polarity);
            syn_o.vs <= (vsyn_d != v_line_i.polarity);

            // Nová logika pre výstupnú farbu
            if (hde_d && vde_d) begin // Ak sme v aktívnej oblasti...
                if (!fifo_empty_i) begin
                    // ...a vo FIFO sú dáta, načítaj novú farbu.
                    vga_data_reg <= fifo_data_i;
                end
                // Ak je FIFO prázdne, nerobíme NIČ. Register si jednoducho
                // podrží poslednú platnú farbu, čím efektívne "zamaskuje"
                // krátky výpadok dát a zabráni zobrazeniu čiernej/fialovej.
            end else begin
                // Mimo aktívnej oblasti zobrazujeme farbu pozadia.
                vga_data_reg <= BLANKING_COLOR;
            end
        end
    end

    // Finálny výstup je teraz z nášho robustného registra.
    assign dat_o = vga_data_reg;

endmodule

`endif // VGA_CTRL_REFACTORED_FIXED
