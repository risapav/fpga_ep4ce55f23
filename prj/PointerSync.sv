/**
 * @file        PointerSync.sv
 * @brief       Modul pre synchronizáciu pointerov medzi hodinovými doménami.
 * @details     Tento modul vykonáva dve hlavné funkcie:
 * 1. Inkrementuje binárny pointer (`bin_ptr_out`) v lokálnej
 * hodinovej doméne (`clk`), keď je povolený (`en`).
 * 2. Synchronizuje Gray kód pointera (`other_gray_in`) z druhej
 * hodinovej domény do lokálnej domény (`clk`) pomocou
 * dvojstupňového synchronizátora (`other_gray_sync_out`).
 * Použitie Gray kódu znižuje riziko metastability pri prenose
 * viacbitovej hodnoty medzi asynchrónnymi doménami.
 *
 * Zmeny:
 * - OPRAVA: Pridaný chýbajúci výstupný port 'other_gray_sync1_out'.
 * - Vrátená dvojstupňová synchronizácia (TWO_STAGE_SYNC=1).
 * - Odstránené použitie '$bits' pri inkrementácii pre lepšiu kompatibilitu.
 * - Pridaný `ifndef` guard.
 * - Detailnejšie komentáre.
 * - Opravená syntax '{0} na '0.
 *
 * @param ADDR_WIDTH     Šírka adresy (a teda pointera bez MSB pre pretečenie). Pointer má šírku ADDR_WIDTH+1.
 * @param TWO_STAGE_SYNC Počet stupňov synchronizátora (1 = dva stupne, 0 = jeden stupeň - menej bezpečné).
 */

`ifndef POINTER_SYNC_SV
`define POINTER_SYNC_SV

`default_nettype none

module PointerSync #(
    parameter int ADDR_WIDTH     = 4,
    parameter bit TWO_STAGE_SYNC = 1'b1  // Predvolene dvojstupňový synchronizátor
)(
    input  logic clk,                   // Hodinový signál lokálnej domény
    input  logic rst_ni,                // Reset, aktívny v nízkej úrovni
    input  logic en,                    // Povolenie inkrementácie lokálneho pointera
    output logic [ADDR_WIDTH:0] bin_ptr_out,       // Lokálny binárny pointer (výstup)
    input  logic [ADDR_WIDTH:0] other_gray_in,     // Gray pointer z druhej domény (vstup)
    output logic [ADDR_WIDTH:0] other_gray_sync_out, // Synchronizovaný Gray pointer (výstup)
    // OPRAVA: Pridaný chýbajúci výstupný port
    output logic [ADDR_WIDTH:0] other_gray_sync1_out
);

    // Interný register pre prvý stupeň synchronizácie
    // (teraz je aj výstupom)
    logic [ADDR_WIDTH:0] other_gray_sync1;
    assign other_gray_sync1_out = other_gray_sync1; // Priradenie na nový výstup


    // -----------------------------------------------------
    // Hlavný sekvenčný blok pre inkrementáciu a synchronizáciu
    // -----------------------------------------------------
    // Synchrónny reset
    always_ff @(posedge clk) begin
        if (!rst_ni) begin
            // Reset všetkých registrov na 0
            bin_ptr_out         <= '0;
            other_gray_sync1    <= '0;
            other_gray_sync_out <= '0;
        end else begin
            // --- Inkrementácia lokálneho binárneho pointera ---
            if (en) begin
                bin_ptr_out <= bin_ptr_out + 1'b1; // Odstránené $bits
            end

            // --- Synchronizácia Gray pointera z druhej domény ---
            // 1. stupeň
            other_gray_sync1 <= other_gray_in;
            // 2. stupeň (ak povolený)
            if (TWO_STAGE_SYNC) begin
                other_gray_sync_out <= other_gray_sync1; // Dvojstupňová
            end else begin
                // Pri TWO_STAGE_SYNC=0, other_gray_sync1 slúži ako jediný stupeň
                other_gray_sync_out <= other_gray_sync1; // Efektívne jednostupňová
            end
        end
    end

endmodule

`default_nettype wire // Obnovenie predvoleného typu siete

`endif // POINTER_SYNC_SV

