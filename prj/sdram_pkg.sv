/**
 * @file        sdram_pkg.sv
 * @brief       Balíček pre SDRAM parametre a typy.
 * @details     Definuje zdieľané parametre (šírka dát, adresy),
 * dátové typy (rozdelená adresa, príkaz) pre SDRAM kontrolér.
 */

`ifndef SDRAM_PKG_SV
`define SDRAM_PKG_SV

`default_nettype none

package sdram_pkg;
    // Základné parametre SDRAM
    parameter int DATA_WIDTH      = 16;  // Šírka dátovej zbernice DQ
    parameter int ROW_ADDR_WIDTH  = 13;  // Šírka riadkovej adresy
    parameter int COL_ADDR_WIDTH  = 9;   // Šírka stĺpcovej adresy
    parameter int BANK_ADDR_WIDTH = 2;   // Šírka adresy banky
    parameter int ADDR_WIDTH      = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH; // Celková šírka adresy (používaná interne)
    parameter int BURST_LEN       = 8;   // Dĺžka burst prenosu
    parameter int CAS_LATENCY     = 3;   // CAS latencia

    /**
     * @brief Štruktúra pre rozdelenú SDRAM adresu.
     * Umožňuje jednoduchý prístup k jednotlivým častiam adresy.
     */
    typedef struct packed {
        logic [BANK_ADDR_WIDTH-1:0] bank; // Bank Address (BA)
        logic [ROW_ADDR_WIDTH-1:0]  row;  // Row Address
        logic [COL_ADDR_WIDTH-1:0]  col;  // Column Address
    } sdram_addr_t;

    /**
     * @brief Štruktúra pre príkaz posielaný SDRAM kontroléru.
     * Spája adresu, typ operácie (R/W) a príznak auto-precharge.
     */
    typedef struct packed {
        sdram_addr_t addr;           // Cieľová adresa (rozdelená)
        logic        rw;             // Smer prenosu: 1 = Zápis (Write), 0 = Čítanie (Read)
        logic        auto_precharge; // Príznak automatického precharge po operácii
    } sdram_cmd_t;

endpackage : sdram_pkg

`default_nettype wire

`endif // SDRAM_PKG_SV
