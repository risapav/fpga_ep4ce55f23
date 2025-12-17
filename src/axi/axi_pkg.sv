/**
 * @file        axi_pkg.sv
 * @brief       Centrálna konfigurácia AXI-Stream zbernice.
 * @details     Tento balíček definuje základné parametre a dátové typy
 * pre AXI4-Stream komunikáciu používanú v celom projekte.
 * Umožňuje jednotnú konfiguráciu šírky dát a používateľských signálov.
 *
 * @param       AXI_TDATA_WIDTH   Šírka TDATA zbernice v bitoch (default: 16).
 * @param       AXI_TUSER_WIDTH   Šírka TUSER signálu v bitoch (default: 1).
 *
 * @typedef     axi4s_payload_t   Dátová štruktúra pre AXI4-Stream prenos.
 *
 * @example
 * // Príklad použitia v module:
 * import axi_pkg::*;
 * axi4s_payload_t payload;
 * assign payload.TDATA = 16'hABCD;
 * assign payload.TUSER = 1'b0;
 * assign payload.TLAST = 1'b1;
 */

`ifndef AXI_PKG_SV
`define AXI_PKG_SV

package axi_pkg;

    // ================================================================
    //  CENTRÁLNA KONFIGURÁCIA AXI ZBERNICE
    // ================================================================
    // Úpravou týchto parametrov sa zmení šírka AXI-Stream zbernice
    // v celom projekte, ktorý tento balíček importuje.
    
    parameter int AXI_TDATA_WIDTH = 16; // Šírka TDATA v bitoch (napr. RGB565)
    parameter int AXI_TUSER_WIDTH = 1;  // Šírka TUSER v bitoch (napr. SOF)


    // ================================================================
    //  AXI4-Stream Dátové Typy (Payloads)
    // ================================================================
    // Táto štruktúra definuje dátový obsah (payload) pre AXI-Stream.
    // Jej šírka sa automaticky prispôsobuje podľa parametrov vyššie.
    // Použitie `packed` je kľúčové, aby sa so štruktúrou dalo
    // pracovať ako s jedným súvislým bitovým vektorom.
    
    typedef struct packed {
        logic                         TLAST;  // 1-bitový signál konca paketu (EOL/EOF)
        logic [AXI_TUSER_WIDTH-1:0]   TUSER;  // Používateľský signál (SOF)
        logic [AXI_TDATA_WIDTH-1:0]   TDATA;  // Dátová zbernica (Video Data)
    } axi4s_payload_t;

    // Pomocný parameter pre výpočet šírky FIFO bufferov
    parameter int PAYLOAD_WIDTH = AXI_TDATA_WIDTH + AXI_TUSER_WIDTH + 1;

endpackage : axi_pkg

`endif // AXI_PKG_SV

