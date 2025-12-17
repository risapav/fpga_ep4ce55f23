/**
 * @file        fb_addr_translator.sv
 * @brief       Prekladá lineárnu 32-bitovú adresu na SDRAM geometriu (Bank, Row, Col).
 * @details     Mapovanie je sekvenčné (Row-Sequential):
 * Adresa rastie v poradí: Column -> Row -> Bank.
 * Toto minimalizuje prepínanie riadkov (Page Miss) pri lineárnom burst prístupe.
 *
 * @input  linear_addr_i Lineárna adresa (napr. z Framebuffera).
 * @output sdram_addr_o  Fyzická adresa SDRAM (štruktúra).
 */

`default_nettype none

`ifndef FB_ADDR_TRANSLATOR_SV
`define FB_ADDR_TRANSLATOR_SV

import sdram_pkg::*;

module fb_addr_translator (
    input  logic [31:0]        linear_addr_i,
    output sdram_pkg::sdram_addr_t sdram_addr_o
);

    // -------------------------------------------------------------------------
    // Mapovanie Adresy
    // -------------------------------------------------------------------------
    // Schéma mapovania: {MSB... Bank, Row, Column ...LSB}
    //
    // 1. Column (LSB): Mení sa najrýchlejšie. Umožňuje využiť bursty v rámci jedného riadku.
    // 2. Row (Middle): Mení sa po pretečení stĺpcov. Vyžaduje PRECHARGE/ACTIVATE.
    // 3. Bank (MSB):   Mení sa najpomalšie.
    
    // Pozor: Toto mapovanie predpokladá, že linear_addr_i je bajtová adresa, 
    // ale SDRAM adresuje po slovách (16-bit). 
    // Ak je linear_addr_i bajtová, bit 0 by sa mal ignorovať alebo použiť na maskovanie (DQM).
    // Tu predpokladáme, že linear_addr_i je už zarovnaná na slovo (Word Address), 
    // alebo že Column 0 zodpovedá adrese 0.
    
    assign sdram_addr_o.col  = linear_addr_i[COL_ADDR_WIDTH - 1 : 0];
    
    assign sdram_addr_o.row  = linear_addr_i[COL_ADDR_WIDTH + ROW_ADDR_WIDTH - 1 : COL_ADDR_WIDTH];
    
    assign sdram_addr_o.bank = linear_addr_i[COL_ADDR_WIDTH + ROW_ADDR_WIDTH + BANK_ADDR_WIDTH - 1 : COL_ADDR_WIDTH + ROW_ADDR_WIDTH];

endmodule

`endif // FB_ADDR_TRANSLATOR_SV

`default_nettype wire
