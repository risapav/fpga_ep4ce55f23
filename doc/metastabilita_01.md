Samozrejme, tu je refaktorovaná a podrobne okomentovaná verzia modulu `TwoFlopSynchronizer`.

Najdôležitejšou zmenou je pridanie syntézneho atribútu `(* async_reg = "true" *)`. Tento malý, ale kritický doplnok zaručuje, že syntetizačný nástroj (Quartus) nikdy "neoptimalizuje" preč prvý register, čím by zničil celú funkciu synchronizátora. Taktiež som doplnil komentáre, ktoré vysvetľujú účel, použitie a obmedzenia modulu.

Tento kód je teraz pripravený na bezpečné použitie v akomkoľvek projekte ako robustné IP jadro.

-----

### Refaktorizovaný Kód `TwoFlopSynchronizer.sv` (Verzia 2.0)

```systemverilog
//=============================================================================
// TwoFlopSynchronizer.sv - Robustný dvojstupňový synchronizátor
//
// Verzia: 2.0
//
// === Popis a vylepšenia ===
// 1. ROBUSTNOSŤ VOČI SYNTÉZE: Pridaný bol kľúčový syntézny atribút
//    `(* async_reg = "true" *)` k prvému stupňu registra. Týmto sa
//    explicitne zabraňuje nástroju pre syntézu, aby tento register
//    omylom "zoptimalizoval" preč, čo by znefunkčnilo ochranu proti
//    metastabilite.
//
// 2. DETAILNÁ DOKUMENTÁCIA: Boli pridané komentáre vysvetľujúce problém
//    metastability, princíp fungovania synchronizátora a jeho správne
//    použitie (napr. obmedzenia pri viacbitových zberniciach).
//
// === Účel Modulu ===
// Tento modul bezpečne prenáša signály cez hranicu hodinových domén (CDC).
// Rieši problém metastability, ktorá môže nastať, keď cieľový klopný
// obvod vzorkuje vstupný signál, ktorý sa mení asynchrónne voči jeho
// hodinám. Používa na to štandardnú techniku dvoch za sebou idúcich
// registrov (klopných obvodov).
//=============================================================================

`ifndef TWO_FLOP_SYNCHRONIZER_SV
`define TWO_FLOP_SYNCHRONIZER_SV

`default_nettype none

module TwoFlopSynchronizer #(
    parameter int WIDTH = 1 // Šírka synchronizovaného signálu v bitoch
)(
    input  logic             clk,   // Hodinový signál CIEĽOVEJ domény
    input  logic             rst_n, // Asynchrónny reset pre cieľovú doménu, aktívny v nule
    input  logic [WIDTH-1:0] d,     // Vstupný asynchrónny signál (zo ZDROJOVEJ domény)
    output logic [WIDTH-1:0] q      // Výstupný signál, bezpečne synchronizovaný do CIEĽOVEJ domény
);

    // Prvý stupeň synchronizátora.
    // Tento register je priamo vystavený riziku metastability.
    // Atribút `async_reg` je kritický - hovorí syntetizátoru, aby tento
    // register nikdy neoptimalizoval (neodstránil ani nezlučoval), pretože
    // je súčasťou CDC (Clock Domain Crossing) reťazca.
    (* async_reg = "true" *) logic [WIDTH-1:0] sync1_reg;

    // Dvojstupňová registrácia na minimalizáciu metastability.
    // Všetka logika beží v cieľovej hodinovej doméne `clk`.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // V resete sú oba stupne vynulované pre definovaný počiatočný stav.
            sync1_reg <= 'd0;
            q         <= 'd0;
        end else begin
            // Asynchrónny vstup `d` sa najprv zachytí do prvého stupňa.
            sync1_reg <= d;
            // Výstup z prvého stupňa (ktorý mal čas sa ustáliť) sa bezpečne
            // zachytí do druhého, finálneho výstupného registra `q`.
            q         <= sync1_reg;
        end
    end

    // --- Dôležité Upozornenie k Použitiu ---
    // Tento synchronizátor je bezpečný pre jednobitové riadiace signály
    // alebo pre viacbitové zbernice, kde sa mení vždy len jeden bit naraz
    // (napr. Grayov kód), alebo kde je zaručené, že hodnota na vstupe `d`
    // je stabilná po niekoľko cyklov cieľových hodín `clk`.
    //
    // Pre prenos všeobecných viacbitových dát (napr. binárny čítač), kde sa
    // môže meniť viacero bitov súčasne, tento synchronizátor NIE JE bezpečný
    // kvôli riziku skreslenia (skew). V takom prípade je nutné použiť
    // metódy ako asynchrónne FIFO.

endmodule

`endif // TWO_FLOP_SYNCHRONIZER_SV
```

Týmto jednoduchým pridaním atribútu sa z funkčného modulu stáva skutočne robustné a priemyselne kvalitné IP jadro, na ktoré sa môžete spoľahnúť v akomkoľvek dizajne s viacerými hodinovými doménami.
