//=============================================================================
// TwoFlopSynchronizer.sv - Robustný dvojstupňový synchronizátor pre Quartus
//
// Verzia: 2.2 (refaktor + doplnené poznámky)
//
// === Popis ===
// Tento modul implementuje dvojstupňový synchronizátor pre bezpečný prenos
// asynchrónneho signálu do cieľovej hodinovej domény. Je to štandardný
// spôsob eliminácie metastability.
//
// === Kľúčové vlastnosti ===
// - Dvojstupňová registrácia (FF1 → FF2) minimalizuje pravdepodobnosť metastability.
// - Použitie atribútu `altera_attribute` zabezpečuje, že Quartus správne
//   identifikuje tento reťazec ako CDC synchronizátor a aplikuje patričné ochrany.
//=============================================================================

`ifndef TWO_FLOP_SYNCHRONIZER_SV
`define TWO_FLOP_SYNCHRONIZER_SV

`default_nettype none  // Zakazuje implicitné deklarácie - zvyšuje robustnosť

module TwoFlopSynchronizer #(
    parameter int WIDTH = 1 // Počet bitov synchronizovaného signálu
)(
    input  logic             clk_i,     // Hodinový signál cieľovej domény
    input  logic             rst_ni,    // Asynchrónny reset aktívny v L (negatívna logika)
    input  logic [WIDTH-1:0] d_i,       // Vstupný signál z inej (asynchrónnej) domény
    output logic [WIDTH-1:0] q_o        // Výstupný, synchronizovaný signál
);

    // === Prvý stupeň synchronizácie ===
    // Tento FF zachytáva asynchrónny vstup. Označený pre Quartus ako CDC synchronizátor.
    // Atribút `SYNCHRONIZER_IDENTIFICATION` zabezpečí automatické rozpoznanie nástrojom.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [WIDTH-1:0] sync1_reg;

    // === Sekvenčná logika ===
    // Vykonáva dvojstupňovú synchronizáciu v cieľovej hodinovej doméne.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Inicializácia počas resetu - zabraňuje neznámym stavom
            sync1_reg <= 'd0;
            q_o       <= 'd0;
        end else begin
            // Prvý FF zachytí asynchrónny signál
            sync1_reg <= d_i;
            // Druhý FF produkuje synchronizovaný výstup
            q_o       <= sync1_reg;
        end
    end

endmodule

`endif // TWO_FLOP_SYNCHRONIZER_SV
