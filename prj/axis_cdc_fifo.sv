// ============================================================================
// Súbor: axis_cdc_fifo.sv
// Verzia: 1.8 (Pridaná diagnostika celých pointerov)
// Dátum: 26. október 2025
//
// Popis:
// AXI4-Stream Clock Domain Crossing (CDC) FIFO wrapper.
//
// Zmeny vo verzii 1.8:
// - Pridané výstupy pre celé lokálne a synchronizované Gray pointery.
// - Odstránené LSB-only diagnostické výstupy.
// ============================================================================


`ifndef AXIS_CDC_FIFO_SV
`define AXIS_CDC_FIFO_SV

`default_nettype none

import axi_pkg::*;       // Import balíčka s AXI definíciami

// ============================================================================
// Modul: axis_cdc_fifo
// ============================================================================
/**
 * @brief       AXI4-Stream Clock Domain Crossing (CDC) FIFO
 * @details     Wrapper modul, ktorý implementuje asynchrónne FIFO
 * medzi dvoma AXI4-Stream rozhraniami s oddelenými
 * hodinovými doménami a resetmi.
 *
 * @param DATA_WIDTH     Šírka AXI TDATA zbernice (z axi_pkg).
 * @param USER_WIDTH     Šírka AXI TUSER signálu (z axi_pkg).
 * @param KEEP_WIDTH     Šírka AXI TKEEP signálu (defaultne odvodené).
 * @param ID_WIDTH       Šírka AXI TID signálu (defaultne 0).
 * @param DEST_WIDTH     Šírka AXI TDEST signálu (defaultne 0).
 * @param FIFO_DEPTH_BITS Hĺbka FIFO vyjadrená ako počet adresných bitov (Pointer má šírku +1).
 * @param RAM_STYLE      Typ bloku RAM.
 * @param TWO_STAGE_SYNC Použitie 2-stupňového synchronizátora.
 */
module axis_cdc_fifo #(
    // Parametre AXI Streamu
    parameter int DATA_WIDTH     = axi_pkg::AXI_TDATA_WIDTH,
    parameter int USER_WIDTH     = axi_pkg::AXI_TUSER_WIDTH,
    parameter int KEEP_WIDTH     = DATA_WIDTH / 8,
    parameter int ID_WIDTH       = 0,
    parameter int DEST_WIDTH     = 0,
    // Parametre FIFO
    parameter int FIFO_DEPTH_BITS  = 8, // Pointer width = FIFO_DEPTH_BITS + 1
    parameter string RAM_STYLE     = "auto",
    parameter bit TWO_STAGE_SYNC   = 1'b1
)(
    // Slave (Write) Interface
    input  logic s_clk_i,
    input  logic s_rst_ni,
    axi4s_if.slave s_axis,

    // Master (Read) Interface
    input  logic m_clk_i,
    input  logic m_rst_ni,
    axi4s_if.master m_axis,

    // Status
    output logic [$clog2(1<<FIFO_DEPTH_BITS):0] level_o,
    output logic wr_overflow_o,
    output logic rd_underflow_o,
    output logic internal_rd_empty_o, // Priamo stav empty z AsyncFifoGeneric
    output logic internal_wr_full_o,  // Priamo stav full z AsyncFifoGeneric

    // Nové diagnostické výstupy pre celé pointery
    output logic [FIFO_DEPTH_BITS:0] local_wr_ptr_gray_o,
    output logic [FIFO_DEPTH_BITS:0] local_rd_ptr_gray_o,
    output logic [FIFO_DEPTH_BITS:0] sync_wr_ptr_gray_o,
    output logic [FIFO_DEPTH_BITS:0] sync_rd_ptr_gray_o
);

    // Šírka dát ukladaných do interného FIFO (TDATA + TUSER + TLAST)
    localparam int ActualPayloadWidth = DATA_WIDTH + USER_WIDTH + 1;
    localparam int PtrWidth           = FIFO_DEPTH_BITS + 1; // Celková šírka pointera

    // Signály prepojenia s interným FIFO
    logic wr_full, wr_overflow;
    logic rd_empty, rd_underflow;
    logic wr_en;
    logic rd_en;

    // Interné signály pre diagnostiku pointerov (celé šírky)
    logic [PtrWidth-1:0] local_wr_ptr_gray_internal;
    logic [PtrWidth-1:0] local_rd_ptr_gray_internal;
    logic [PtrWidth-1:0] sync_wr_ptr_gray_internal;
    logic [PtrWidth-1:0] sync_rd_ptr_gray_internal;


    typedef struct packed {
        logic              tlast;
        logic [USER_WIDTH-1:0] tuser;
        logic [DATA_WIDTH-1:0] tdata;
    } internal_payload_t;

    internal_payload_t wr_payload;
    internal_payload_t rd_payload;

    assign wr_payload.tlast = s_axis.TLAST;
    assign wr_payload.tuser = s_axis.TUSER;
    assign wr_payload.tdata = s_axis.TDATA;

    assign wr_en = s_axis.TVALID && !wr_full;
    assign s_axis.TREADY = !wr_full;

    assign rd_en = m_axis.TREADY && !rd_empty;
    assign m_axis.TVALID = !rd_empty;

    assign m_axis.TDATA = rd_payload.tdata;
    assign m_axis.TLAST = rd_payload.tlast;
    assign m_axis.TUSER = rd_payload.tuser;

    assign m_axis.TKEEP = (KEEP_WIDTH > 0) ? {KEEP_WIDTH{1'b1}} : '0;
    assign m_axis.TID   = (ID_WIDTH > 0)   ? {ID_WIDTH{1'b0}}   : '0;
    assign m_axis.TDEST = (DEST_WIDTH > 0) ? {DEST_WIDTH{1'b0}} : '0;


    // Inštancia asynchrónneho FIFO
    AsyncFifoGeneric #(
        .DATA_WIDTH     ( ActualPayloadWidth ),
        .ADDR_WIDTH     ( FIFO_DEPTH_BITS    ), // ADDR_WIDTH pre FIFO = FIFO_DEPTH_BITS
        .RAM_STYLE      ( RAM_STYLE          ),
        .TWO_STAGE_SYNC ( TWO_STAGE_SYNC     )
    ) i_async_fifo (
        .wr_rst_ni    ( s_rst_ni           ),
        .wr_clk       ( s_clk_i            ),
        .wr_en        ( wr_en              ),
        .wr_data      ( wr_payload         ),
        .wr_full      ( wr_full            ),
        .wr_overflow  ( wr_overflow        ),

        .rd_rst_ni    ( m_rst_ni           ),
        .rd_clk       ( m_clk_i            ),
        .rd_en        ( rd_en              ),
        .rd_data      ( rd_payload         ),
        .rd_empty     ( rd_empty           ),
        .rd_underflow ( rd_underflow       ),

        .level        ( level_o            ),

        // Pripojenie diagnostických signálov z AsyncFifoGeneric
        .wr_ptr_gray_o     ( local_wr_ptr_gray_internal ),
        .rd_ptr_gray_o     ( local_rd_ptr_gray_internal ),
        .sync_wr_ptr_gray_o( sync_wr_ptr_gray_internal  ),
        .sync_rd_ptr_gray_o( sync_rd_ptr_gray_internal  )
        // LSB porty odstránené z AsyncFifoGeneric
    );

    // Priradenie stavových výstupov
    assign wr_overflow_o       = wr_overflow;
    assign rd_underflow_o      = rd_underflow;
    assign internal_rd_empty_o = rd_empty;
    assign internal_wr_full_o  = wr_full;
    // Priradenie nových diagnostických výstupov (celé pointery)
    assign local_wr_ptr_gray_o = local_wr_ptr_gray_internal;
    assign local_rd_ptr_gray_o = local_rd_ptr_gray_internal;
    assign sync_wr_ptr_gray_o  = sync_wr_ptr_gray_internal;
    assign sync_rd_ptr_gray_o  = sync_rd_ptr_gray_internal;

endmodule

`default_nettype wire

`endif // AXIS_CDC_FIFO_SV

