/**
 * @file        axis_frame_streamer.sv
 * @brief       AXI4-Stream Frame Streamer generujúci súradnice pixelov.
 * @details     Generuje sekvenčný tok pixelových súradníc (x, y) a riadiace
 * signály (TVALID, TLAST, TUSER) pre AXI4-Stream Video.
 *
 * Správanie signálov:
 * - TVALID: Trvalo log.1 (okrem resetu).
 * - TUSER[0]: Start of Frame (SOF) - aktívny pri pixeli (0,0).
 * - TLAST: End of Line (EOL) - aktívny na konci každého riadku.
 *
 * @param H_RES         Horizontálne rozlíšenie.
 * @param V_RES         Vertikálne rozlíšenie.
 * @param DATA_WIDTH    Šírka TDATA.
 * @param USER_WIDTH    Šírka TUSER.
 * @param KEEP_WIDTH    Šírka TKEEP.
 * @param ID_WIDTH      Šírka TID.
 * @param DEST_WIDTH    Šírka TDEST.
 * @param COUNTER_WIDTH Šírka čítačov.
 */

`default_nettype none

`ifndef AXIS_FRAME_STREAMER_SV
`define AXIS_FRAME_STREAMER_SV

import axi_pkg::*;

module axis_frame_streamer #(
    parameter int unsigned H_RES = 1024,
    parameter int unsigned V_RES = 768,

    parameter int unsigned DATA_WIDTH = 16,
    parameter int unsigned USER_WIDTH = 1,
    parameter int unsigned KEEP_WIDTH = DATA_WIDTH / 8,
    parameter int unsigned ID_WIDTH   = 0,
    parameter int unsigned DEST_WIDTH = 0,

    parameter int unsigned COUNTER_WIDTH = $clog2(H_RES)
)(
    input  wire logic                      clk_i,
    input  wire logic                      rst_ni,
    
    // Diagnostické výstupy
    output logic [COUNTER_WIDTH-1:0]       x_o,
    output logic [COUNTER_WIDTH-1:0]       y_o,
    
    // AXI Stream Master
    axi4s_if.master                        m_axis
);

    // -------------------------------------------------------------------------
    // 1. Signály a Registre
    // -------------------------------------------------------------------------
    logic [COUNTER_WIDTH-1:0] x_reg;
    logic [COUNTER_WIDTH-1:0] y_reg;

    // -------------------------------------------------------------------------
    // 2. Logika Počítadiel (Sequential)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            x_reg <= '0;
            y_reg <= '0;
        end else begin
            // Počítadlá bežia len keď je Master Valid (vždy) a Slave Ready
            if (m_axis.TREADY) begin
                if (x_reg == H_RES - 1) begin
                    x_reg <= '0;
                    if (y_reg == V_RES - 1) begin
                        y_reg <= '0;
                    end else begin
                        y_reg <= y_reg + 1'b1;
                    end
                end else begin
                    x_reg <= x_reg + 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. AXI Výstupy (Combinatorial / Assignments)
    // -------------------------------------------------------------------------
    
    // Dáta sú platné ihneď po uvoľnení resetu
    assign m_axis.TVALID = 1'b1; 

    // TUSER[0] indikuje Start of Frame (prvý pixel)
    // Musí byť zosynchronizovaný s x_reg=0, y_reg=0
    assign m_axis.TUSER = (USER_WIDTH > 0) ? {USER_WIDTH{(x_reg == 0 && y_reg == 0)}} : '0;

    // TLAST indikuje End of Line (posledný pixel v riadku)
    // AXI Video štandard vyžaduje TLAST na konci KAŽDÉHO riadku, nielen snímky
    assign m_axis.TLAST = (x_reg == H_RES - 1);

    // Dáta (ak nie sú špecifikované, posielame 0 alebo môžeme poslať súradnice)
    assign m_axis.TDATA = '0; 

    // Fixné signály
    assign m_axis.TKEEP = (KEEP_WIDTH > 0) ? {KEEP_WIDTH{1'b1}} : '0;
    assign m_axis.TID   = (ID_WIDTH > 0)   ? {ID_WIDTH{1'b0}}   : '0;
    assign m_axis.TDEST = (DEST_WIDTH > 0) ? {DEST_WIDTH{1'b0}} : '0;

    // -------------------------------------------------------------------------
    // 4. Diagnostické Výstupy
    // -------------------------------------------------------------------------
    assign x_o = x_reg;
    assign y_o = y_reg;

endmodule

`endif // AXIS_FRAME_STREAMER_SV

`default_nettype wire
