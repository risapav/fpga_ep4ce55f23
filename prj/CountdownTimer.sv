/**
 * @file        CountdownTimer.sv
 * @brief       Generický modul pre odpočítavací časovač.
 * @details     Tento modul implementuje jednoduchý časovač, ktorý odpočítava
 * od načítanej hodnoty (`load_val`) až po nulu. Keď dosiahne nulu,
 * aktivuje výstup `done`.
 *
 * Zmeny v v1.2:
 * - OPRAVA (Deadlock): Logika 'done_next' je teraz aktívna, len ak
 * 'count_reg == 0' A ZÁROVEŇ 'load == 0'. Tým sa zabráni
 * falošnému signálu 'done' počas resetu/nabíjania.
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
    logic [COUNT_WIDTH-1:0] count_reg;
    logic [COUNT_WIDTH-1:0] count_next;
    logic                   done_next;

    // -----------------------------------------------------
    // Register počítadla
    // -----------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rstn)
            count_reg <= '0;
        else
            count_reg <= count_next;
    end

    // -----------------------------------------------------
    // Kombinačná logika pre odpočet a výstup 'done'
    // -----------------------------------------------------
    always_comb begin
        // Výpočet ďalšej hodnoty počítadla
        if (load) begin
            count_next = load_val;
        end else if (count_reg > 0) begin
            count_next = count_reg - 1'b1;
        end else begin
            count_next = count_reg;
        end

        // OPRAVA (v1.2): 'done' je aktívny, len ak sme na 0 A NENABÍJAME
        done_next = (count_reg == 0) && !load;
    end

    // -----------------------------------------------------
    // Výstup 'done' (kombinačný alebo registrovaný)
    // -----------------------------------------------------
    generate
        if (DONE_REGISTERED) begin : g_done_reg_block
            logic done_reg;

            always_ff @(posedge clk) begin
                if (!rstn)
                    done_reg <= 1'b0;
                else
                    done_reg <= done_next;
            end

            assign done = done_reg;

        end else begin : g_done_comb_block
            assign done = done_next;
        end
    endgenerate

endmodule

`default_nettype wire

`endif // COUNTDOWN_TIMER_SV

