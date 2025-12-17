/**
 * @file        pointer_sync.sv
 * @brief       Modul pre synchronizáciu pointerov a inkrementáciu lokálneho pointera.
 * @details     Kombinuje dve funkcie pre FIFO implementácie:
 * 1. Binárne počítadlo pre lokálny pointer (Write alebo Read).
 * 2. CDC synchronizátor pre Gray pointer prichádzajúci z druhej domény.
 *
 * Obsahuje atribúty pre správnu syntézu synchronizátora (ASYNC_REG).
 *
 * @param ADDR_WIDTH     Šírka adresy (pointer je ADDR_WIDTH+1).
 * @param TWO_STAGE_SYNC 1 = 2-stupňová synchronizácia (odporúčané), 0 = 1-stupňová.
 *
 * @input  clk_i         Hodinový signál lokálnej domény.
 * @input  rst_ni        Asynchrónny reset (active-low).
 * @input  en_i          Povolenie inkrementácie lokálneho pointera.
 * @output bin_ptr_o     Lokálny binárny pointer.
 * @input  ptr_gray_i    Gray pointer z druhej domény (vstup).
 * @output ptr_gray_sync_o Synchronizovaný Gray pointer.
 */

`default_nettype none

`ifndef POINTER_SYNC_SV
`define POINTER_SYNC_SV

module pointer_sync #(
    parameter int ADDR_WIDTH     = 4,
    parameter bit TWO_STAGE_SYNC = 1'b1
)(
    input  wire logic                  clk_i,
    input  wire logic                  rst_ni,
    input  wire logic                  en_i,
    output      logic [ADDR_WIDTH:0]   bin_ptr_o,
    
    // CDC signály
    input  wire logic [ADDR_WIDTH:0]   ptr_gray_i,
    output      logic [ADDR_WIDTH:0]   ptr_gray_sync_o
);

    // -------------------------------------------------------------------------
    // 1. Lokálny Binárny Pointer (Počítadlo)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            bin_ptr_o <= '0;
        end else if (en_i) begin
            bin_ptr_o <= bin_ptr_o + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Synchronizátor Gray Pointera (CDC)
    // -------------------------------------------------------------------------
    
    // Atribúty pre syntézu na minimalizáciu metastability a oneskorenia
    (* ASYNC_REG = "TRUE" *) 
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [ADDR_WIDTH:0] sync_regs [0:1]; // Pole pre 2 stupne

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_regs[0] <= '0;
            sync_regs[1] <= '0;
        end else begin
            // 1. Stupeň: Zachytenie asynchrónneho vstupu
            sync_regs[0] <= ptr_gray_i;
            
            // 2. Stupeň: Stabilizácia
            sync_regs[1] <= sync_regs[0];
        end
    end

    // Výber výstupu podľa parametra (Combinatorial assignment)
    // Ak TWO_STAGE_SYNC=1, berieme výstup z sync_regs[1] (2. FF).
    // Ak TWO_STAGE_SYNC=0, berieme výstup z sync_regs[0] (1. FF - menej bezpečné).
    assign ptr_gray_sync_o = TWO_STAGE_SYNC ? sync_regs[1] : sync_regs[0];

endmodule

`endif // POINTER_SYNC_SV

`default_nettype wire
