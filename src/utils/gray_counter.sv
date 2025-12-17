`ifndef GRAY_COUNTER_2BIT_SV
`define GRAY_COUNTER_2BIT_SV

/**
 * @file        gray_counter_2bit.sv
 * @brief       Synchronny 2-bitovy citac s Grayovym kodom.
 * @details     Modul implementuje 2-bitovy citac, ktory prechadza sekvenciou
 *              Grayovho kodu: 00 -> 01 -> 11 -> 10 -> 00 ...
 *              Citac ma asynchronny aktivny v nule reset a synchronne povolenie (enable).
 *              Pri resete je vystup nastaveny na 2'b00.
 *              Ak je povolenie neaktivne, citac si drzi svoju aktualnu hodnotu.
 */

`default_nettype none

module gray_counter_2bit
(
    input  logic        i_clk,       // Vstupny hodinovy signal
    input  logic        i_rst_n,     // Asynchronny reset, aktivny v nule
    input  logic        i_en,        // Synchronne povolenie citania
    output logic [1:0]  o_gray_count // Vystupna 2-bitova hodnota Grayovho kodu
);

    // Interne registre pre sucasny a nasledujuci stav
    logic [1:0] gray_count_q;
    logic [1:0] gray_count_d;

    // Sekvencna logika: registre (klopne obvody)
    // - Asynchronny reset
    // - Synchronna zmena stavu pri povoleni
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            gray_count_q <= 2'b00;
         Logika pre reset
        end
        else if (i_en) begin
            gray_count_q <= gray_count_d; // Nacitanie nasledujuceho stavu
        end
        // Ak i_en je '0', gray_count_q si udrzi svoju hodnotu (implicitne)
    end

    // Kombinacna logika: logika pre nasledujuci stav
    // Definuje prechodovu funkciu citaca podla Grayovej sekvencie
    always_comb begin
        case (gray_count_q)
            2'b00:   gray_count_d = 2'b01;
            2'b01:   gray_count_d = 2'b11;
            2'b11:   gray_count_d = 2'b10;
            2'b10:   gray_count_d = 2'b00;
            default: gray_count_d = 2'b00; // Zabezpecenie proti nelegalnym stavom
        endcase
    end

    // Priradenie vystupu
    // Vystup je priamo hodnota z registra
    assign o_gray_count = gray_count_q;

endmodule

`endif // GRAY_COUNTER_2BIT_SV
