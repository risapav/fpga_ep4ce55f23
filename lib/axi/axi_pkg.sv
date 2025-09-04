//=============================================================================
// axi_pkg.sv - Parametrizovaný balíček pre AXI
//
// Verzia: 5.1
//
// === Popis a vylepšenia ===
// 1. PARAMETRIZÁCIA ŠÍRKY ZBERNICE:
//    - Boli pridané parametre `AXI_DATA_WIDTH` a `AXI_USER_WIDTH`, ktoré
//      umožňujú jednoduchú a centrálnu konfiguráciu šírky AXI4-Stream
//      zbernice pre celý projekt.
//
// 2. FLEXIBILNÝ DÁTOVÝ TYP:
//    - Štruktúra `axi4s_payload_t` teraz používa tieto parametre,
//      čím sa stáva znovupoužiteľnou pre rôzne konfigurácie.
//
// 3. ZACHOVANIE KOMPATIBILITY:
//    - Balíček naďalej obsahuje len `typedef` a `parameter` definície
//      pre maximálnu kompatibilitu so syntetizačnými nástrojmi.
//=============================================================================

`ifndef AXI_PKG_DONE
`define AXI_PKG_DONE

package axi_pkg;

    //================================================================
    //  CENTRÁLNA KONFIGURÁCIA AXI ZBERNICE
    //================================================================
    // Úpravou týchto parametrov sa zmení šírka AXI-Stream zbernice
    // v celom projekte, ktorý tento balíček importuje.
    parameter int AXI_DATA_WIDTH = 16; // Šírka TDATA v bitoch
    parameter int AXI_USER_WIDTH = 1;  // Šírka TUSER v bitoch


    //================================================================
    // AXI4-Stream Dátové Typy (Payloads)
    //================================================================
    // Táto štruktúra definuje dátový obsah (payload) pre AXI-Stream.
    // Jej šírka sa automaticky prispôsobuje podľa parametrov vyššie.
    // Použitie `packed` je kľúčové, aby sa so štruktúrou dalo
    // pracovať ako s jedným súvislým bitovým vektorom.
    typedef struct packed {
        logic                      TLAST;                  // 1-bitový signál konca paketu
        logic [AXI_USER_WIDTH-1:0] TUSER;                  // Používateľský signál s parametrizovateľnou šírkou
        logic [AXI_DATA_WIDTH-1:0] TDATA;                  // Dátová zbernica s parametrizovateľnou šírkou
    } axi4s_payload_t;

endpackage : axi_pkg

`endif // AXI_PKG_DONE
