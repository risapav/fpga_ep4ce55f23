/**
 * @file        axis_checker_generator.sv
 * @brief       AXI4-Stream generátor šachovnicového vzoru.
 * @details     Generuje RGB565 šachovnicu na základe súradníc z axis_frame_streamer.
 * Slúži ako príklad integrácie modulov.
 *
 * @param H_RES         Horizontálne rozlíšenie.
 * @param V_RES         Vertikálne rozlíšenie.
 * @param CELL_W_BITS   Šírka bunky (log2).
 * @param CELL_H_BITS   Výška bunky (log2).
 * @param DATA_WIDTH    Šírka TDATA (16).
 */

`default_nettype none

`ifndef AXIS_CHECKERBOARD_GENERATOR_SV
`define AXIS_CHECKERBOARD_GENERATOR_SV

import axi_pkg::*;

// =============================================================================
// Modul: CheckerPattern (Pure Combinatorial)
// =============================================================================
module CheckerPattern #(
    parameter int H_RES         = 1024,
    parameter int V_RES         = 768,
    parameter int CELL_W_BITS   = 7,
    parameter int CELL_H_BITS   = 6,
    parameter logic [15:0] COLOR_1 = 16'hFFFF,
    parameter logic [15:0] COLOR_2 = 16'h0000,
    parameter int unsigned COUNTER_WIDTH = $clog2(H_RES)
)(
    input  wire logic [COUNTER_WIDTH-1:0] x_i,
    input  wire logic [COUNTER_WIDTH-1:0] y_i,
    output logic [15:0]                   color_o
);
    logic cell_x_is_odd;
    logic cell_y_is_odd;

    // Pomocné signály pre shift (Quartus friendly syntax)
    logic [COUNTER_WIDTH-1:0] shifted_x;
    logic [COUNTER_WIDTH-1:0] shifted_y;

    assign shifted_x = x_i >> CELL_W_BITS;
    assign shifted_y = y_i >> CELL_H_BITS;

    assign cell_x_is_odd = shifted_x[0];
    assign cell_y_is_odd = shifted_y[0];

    assign color_o = (cell_x_is_odd ^ cell_y_is_odd) ? COLOR_1 : COLOR_2;

endmodule

// =============================================================================
// Modul: axis_checker_generator (Wrapper)
// =============================================================================
module axis_checker_generator #(
    parameter int unsigned DATA_WIDTH = 16,
    parameter int unsigned USER_WIDTH = 1,
    parameter int unsigned ID_WIDTH   = 0,
    parameter int unsigned DEST_WIDTH = 0,

    parameter int unsigned H_RES      = 1024,
    parameter int unsigned V_RES      = 768,

    parameter int unsigned COUNTER_WIDTH = $clog2(H_RES)
)(
    input  wire logic       clk_i,
    input  wire logic       rst_ni,
    axi4s_if.master         m_axis
);

    // Interné signály
    logic [COUNTER_WIDTH-1:0] x_coord;
    logic [COUNTER_WIDTH-1:0] y_coord;
    logic [15:0]              pattern_data;

    // Interný interface pre prepojenie streameru a výstupu
    // Poznámka: axi4s_if by mal byť definovaný bez portov pre interné použitie,
    // alebo použijeme signály priamo ak nástroj nepodporuje vnorené inštancie iface.
    // Tu predpokladáme, že axis_frame_streamer akceptuje interface.
    axi4s_if #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .DEST_WIDTH(DEST_WIDTH)
    ) int_axis (); 

    // 1. Frame Streamer (Generuje X, Y, TLAST, TUSER, TVALID)
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
        .m_axis (int_axis) // Pripájame na interný interface
    );

    // 2. Pattern Generator (Generuje farbu na základe X, Y)
    CheckerPattern #(
        .H_RES(H_RES), 
        .V_RES(V_RES)
    ) u_pattern (
        .x_i     (x_coord), 
        .y_i     (y_coord), 
        .color_o (pattern_data)
    );

    // 3. Output Mapping (Zlúčenie signálov)
    // axis_frame_streamer už riadi flow control, my len vložíme dáta.
    
    // Prepojenie smerom von (Master -> Output)
    assign m_axis.TVALID = int_axis.TVALID;
    assign m_axis.TLAST  = int_axis.TLAST;
    assign m_axis.TUSER  = int_axis.TUSER;
    assign m_axis.TKEEP  = int_axis.TKEEP;
    assign m_axis.TID    = int_axis.TID;
    assign m_axis.TDEST  = int_axis.TDEST;
    
    // Vloženie vypočítaných dát
    // Ak je DATA_WIDTH > 16, doplníme nuly alebo rozšírime
    assign m_axis.TDATA = (DATA_WIDTH == 16) ? pattern_data : {{(DATA_WIDTH-16){1'b0}}, pattern_data};

    // Prepojenie smerom dnu (Output -> Master) - Backpressure
    assign int_axis.TREADY = m_axis.TREADY;

endmodule

`endif // AXIS_CHECKERBOARD_GENERATOR_SV

`default_nettype wire
