// ============================================================================
// Súbor: axis_cdc_fifo.sv
// Verzia: 2.1 (Použitie externého cdc_reset_synchronizer)
// Dátum: 27. október 2025
//
// Popis:
// Bezpečný AXI4-Stream Clock Domain Crossing FIFO.
// Ošetruje resety, handshake hazardy a bitovú kompatibilitu payloadu.
//
// Zlepšenia oproti verzii 2.0:
//  - Odstránená interná definícia 'cdc_reset_synchronizer'.
//  - Modul teraz závisí od externého súboru 'cdc_reset_synchronizer.sv'.
//  - Upravené inštancie synchronizátorov pre externý modul.
// ============================================================================

`ifndef AXIS_CDC_FIFO_SV
`define AXIS_CDC_FIFO_SV
`default_nettype none

import axi_pkg::*; // Centrálna konfigurácia AXI-Stream šírok

// ============================================================================
// Modul: axis_cdc_fifo
// ============================================================================
module axis_cdc_fifo #(
    // AXI šírky
    parameter int DATA_WIDTH     = axi_pkg::AXI_TDATA_WIDTH,
    parameter int USER_WIDTH     = axi_pkg::AXI_TUSER_WIDTH,
    parameter int KEEP_WIDTH     = DATA_WIDTH / 8,
    parameter int ID_WIDTH       = 0,
    parameter int DEST_WIDTH     = 0,
    // FIFO konfigurácia
    parameter int FIFO_DEPTH_BITS  = 8, // -> FIFO hlbka = 2^FIFO_DEPTH_BITS
    parameter string RAM_STYLE     = "block",
    parameter bit TWO_STAGE_SYNC   = 1'b1
)(
    // Slave (Write) Interface
    input  logic s_clk_i,
    input  logic s_rst_ni, // Externý reset pre WR doménu
    axi4s_if.slave s_axis,

    // Master (Read) Interface
    input  logic m_clk_i,
    input  logic m_rst_ni, // Externý reset pre RD doménu
    axi4s_if.master m_axis,

    // Stavové výstupy
    output logic [$clog2(1<<FIFO_DEPTH_BITS):0] level_o,
    output logic wr_overflow_o,
    output logic rd_underflow_o,
    output logic internal_rd_empty_o,
    output logic internal_wr_full_o,

    // Diagnostika (celé pointery)
    output logic [FIFO_DEPTH_BITS:0] local_wr_ptr_gray_o,
    output logic [FIFO_DEPTH_BITS:0] local_rd_ptr_gray_o,
    output logic [FIFO_DEPTH_BITS:0] sync_wr_ptr_gray_o,
    output logic [FIFO_DEPTH_BITS:0] sync_rd_ptr_gray_o
);

    // ========================================================================
    // Interné konštanty a signály
    // ========================================================================
    localparam int PAYLOAD_WIDTH = DATA_WIDTH + USER_WIDTH + 1; // TDATA+TUSER+TLAST
    localparam int PTR_WIDTH     = FIFO_DEPTH_BITS + 1;

    // CDC bezpečné resety (generované interne z externého modulu)
    logic s_rst_sync_ni, m_rst_sync_ni;

    // FIFO signály
    logic wr_full, wr_overflow;
    logic rd_empty, rd_underflow;
    logic wr_en;
    logic rd_en; // Enable pre čítanie z AsyncFifoGeneric

    // Payload flattening
    logic [PAYLOAD_WIDTH-1:0] wr_data; // Vektor na zápis do FIFO
    logic [PAYLOAD_WIDTH-1:0] rd_data; // Vektor prečítaný z FIFO

    // Gray pointer diagnostika
    logic [PTR_WIDTH-1:0] local_wr_ptr_gray_internal;
    logic [PTR_WIDTH-1:0] local_rd_ptr_gray_internal;
    logic [PTR_WIDTH-1:0] sync_wr_ptr_gray_internal;
    logic [PTR_WIDTH-1:0] sync_rd_ptr_gray_internal;

    // Signály pre registrovaný výstupný handshake
    logic        m_valid_q;        // Registrovaný TVALID
    logic [PAYLOAD_WIDTH-1:0] m_data_q; // Registrovaný payload (TLAST, TUSER, TDATA)

    // ========================================================================
    // Reset synchronizácia (CDC bezpečné)
    // ========================================================================
    // Použijeme externý modul 'cdc_reset_synchronizer'
    cdc_reset_synchronizer #(
        .WIDTH(1),    // Reset je 1-bitový
        .STAGES(2)    // Dvojstupňová synchronizácia
        // .REGISTERED_OUT(1) // Tento parameter nie je potrebný, používame rst_no priamo
    ) i_srst_sync (
        .clk_i   ( s_clk_i   ),
        .rst_ni  ( s_rst_ni  ), // Použije externý reset
        .rst_no  ( s_rst_sync_ni ) // Generuje CDC bezpečný reset pre WR logiku
    );

    cdc_reset_synchronizer #(
        .WIDTH(1),
        .STAGES(2)
        // .REGISTERED_OUT(1)
    ) i_mrst_sync (
        .clk_i   ( m_clk_i   ),
        .rst_ni  ( m_rst_ni  ), // Použije externý reset
        .rst_no  ( m_rst_sync_ni ) // Generuje CDC bezpečný reset pre RD logiku
    );

    // ========================================================================
    // AXI Write strana
    // ========================================================================
    assign wr_en = s_axis.TVALID && !wr_full;
    assign s_axis.TREADY = !wr_full;
    assign wr_data = { s_axis.TLAST, s_axis.TUSER, s_axis.TDATA };

    // ========================================================================
    // AXI Read strana – registrovaný handshake
    // ========================================================================
    assign rd_en = (!m_valid_q || m_axis.TREADY) && !rd_empty;

    always_ff @(posedge m_clk_i or negedge m_rst_sync_ni) begin
        if (!m_rst_sync_ni) begin
            m_valid_q <= 1'b0;
            m_data_q  <= '0;
        end else begin
            if (rd_en) begin
                m_valid_q <= 1'b1;
                m_data_q  <= rd_data;
            end else if (m_axis.TREADY && m_valid_q) begin
                m_valid_q <= 1'b0;
            end
        end
    end

    assign m_axis.TVALID = m_valid_q;
    assign { m_axis.TLAST, m_axis.TUSER, m_axis.TDATA } = m_data_q;
    assign m_axis.TKEEP = (KEEP_WIDTH > 0) ? {KEEP_WIDTH{1'b1}} : '0;
    assign m_axis.TID   = (ID_WIDTH > 0)   ? {ID_WIDTH{1'b0}}   : '0;
    assign m_axis.TDEST = (DEST_WIDTH > 0) ? {DEST_WIDTH{1'b0}} : '0;

    // ========================================================================
    // Inštancia Asynchrónneho FIFO
    // ========================================================================
    AsyncFifoGeneric #(
        .DATA_WIDTH     ( PAYLOAD_WIDTH    ),
        .ADDR_WIDTH     ( FIFO_DEPTH_BITS  ),
        .RAM_STYLE      ( RAM_STYLE        ),
        .TWO_STAGE_SYNC ( TWO_STAGE_SYNC   )
    ) i_async_fifo (
        .wr_rst_ni    ( s_rst_sync_ni     ), // Použije synchronizovaný reset
        .wr_clk       ( s_clk_i           ),
        .wr_en        ( wr_en             ),
        .wr_data      ( wr_data           ),
        .wr_full      ( wr_full           ),
        .wr_overflow  ( wr_overflow       ),

        .rd_rst_ni    ( m_rst_sync_ni     ), // Použije synchronizovaný reset
        .rd_clk       ( m_clk_i           ),
        .rd_en        ( rd_en             ),
        .rd_data      ( rd_data           ),
        .rd_empty     ( rd_empty          ),
        .rd_underflow ( rd_underflow      ),

        .level        ( level_o           ),

        .wr_ptr_gray_o      ( local_wr_ptr_gray_internal ),
        .rd_ptr_gray_o      ( local_rd_ptr_gray_internal ),
        .sync_wr_ptr_gray_o ( sync_wr_ptr_gray_internal  ),
        .sync_rd_ptr_gray_o ( sync_rd_ptr_gray_internal  )
    );

    // ========================================================================
    // Stavové a diagnostické výstupy
    // ========================================================================
    assign wr_overflow_o       = wr_overflow;
    assign rd_underflow_o      = rd_underflow;
    assign internal_rd_empty_o = rd_empty;
    assign internal_wr_full_o  = wr_full;

    assign local_wr_ptr_gray_o = local_wr_ptr_gray_internal;
    assign local_rd_ptr_gray_o = local_rd_ptr_gray_internal;
    assign sync_wr_ptr_gray_o  = sync_wr_ptr_gray_internal;
    assign sync_rd_ptr_gray_o  = sync_rd_ptr_gray_internal;

endmodule : axis_cdc_fifo


`default_nettype wire
`endif // AXIS_CDC_FIFO_SV

