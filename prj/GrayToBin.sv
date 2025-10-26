/**
 * @file        GrayToBin.sv
 * @brief       Kombinačný prevodník z Gray kódu na binárny.
 * @details     Tento modul implementuje čisto kombinačnú logiku
 * na prevod pointera v Gray kóde späť na binárny.
 * Používa sa v asynchrónnom FIFO na výpočet zaplnenia (level),
 * kde je potrebné synchronizovaný Gray pointer z druhej domény
 * previesť späť na binárny pre aritmetické porovnanie.
 *
 * Prevod funguje na princípe XOR:
 * bin[MSB] = gray[MSB]
 * bin[i]   = bin[i+1] ^ gray[i]
 *
 * Zmena (Refaktoring):
 * - Nahradený 'generate for' za 'always_comb for' kvôli
 * robustnosti a prevencii interných chýb kompilátora Quartus.
 *
 * @param ADDR_WIDTH     Šírka adresy (prevádza sa ADDR_WIDTH + 1 bitov).
 *
 * @input  gray     Vstupný (ADDR_WIDTH+1)-bitový pointer v Gray kóde.
 * @output bin      Výstupný (ADDR_WIDTH+1)-bitový pointer v binárnom kóde.
 */

`ifndef GRAY_TO_BIN_SV
`define GRAY_TO_BIN_SV

`default_nettype none

module GrayToBin #(
    parameter int ADDR_WIDTH = 4
)(
    input  logic [ADDR_WIDTH:0] gray,
    output logic [ADDR_WIDTH:0] bin
);

    // Kombinačná logika pre prevod Gray -> Binárny
    // Nahradený 'generate for' za 'always_comb for' kvôli
    // robustnosti a prevencii interných chýb kompilátora.
    always_comb begin
        // MSB bit (najvyšší) je rovnaký
        bin[ADDR_WIDTH] = gray[ADDR_WIDTH];

        // Slučka prechádza od (MSB-1) dolu k 0
        // Použitie 'int j' je platné v SystemVerilog 'always_comb'
        for (int j = ADDR_WIDTH-1; j >= 0; j--) begin
            // Každý ďalší bit je XOR predchádzajúceho binárneho bitu
            // a aktuálneho Gray bitu.
            bin[j] = bin[j+1] ^ gray[j];
        end
    end

endmodule

`default_nettype wire

`endif // GRAY_TO_BIN_SV

