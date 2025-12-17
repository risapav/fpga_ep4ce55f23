/**
 * @file        axis_gradient_generator.sv
 * @brief       Generuje AXI4-Stream výstup s farebným gradientom.
 * @details     Vytvára diagonálny gradient (RGB565) kombináciou X a Y súradníc.
 * Využíva axis_frame_streamer pre riadenie časovania a protokolu.
 *
 * @param DATA_WIDTH    Šírka TDATA (typicky 16).
 * @param H_RES         Horizontálne rozlíšenie.
 * @param V_RES         Vertikálne rozlíšenie.
 */

`default_nettype none

`ifndef AXIS_GRADIENT_GENERATOR_SV
`define AXIS_GRADIENT_GENERATOR_SV

import axi_pkg::*;

// =============================================================================
// Modul: GradientPattern (Combinatorial Logic)
// =============================================================================
module GradientPattern #(
    parameter int H_RES         = 1024,
    parameter int V_RES         = 768,
    parameter int unsigned COUNTER_WIDTH = $clog2(H_RES)
)(
    input  wire logic [COUNTER_WIDTH-1:0] x_i,
    input  wire logic [COUNTER_WIDTH-1:0] y_i,
    output logic [15:0]                   color_o
);
    logic [COUNTER_WIDTH:0] sum;

    // Oprava: Použitie správnych názvov vstupných signálov (x_i, y_i)
    assign sum = x_i + y_i;
    
    // Mapovanie súčtu na RGB565 (jednoduchý prechod)
    assign color_o = {sum[10:6], sum[9:4], sum[8:3]};

endmodule

// =============================================================================
// Modul: axis_gradient_generator (Wrapper)
// =============================================================================
module axis_gradient_generator #(
    parameter int unsigned DATA_WIDTH = 16,
    parameter int unsigned USER_WIDTH = 1,
    parameter int unsigned ID_WIDTH   = 0,
    parameter int unsigned DEST_WIDTH = 0,

    parameter int unsigned H_RES      = 1024,
    parameter int unsigned V_RES      = 768
)(
    input  wire logic       clk_i,
    input  wire logic       rst_ni,
    axi4s_if.master         m_axis
);

    // -------------------------------------------------------------------------
    // 1. Interné signály a parametre
    // -------------------------------------------------------------------------
    localparam int unsigned COUNTER_WIDTH = $clog2(H_RES);

    logic [COUNTER_WIDTH-1:0] x_coord;
    logic [COUNTER_WIDTH-1:0] y_coord;
    logic [15:0]              pattern_data;

    // -------------------------------------------------------------------------
    // 2. Interný Interface
    // -------------------------------------------------------------------------
    axi4s_if #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .DEST_WIDTH(DEST_WIDTH)
    ) int_axis ();

    // -------------------------------------------------------------------------
    // 3. Frame Streamer (Generuje časovanie a riadiace signály)
    // -------------------------------------------------------------------------
    axis_frame_streamer #(
        .H_RES(H_RES), 
        .V_RES(V_RES),
        .DATA_WIDTH(DATA_WIDTH), 
        .USER_WIDTH(USER_WIDTH),
        .ID_WIDTH(ID_WIDTH), 
        .DEST_WIDTH(DEST_WIDTH)
    ) u_streamer (
        .clk_i  (clk_i),
        .rst_ni (rst_ni),
        .x_o    (x_coord),
        .y_o    (y_coord),
        .m_axis (int_axis)
    );

    // -------------------------------------------------------------------------
    // 4. Pattern Generator (Generuje dáta)
    // -------------------------------------------------------------------------
    GradientPattern #(
        .H_RES(H_RES), 
        .V_RES(V_RES)
    ) u_pattern (
        .x_i     (x_coord),
        .y_i     (y_coord), 
        .color_o (pattern_data)
    );

    // -------------------------------------------------------------------------
    // 5. Výstupné priradenie (Output Mapping)
    // -------------------------------------------------------------------------
    // axis_frame_streamer riadi TVALID, TLAST, TUSER. 
    // My len vkladáme TDATA.
    
    assign m_axis.TVALID = int_axis.TVALID;
    assign m_axis.TLAST  = int_axis.TLAST;
    assign m_axis.TUSER  = int_axis.TUSER;
    assign m_axis.TKEEP  = int_axis.TKEEP;
    assign m_axis.TID    = int_axis.TID;
    assign m_axis.TDEST  = int_axis.TDEST;

    // Padding dát ak je šírka zbernice väčšia ako 16 bitov
    assign m_axis.TDATA  = (DATA_WIDTH == 16) ? pattern_data : {{(DATA_WIDTH-16){1'b0}}, pattern_data};

    // Spätná väzba pre flow control (Backpressure)
    assign int_axis.TREADY = m_axis.TREADY;

endmodule

`endif // AXIS_GRADIENT_GENERATOR_SV

`default_nettype wire
