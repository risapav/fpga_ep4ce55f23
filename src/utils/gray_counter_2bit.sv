/**
 * @file        gray_counter_2bit.sv
 * @brief       Synchrónny 2-bitový čítač s Grayovým kódom.
 * @details     Modul implementuje 2-bitový čítač, ktorý prechádza sekvenciou
 * Grayovho kódu: 00 -> 01 -> 11 -> 10 -> 00 ...
 * Čítač má asynchrónny reset (aktívny v nule) a synchrónne povolenie (enable).
 * Pri resete je výstup nastavený na 2'b00.
 * Ak je povolenie neaktívne, čítač si drží svoju aktuálnu hodnotu.
 *
 * @input  clk_i         Vstupný hodinový signál.
 * @input  rst_ni        Asynchrónny reset, aktívny v nule.
 * @input  en_i          Synchrónne povolenie čítania.
 * @output gray_count_o  Výstupná 2-bitová hodnota Grayovho kódu.
 */

`default_nettype none

`ifndef GRAY_COUNTER_2BIT_SV
`define GRAY_COUNTER_2BIT_SV

module gray_counter_2bit (
    input  wire logic       clk_i,
    input  wire logic       rst_ni,
    input  wire logic       en_i,
    output      logic [1:0] gray_count_o
);

    // Interne registre pre súčasný a nasledujúci stav
    logic [1:0] gray_count_q;
    logic [1:0] gray_count_d;

    // Sekvenčná logika: registre (klopné obvody)
    // - Asynchrónny reset
    // - Synchrónna zmena stavu pri povolení
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            gray_count_q <= 2'b00;
            // Logika pre reset (pôvodná chyba opravená)
        end else if (en_i) begin
            gray_count_q <= gray_count_d; // Načítanie nasledujúceho stavu
        end
        // Ak en_i je '0', gray_count_q si udrží svoju hodnotu (implicitne)
    end

    // Kombinačná logika: logika pre nasledujúci stav
    // Definuje prechodovú funkciu čítača podľa Grayovej sekvencie
    always_comb begin
        case (gray_count_q)
            2'b00:   gray_count_d = 2'b01;
            2'b01:   gray_count_d = 2'b11;
            2'b11:   gray_count_d = 2'b10;
            2'b10:   gray_count_d = 2'b00;
            default: gray_count_d = 2'b00; // Zabezpečenie proti nelegálnym stavom
        endcase
    end

    // Priradenie výstupu
    // Výstup je priamo hodnota z registra
    assign gray_count_o = gray_count_q;

endmodule

`endif // GRAY_COUNTER_2BIT_SV

`default_nettype wire
