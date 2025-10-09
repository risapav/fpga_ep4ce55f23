`ifndef VGA_LINE_REFACTORED
`define VGA_LINE_REFACTORED

`timescale 1ns/1ns
(* default_nettype = "none" *)

import vga_pkg::*;

// =============================================================================
// Verzia: 2.1 - Refaktorovaná a opravená
// Zmeny:
// - OPRAVA: Časovanie `nol_o` je posunuté o 1 takt pre správnu synchronizáciu.
// - VYLEPŠENIE: Pridané komentáre vysvetľujúce logiku FSM.
// - VYLEPŠENIE: Zjednodušené deklarácie portov.
// =============================================================================
module vga_line #(
    parameter int MAX_COUNTER = MaxLineCounter
)(
    // ZMENA: Zjednodušená deklarácia portov (odstránené nadbytočné `wire`)
    input  logic    clk_i,
    input  logic    rst_ni,
    input  logic    inc_i,
    input  line_t   line_i,
    output logic    de_o,
    output logic    syn_o,
    output logic    eol_o,
    output logic    nol_o
);
    localparam int CounterWidth = $clog2(MAX_COUNTER);

    typedef enum logic [2:0] {
        EOL, ACT, FRP, SYN, BCP
    } state_e;

    state_e state_q;
    logic [CounterWidth-1:0] counter_q;

    //================================================================
    // == ZJEDNOTENÁ SEKVENČNÁ LOGIKA PRE FSM A POČÍTADLO
    //================================================================
    always_ff @(posedge clk_i) begin
        // VYSVETLENIE: FSM sa resetuje do stavu EOL (End of Line). Je to efektívne,
        // pretože pri prvom `inc_i` takte sa okamžite prepne do stavu ACT a začne
        // generovať aktívnu oblasť.
        if (!rst_ni) begin
            state_q   <= EOL;
            counter_q <= '0;
        end else if (inc_i) begin
            unique case (state_q)
                EOL: begin
                    state_q   <= ACT;
                    counter_q <= line_i.visible_area - 1;
                end

                ACT: begin
                    if (counter_q == 0) begin
                        state_q   <= FRP;
                        counter_q <= line_i.front_porch - 1;
                    end else begin
                        counter_q <= counter_q - 1;
                    end
                end

                FRP: begin
                    if (counter_q == 0) begin
                        state_q   <= SYN;
                        counter_q <= line_i.sync_pulse - 1;
                    end else begin
                        counter_q <= counter_q - 1;
                    end
                end

                SYN: begin
                    if (counter_q == 0) begin
                        state_q   <= BCP;
                        // VYSVETLENIE: Načíta sa hodnota `back_porch - 2`.
                        // Dôvod: Stav BCP bude trvať (back_porch - 1) taktov a stav EOL
                        // trvá 1 takt. Spolu je to presne `back_porch` taktov.
                        // UPOZORNENIE: Táto logika vyžaduje, aby `line_i.back_porch` bol >= 2.
                        counter_q <= line_i.back_porch - CounterWidth'(2);
                    end else begin
                        counter_q <= counter_q - 1;
                    end
                end

                BCP: begin
                    if (counter_q == 0) begin
                        state_q   <= EOL;
                        counter_q <= '0;
                    end else begin
                        counter_q <= counter_q - 1;
                    end
                end

                default: begin
                    state_q   <= EOL;
                    counter_q <= '0;
                end
            endcase
        end
    end

    //================================================================
    // == Kombinačná logika pre výstupy
    //================================================================
    assign de_o  = (state_q == ACT);
    assign eol_o = (state_q == EOL);
    assign syn_o = (state_q == SYN); // Generuje "surový" pulz, polarita sa aplikuje o úroveň vyššie

    // ZMENA: Kritická oprava časovania.
    // `nol_o` je teraz aktívne, keď je čítač v stave BCP na nule.
    // To vygeneruje pulz presne 1 takt pred `eol_o`, čo je správne
    // pre taktovanie vertikálneho FSM.
    assign nol_o = (state_q == BCP) && (counter_q == 0);

endmodule

`endif // VGA_LINE_REFACTORED