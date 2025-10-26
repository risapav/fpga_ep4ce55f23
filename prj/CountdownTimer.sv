/**
 * @file        CountdownTimer.sv
 * @brief       Generický modul pre odpočítavací časovač.
 * @details     Tento modul implementuje jednoduchý časovač, ktorý odpočítava
 * od načítanej hodnoty (`load_val`) až po nulu. Keď dosiahne nulu,
 * aktivuje výstup `done`.
 *
 * Zmeny:
 * - Odstránené použitie '$bits' pri dekrementácii pre lepšiu kompatibilitu.
 * - Pridaný `ifndef` guard.
 * - Detailnejšie komentáre.
 * - Opravená syntax '{0} na '0.
 *
 * @param COUNT_WIDTH     Šírka počítadla (určuje maximálnu hodnotu odpočtu).
 * @param DONE_REGISTERED Výstup `done` (1 = registrovaný, 0 = kombinačný).
 */

`ifndef COUNTDOWN_TIMER_SV
`define COUNTDOWN_TIMER_SV

`default_nettype none

module CountdownTimer #(
    parameter int COUNT_WIDTH     = 4,
    parameter bit DONE_REGISTERED = 0     // Predvolene kombinačný výstup
)(
    input  logic clk,                  // Hodinový signál
    input  logic rstn,                 // Reset, aktívny v nízkej úrovni
    input  logic load,                 // Signál na načítanie novej hodnoty
    input  logic [COUNT_WIDTH-1:0] load_val, // Hodnota na načítanie
    output logic done                  // Výstup: časovač dobehol (dosiahol 0)
);

    // Interné registre a signály
    logic [COUNT_WIDTH-1:0] count_reg;  // Register držiaci aktuálnu hodnotu počítadla
    logic [COUNT_WIDTH-1:0] count_next; // Kombinačná logika pre ďalšiu hodnotu
    logic                   done_next;  // Kombinačná logika pre výstup 'done'

    // -----------------------------------------------------
    // Register počítadla (s podporou synch/asynch resetu)
    // -----------------------------------------------------
    // Synchrónny reset: reaguje na rstn len pri hrane hodín
    always_ff @(posedge clk) begin
        if (!rstn)
            count_reg <= '0; // Reset na 0
        else
            count_reg <= count_next; // Inak preklopí ďalšiu hodnotu
    end

    // -----------------------------------------------------
    // Kombinačná logika pre odpočet a výstup 'done'
    // -----------------------------------------------------
    always_comb begin
        // Výpočet ďalšej hodnoty počítadla
        if (load) begin
            count_next = load_val; // Ak je 'load' aktívny, načítame novú hodnotu
        end else if (count_reg > 0) begin // Kontrola '!='0 je bezpečnejšia ako '>'0
            count_next = count_reg - 1'b1; // Ak nie sme na 0, odpočítame 1 (Odstránené $bits)
        end else begin
            count_next = count_reg; // Ak sme na 0 (alebo pri resete), zostaneme na 0
        end

        // Výpočet výstupu 'done'
        done_next = (count_reg == 0); // 'done' je aktívny, keď počítadlo dosiahne 0
    end

    // -----------------------------------------------------
    // Výstup 'done' (kombinačný alebo registrovaný)
    // -----------------------------------------------------
    generate
        if (DONE_REGISTERED) begin : g_done_reg_block
            logic done_reg; // Interný register pre 'done'

            // Registrovaný výstup (pridáva 1 takt latencie)
            always_ff @(posedge clk) begin
                if (!rstn)
                    done_reg <= 1'b0; // Reset na 0
                else
                    done_reg <= done_next; // Preklopí vypočítanú hodnotu
            end

            assign done = done_reg; // Priradenie registrovaného signálu na výstup

        end else begin : g_done_comb_block
            // Kombinačný výstup (rýchlejší, ale môže byť horší pre časovanie)
            assign done = done_next; // Priame priradenie kombinačného signálu
        end
    endgenerate

endmodule

`default_nettype wire // Obnovenie predvoleného typu siete

`endif // COUNTDOWN_TIMER_SV

