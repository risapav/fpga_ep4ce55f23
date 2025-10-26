/**
 * @file        AsyncFifoGeneric.sv
 * @brief       Generické asynchrónne FIFO (CDC).
 * @details     Modul implementuje plne asynchrónne FIFO s oddelenými hodinovými
 * doménami pre zápis (wr_clk) a čítanie (rd_clk).
 * Používa synchronizáciu Gray kódovaných pointerov pre bezpečný
 * prechod medzi hodinovými doménami (CDC).
 *
 * Obsahuje registrovaný výstup (rd_data a rd_empty), čo pridáva
 * jeden takt latencie na čítacej strane, ale výrazne zlepšuje
 * časovanie (timing closure).
 *
 * Zmeny:
 * - OPRAVA DEADLOCKU: Enable pre inkrementáciu RD pointera teraz závisí
 * od kombinačného 'rd_empty_comb', nie registrovaného 'rd_empty_reg'.
 * - Upravená logika 'rd_underflow' na použitie 'rd_empty_comb'.
 * - Pridané výstupy pre celé lokálne a synchronizované Gray pointery.
 *
 * Závislosti:
 * - Modul 'PointerSync' (musí byť v projekte)
 * - Modul 'GrayToBin' (musí byť v projekte)
 *
 * @param DATA_WIDTH     Šírka dátového vstupu/výstupu.
 * @param ADDR_WIDTH     Šírka adresy (Hĺbka FIFO = 2^ADDR_WIDTH). Pointer má šírku ADDR_WIDTH+1.
 * @param RAM_STYLE      Typ RAM (napr. "M20K", "M9K", "auto", "distributed").
 * @param TWO_STAGE_SYNC 1 = použiť 2-stupňovú synchronizáciu (odporúčané).
 */

`ifndef ASYNC_FIFO_GENERIC_SV
`define ASYNC_FIFO_GENERIC_SV

`default_nettype none

module AsyncFifoGeneric #(
    parameter int DATA_WIDTH       = 16,
    parameter int ADDR_WIDTH       = 4, // Pointer width = ADDR_WIDTH + 1
    parameter string RAM_STYLE     = "auto",
    parameter bit TWO_STAGE_SYNC   = 1'b1
)(
    // Zapisovacia (Write) doména
    input  logic wr_rst_ni,
    input  logic wr_clk,
    input  logic wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic wr_full,
    output logic wr_overflow,

    // Čítacia (Read) doména
    input  logic rd_rst_ni,
    input  logic rd_clk,
    input  logic rd_en, // Pôvodný enable signál z wrapperu
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic rd_empty,
    output logic rd_underflow,

    // Stav (v 'wr_clk' doméne)
    output logic [$clog2(1<<ADDR_WIDTH):0] level,

    // Diagnostické výstupy
    output logic [ADDR_WIDTH:0] wr_ptr_gray_o,       // Lokálny WR pointer
    output logic [ADDR_WIDTH:0] rd_ptr_gray_o,       // Lokálny RD pointer
    output logic [ADDR_WIDTH:0] sync_wr_ptr_gray_o,  // Sync WR pointer (v RD doméne)
    output logic [ADDR_WIDTH:0] sync_rd_ptr_gray_o   // Sync RD pointer (v WR doméne)
);

    localparam int DEPTH = 1 << ADDR_WIDTH;
    localparam int PTR_WIDTH = ADDR_WIDTH + 1;

    (* ramstyle = RAM_STYLE *) logic [DATA_WIDTH-1:0] mem [DEPTH];

    logic [PTR_WIDTH-1:0] wr_ptr_bin, rd_ptr_bin;
    logic [PTR_WIDTH-1:0] wr_ptr_gray, rd_ptr_gray;

    logic [PTR_WIDTH-1:0] rd_ptr_gray_to_wr_clk;
    logic [PTR_WIDTH-1:0] rd_ptr_gray_sync1;
    logic [PTR_WIDTH-1:0] rd_ptr_gray_sync2;

    logic [PTR_WIDTH-1:0] wr_ptr_gray_to_rd_clk;
    logic [PTR_WIDTH-1:0] wr_ptr_gray_sync1;
    logic [PTR_WIDTH-1:0] wr_ptr_gray_sync2;

    logic [PTR_WIDTH-1:0] rd_ptr_bin_from_gray_sync;

    logic [DATA_WIDTH-1:0] mem_data_out;
    logic [DATA_WIDTH-1:0] rd_data_reg;
    logic                  rd_empty_comb;
    logic                  rd_empty_reg;

    // --- Zapisovacia (Write) doména ---
    assign rd_ptr_gray_to_wr_clk = rd_ptr_gray;

    PointerSync #(
        .ADDR_WIDTH     ( ADDR_WIDTH     ),
        .TWO_STAGE_SYNC ( TWO_STAGE_SYNC )
    ) wr_sync_inst (
        .clk                 ( wr_clk              ),
        .rst_ni              ( wr_rst_ni           ),
        .en                  ( wr_en && !wr_full   ),
        .bin_ptr_out         ( wr_ptr_bin          ),
        .other_gray_in       ( rd_ptr_gray_to_wr_clk ),
        .other_gray_sync1_out( rd_ptr_gray_sync1   ),
        .other_gray_sync_out ( rd_ptr_gray_sync2   )
    );

    always_ff @(posedge wr_clk) begin
        if (!wr_rst_ni) wr_overflow <= 1'b0;
        else if (wr_en) wr_overflow <= wr_full; // Overflow if write enable and full
        else            wr_overflow <= 1'b0;
    end

    // Pamäťový zápis (pre jednoduchosť, bez explicitnej detekcie overflow tu)
    always_ff @(posedge wr_clk) begin
        if (wr_en && !wr_full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;

    assign wr_full = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH],
                                     ~rd_ptr_gray_sync2[ADDR_WIDTH-1],
                                      rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});

    // --- Čítacia (Read) doména ---
    assign wr_ptr_gray_to_rd_clk = wr_ptr_gray;

    // Kombinačný výpočet 'empty'
    assign rd_empty_comb = (rd_ptr_gray == wr_ptr_gray_sync2);

    PointerSync #(
        .ADDR_WIDTH     ( ADDR_WIDTH     ),
        .TWO_STAGE_SYNC ( TWO_STAGE_SYNC )
    ) rd_sync_inst (
        .clk                 ( rd_clk              ),
        .rst_ni              ( rd_rst_ni           ),
        // OPRAVA DEADLOCKU: Použijeme rd_en (z wrapperu) a KOMBINAČNÝ empty
        .en                  ( rd_en && !rd_empty_comb ),
        .bin_ptr_out         ( rd_ptr_bin          ),
        .other_gray_in       ( wr_ptr_gray_to_rd_clk ),
        .other_gray_sync1_out( wr_ptr_gray_sync1   ),
        .other_gray_sync_out ( wr_ptr_gray_sync2   )
    );

    assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;

    assign mem_data_out = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];

    assign rd_data  = rd_data_reg;
    assign rd_empty = rd_empty_reg; // Výstup je stále registrovaný

    always_ff @(posedge rd_clk) begin
        if (!rd_rst_ni) begin
            rd_underflow <= 1'b0;
            rd_data_reg  <= '0;
            rd_empty_reg <= 1'b1;
        end else begin
            // Register empty stále sleduje kombinačnú logiku
            rd_empty_reg <= rd_empty_comb;

            // Dáta registrujeme, ak bol povolený read a FIFO NEBOLO prázdne (registrovaný stav z predch. cyklu)
            if (rd_en && !rd_empty_reg) begin
                 rd_data_reg <= mem_data_out;
            end

            // Underflow nastane, ak bol povolený read A FIFO JE prázdne (kombinačný stav)
            if (rd_en)
                rd_underflow <= rd_empty_comb; // Použijeme rd_empty_comb
            else
                rd_underflow <= 1'b0;
        end
    end

    // --- Výpočet zaplnenia (Level) ---
    GrayToBin #(.ADDR_WIDTH(ADDR_WIDTH)) gray2bin_inst (
        .gray ( rd_ptr_gray_sync2         ),
        .bin  ( rd_ptr_bin_from_gray_sync )
    );
    assign level = wr_ptr_bin - rd_ptr_bin_from_gray_sync;

    // --- Diagnostické výstupy ---
    assign wr_ptr_gray_o      = wr_ptr_gray;
    assign rd_ptr_gray_o      = rd_ptr_gray;
    assign sync_wr_ptr_gray_o = wr_ptr_gray_sync2;
    assign sync_rd_ptr_gray_o = rd_ptr_gray_sync2;

endmodule

`default_nettype wire

`endif // ASYNC_FIFO_GENERIC_SV

