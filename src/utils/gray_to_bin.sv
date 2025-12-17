/**
 * @file        gray_to_bin.sv
 * @brief       Kombinačný prevodník z Gray kódu na binárny.
 * @details     Čisto kombinačný prevod pointera v Gray kóde na binárny.
 * Algoritmus: b[N] = g[N], b[i] = b[i+1] ^ g[i].
 *
 * @param ADDR_WIDTH Počet adresových bitov (šírka zbernice = ADDR_WIDTH+1).
 *
 * @input  gray_i  Vstupný vektor v Gray kóde.
 * @output bin_o   Výstupný vektor v binárnom kóde.
 */

`default_nettype none

`ifndef GRAY_TO_BIN_SV
`define GRAY_TO_BIN_SV

module gray_to_bin #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic [ADDR_WIDTH:0] gray_i,
    output logic [ADDR_WIDTH:0] bin_o
);

    // Interný signál pre medzivýpočet
    logic [ADDR_WIDTH:0] bin_int;

    always_comb begin
        // MSB je totožné s Gray kódom
        bin_int[ADDR_WIDTH] = gray_i[ADDR_WIDTH];

        // Výpočet od (MSB-1) po LSB
        // Algoritmus: bin[i] = bin[i+1] XOR gray[i]
        for (int i = ADDR_WIDTH - 1; i >= 0; i--) begin
            bin_int[i] = bin_int[i+1] ^ gray_i[i];
        end
    end

    // Priradenie výstupu
    assign bin_o = bin_int;

endmodule

`endif // GRAY_TO_BIN_SV

`default_nettype wire
