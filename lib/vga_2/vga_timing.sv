// vga_timing.sv - Vylepšený a robustný VGA časovací generátor
//
// Verzia 3.1 - Refaktoring, typová čistota, komentáre

`ifndef VGA_TIMING_DONE
`define VGA_TIMING_DONE

`default_nettype none

import vga_pkg::*;

module Vga_timing #(
    // Parametre pre šírku počítadiel - získané automaticky z package.
//    parameter int H_WIDTH = $bits(vga_pkg::line_t::visible_area),
//    parameter int V_WIDTH = $bits(vga_pkg::line_t::visible_area),
    parameter int H_WIDTH = vga_pkg::LINE_WIDTH,
    parameter int V_WIDTH = vga_pkg::LINE_WIDTH,	 

    // Výber výstupnej logiky:
    // 0 = registrovaný (odporúčaný, bezpečný)
    // 1 = kombinačný (rýchlejší, ale potenciálne hazardný)
    parameter bit COMBILOGIC = 0
)(
    input  logic      clk_pix,   // Hlavný pixelový hodinový signál
    input  logic      rstn,      // Asynchrónny reset (aktívny v L)
    input  line_t     h_line,    // Horizontálne parametre časovania
    input  line_t     v_line,    // Vertikálne parametre časovania
    output position_t pos,       // Aktuálna pozícia vo frame (x, y)
    output signal_t   signal     // Synchronizačné a aktívne výstupy
);

    // --- Počítadlá pozície ---
    logic [H_WIDTH-1:0] pos_x;   // Počítadlo horizontálnej pozície
    logic [V_WIDTH-1:0] pos_y;   // Počítadlo vertikálnej pozície

    assign pos = '{x: pos_x, y: pos_y};

    // --- FSM výstupy ---
    fsm_output_t h_out, v_out;

    // --- Výpočet celkovej dĺžky periódy ---
    // Predpoklad: get_total() vracia 14-bitovú hodnotu
    typedef logic [13:0] total_t;
    total_t h_total, v_total;

    assign h_total = get_total(h_line);
    assign v_total = get_total(v_line);

    // --- Detekcia konca riadku a snímky ---
    wire end_of_line  = (pos_x == h_total - 1);
    wire end_of_frame = (pos_y == v_total - 1);

    // === Horizontálne počítadlo (x-ová pozícia) ===
    always_ff @(posedge clk_pix) begin
        if (!rstn)            pos_x <= 'd0;
        else if (end_of_line) pos_x <= 'd0;
        else                  pos_x <= pos_x + 1;
    end

    // === Vertikálne počítadlo (y-ová pozícia) ===
    // Inkrementuje sa iba na konci riadku
    always_ff @(posedge clk_pix) begin
        if (!rstn) begin
            pos_y <= 'd0;
        end else if (end_of_line) begin
            pos_y <= (end_of_frame) ? 'd0 : pos_y + 1;
        end
    end

    // === FSM moduly pre H a V signály ===
    vga_fsm #(.WIDTH(H_WIDTH)) h_fsm_inst (
        .clk(clk_pix),
        .rstn(rstn),
        .pos(pos_x),
        .line(h_line),
        .out(h_out)
        // .state() môže byť doplnený pre diagnostiku
    );

    vga_fsm #(.WIDTH(V_WIDTH)) v_fsm_inst (
        .clk(clk_pix),
        .rstn(rstn),
        .pos(pos_y),
        .line(v_line),
        .out(v_out)
    );

    // === Výstupná logika ===
    generate
        if (COMBILOGIC == 0) begin : REG_LOGIC
            // === Registrovaný výstup (synchronizovaný, bez hazardov) ===
            always_ff @(posedge clk_pix) begin
                if (!rstn) begin
                    // Bezpečný stav počas resetu
                    signal.active <= 1'b0;
                    signal.blank  <= 1'b1;
                    signal.h_sync <= ~h_line.polarity;  // Neaktívny sync
                    signal.v_sync <= ~v_line.polarity;
                end else begin
                    signal.active <= h_out.active & v_out.active;
                    signal.blank  <= h_out.blank  | v_out.blank;
                    signal.h_sync <= (h_line.polarity) ? h_out.sync : ~h_out.sync;
                    signal.v_sync <= (v_line.polarity) ? v_out.sync : ~v_out.sync;
                end
            end
        end else begin : COMB_LOGIC
            // === Kombinačný výstup (nízka latencia, náchylný na glitch) ===
            always_comb begin
                signal.active = h_out.active & v_out.active;
                signal.blank  = h_out.blank  | v_out.blank;
                signal.h_sync = (h_line.polarity) ? h_out.sync : ~h_out.sync;
                signal.v_sync = (v_line.polarity) ? v_out.sync : ~v_out.sync;
            end
        end
    endgenerate

endmodule

`endif // VGA_TIMING_DONE
