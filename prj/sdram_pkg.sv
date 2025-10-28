/**
 * @file        sdram_pkg.sv
 * @brief       Balíček pre SDRAM parametre a typy (Vylepšená verzia)
 * @details     Definuje zdieľané parametre (geometria, časovanie v ns)
 * a automaticky prepočítava časovanie na hodinové cykly
 * na základe definovanej CLOCK_FREQ_HZ.
 *
 * Táto verzia je optimalizovaná pre:
 * Pamäť: W9825G6KH-6 (256Mbit, 8K row, 4 bank, x16)
 * Frekvencia: 100 MHz
 *
 * Zmeny v tejto verzii:
 * - OPRAVA (Syntax v4.8): Zjednodušený výpočet 'CMrsValueAddr'
 * pridaním 'C_MRS_RESERVED_WIDTH' pre opravu Quartus Error 10170.
 * - OPRAVA (Syntax v4.9): Odstránené prebytočné zátvorky '()'
 * okolo replikácie v 'CMrsValueAddr' (oprava Error 10170).
 * - OPRAVA (Syntax v4.10): Zmenená syntax replikácie na '{N{value}}'
 * pre opravu chyby Quartus Error 10170 (near text ",").
 */

`ifndef SDRAM_PKG_V2_SV
`define SDRAM_PKG_V2_SV

`default_nettype none

package sdram_pkg;

    // =========================================================================
    // 1. ZÁKLADNÁ KONFIGURÁCIA (Tu upravujete podľa projektu)
    // =========================================================================

    // --- Frekvencia hodín kontroléra ---
    parameter int CLOCK_FREQ_HZ   = 100_000_000; // 100 MHz

    // --- Geometria pamäte (W9825G6KH-6) ---
    parameter int DATA_WIDTH      = 16;  // Šírka dátovej zbernice DQ
    parameter int ROW_ADDR_WIDTH  = 13;  // Počet riadkových adries (8K = 2^13)
    parameter int COL_ADDR_WIDTH  = 9;   // Počet stĺpcových adries (512 = 2^9)
    parameter int BANK_ADDR_WIDTH = 2;   // Počet adries bánk (4 = 2^2)

    // --- Základné nastavenia režimu ---
    parameter int BURST_LEN       = 8;   // Dĺžka burst prenosu
    parameter int CAS_LATENCY     = 3;   // CAS latencia

    // --- Časovanie v Nanosekundách (podľa W9825G6KH-6 @ 100-166MHz) ---
    parameter int T_RP_NS  = 18; // Precharge command period (tRP)
    parameter int T_RCD_NS = 18; // Active to R/W command (tRCD)
    parameter int T_WR_NS  = 12; // Write recovery time (tWR)
    parameter int T_RFC_NS = 60; // Refresh cycle time (tRFC)
    parameter int T_RAS_NS = 42; // Active to Precharge command (tRAS)
    parameter int T_MRD_NS = 14; // Mode Register Set (tMRD), min 2 cykly

    // Štandardný JEDEC interval medzi refreshmi pre 64ms/8K riadkov
    parameter int T_REFI_NS = 7812; // 7.812 us


    // =========================================================================
    // 2. ODVODENÉ KONŠTANTY (Nemeňte, počítajú sa automaticky)
    // =========================================================================

    // --- Pomocná funkcia na výpočet cyklov (zaokrúhlenie nahor) ---
    function automatic int ceil_div(input int A, input int B);
        return (A + B - 1) / B;
    endfunction

    // --- Perióda hodín ---
    localparam int NS_PER_SEC    = 1_000_000_000;
    localparam int CLK_PERIOD_NS = ceil_div(NS_PER_SEC, CLOCK_FREQ_HZ); // v ns (10ns @ 100MHz)

    // --- Prepočítané časovanie v CYKLOCH ---
    localparam int T_RP_CYCLES  = ceil_div(T_RP_NS, CLK_PERIOD_NS); // 18ns/10ns = 2 cykly
    localparam int T_RCD_CYCLES = ceil_div(T_RCD_NS, CLK_PERIOD_NS); // 18ns/10ns = 2 cykly
    localparam int T_WR_CYCLES  = (ceil_div(T_WR_NS, CLK_PERIOD_NS) > 2) ? ceil_div(T_WR_NS, CLK_PERIOD_NS) : 2; // 12ns/10ns = 2 cykly
    localparam int T_RFC_CYCLES = ceil_div(T_RFC_NS, CLK_PERIOD_NS); // 60ns/10ns = 6 cyklov
    localparam int T_RAS_CYCLES = ceil_div(T_RAS_NS, CLK_PERIOD_NS); // 42ns/10ns = 5 cyklov
    localparam int T_MRD_CYCLES = (ceil_div(T_MRD_NS, CLK_PERIOD_NS) > 2) ? ceil_div(T_MRD_NS, CLK_PERIOD_NS) : 2; // 14ns/10ns = 2 cykly

    localparam int CInitWaitCycles = ceil_div(200_000, CLK_PERIOD_NS); // Prepočet 200us na cykly
    localparam int REFRESH_INTERVAL_CYCLES = T_REFI_NS / CLK_PERIOD_NS; // 7812ns / 10ns = 781 cyklov


    // --- Konštanty pre Mode Register ---
    localparam logic [2:0] CMrsCasValue = (CAS_LATENCY == 3) ? 3'b011 :
                                          (CAS_LATENCY == 2) ? 3'b010 :
                                                               3'b011;
    localparam logic [2:0] CMrsBurstLenValue = (BURST_LEN == 8) ? 3'b011 :
                                              (BURST_LEN == 4) ? 3'b010 :
                                              (BURST_LEN == 2) ? 3'b001 :
                                                                 3'b000;

    localparam int C_MRS_RESERVED_WIDTH = ROW_ADDR_WIDTH - 10;

    // Adresa pre MRS: A12-A10=0, A9=0 (Standard), A8-A7=00 (Write Burst), A6-A4=CAS, A3=0 (Sequential), A2-A0=BurstLen
    localparam logic [ROW_ADDR_WIDTH-1:0] CMrsValueAddr = {
        // OPRAVA (Syntax v4.10): Použitá syntax {N{value}} pre replikáciu vnútri konkatenácie
        { C_MRS_RESERVED_WIDTH { 1'b0 } }, // Rezervované bity (A12-A10)
        1'b0,                              // A9: Write Burst Mode (0=Programmed Burst Length)
        2'b00,                             // A8-A7: Operating Mode (Standard)
        CMrsCasValue,                      // A6-A4: CAS Latency
        1'b0,                              // A3: Burst Type (0=Sequential)
        CMrsBurstLenValue                  // A2-A0: Burst Length
    };


    // =========================================================================
    // 3. ZDIEĽANÉ DÁTOVÉ TYPY
    // =========================================================================

    parameter int ADDR_WIDTH      = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;

    typedef struct packed {
        logic [BANK_ADDR_WIDTH-1:0] bank;
        logic [ROW_ADDR_WIDTH-1:0]  row;
        logic [COL_ADDR_WIDTH-1:0]  col;
    } sdram_addr_t;

    typedef struct packed {
        sdram_addr_t addr;
        logic        rw;
        logic        auto_precharge;
    } sdram_cmd_t;

endpackage : sdram_pkg

`default_nettype wire

`endif // SDRAM_PKG_V2_SV

