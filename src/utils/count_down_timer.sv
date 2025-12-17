/**
 * @file        count_down_timer.sv
 * @brief       Generický odpočítavací časovač.
 * @details     Modul pre odpočítavanie s podporou nahrávania (load) a saturáciou na nule.
 * Umožňuje voľbu medzi kombinačným a registrovaným výstupom 'done'.
 *
 * @param COUNT_WIDTH     Šírka interného počítadla.
 * @param DONE_REGISTERED 1 = registrovaný výstup (latencia 1 takt), 0 = kombinačný.
 *
 * @input  clk_i       Hodinový signál.
 * @input  rst_ni      Asynchrónny reset (active-low).
 * @input  load_i      Signál pre nahranie počiatočnej hodnoty.
 * @input  load_val_i  Počiatočná hodnota počítadla.
 * @output done_o      Indikácia, že počítadlo dosiahlo nulu.
 */

`default_nettype none

`ifndef COUNT_DOWN_TIMER_SV
`define COUNT_DOWN_TIMER_SV

module count_down_timer #(
    parameter int COUNT_WIDTH     = 4,
    parameter bit DONE_REGISTERED = 1
)(
    input  logic                   clk_i,
    input  logic                   rst_ni, // Premenované z arstn_i pre konzistenciu
    input  logic                   load_i,
    input  logic [COUNT_WIDTH-1:0] load_val_i,
    output logic                   done_o
);

    // -------------------------------------------------------------------------
    // 1. Interné registre a signály
    // -------------------------------------------------------------------------
    logic [COUNT_WIDTH-1:0] count_reg;
    logic [COUNT_WIDTH-1:0] count_next;
    logic                   done_next;

    // -------------------------------------------------------------------------
    // 2. Logika Počítadla (Sequential)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_reg <= '0;
        end else begin
            count_reg <= count_next;
        end
    end

    // -------------------------------------------------------------------------
    // 3. Logika Ďalšieho Stavu (Combinatorial)
    // -------------------------------------------------------------------------
    always_comb begin
        count_next = count_reg;

        if (load_i) begin
            // Prioritné nahrávanie novej hodnoty
            count_next = load_val_i;
        end else if (count_reg > '0) begin
            // Odpočítavanie (saturácia na 0)
            count_next = count_reg - 1'b1;
        end
        // Ak je count_reg == 0 a nie je load, hodnota zostáva 0 (implicitne)

        // Výpočet done flagu (aktívny, ak je nula a nenahrávame novú hodnotu)
        done_next = (count_reg == '0) && !load_i;
    end

    // -------------------------------------------------------------------------
    // 4. Logika Výstupu (Generovanie)
    // -------------------------------------------------------------------------
    generate
        if (DONE_REGISTERED) begin : g_done_registered
            // Registrovaný výstup (pre lepší timing, latencia +1 takt)
            logic done_reg;

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    done_reg <= 1'b0;
                end else begin
                    done_reg <= done_next;
                end
            end

            assign done_o = done_reg;

        end else begin : g_done_comb
            // Kombinačný výstup (ihneď, horší timing path)
            assign done_o = done_next;
        end
    endgenerate

endmodule

`endif // COUNT_DOWN_TIMER_SV

`default_nettype wire
