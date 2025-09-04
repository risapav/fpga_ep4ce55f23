/**
 * @brief       AXI4-Stream Frame Streamer generujúci súradnice pixelov.
 * @details     Modul generuje sekvenčný tok pixelových súradníc (x, y) pre dané
 *              rozlíšenie (H_RES × V_RES) a vystavuje ich ako AXI4-Stream master rozhranie.
 *              Signály TVALID, TLAST a TUSER sú riadené podľa štandardu AXI4-Stream:
 *                - TLAST označuje posledný pixel rámca (pravý spodný roh).
 *                - TUSER je aktívny na prvom pixeli rámca (ľavý horný roh).
 *              Modul je vhodný na testovanie a generovanie riadiacich signálov pre
 *              spracovanie videa alebo grafiky.
 *
 * @param[in]   H_RES               Horizontálne rozlíšenie rámca (pixely).
 * @param[in]   V_RES               Vertikálne rozlíšenie rámca (pixely).
 * @param[in]   DATA_WIDTH          Šírka dátového slova (bity).
 * @param[in]   USER_WIDTH          Šírka TUSER signálu.
 * @param[in]   KEEP_WIDTH          Šírka TKEEP signálu (DATA_WIDTH/8).
 * @param[in]   ID_WIDTH            Šírka TID signálu (ak sa používa).
 * @param[in]   DEST_WIDTH          Šírka TDEST signálu (ak sa používa).
 * @param[in]   COUNTER_WIDTH       Šírka čítačov pre x a y (vypočítaná z H_RES).
 *
 * @input       clk_i               Hodinový signál modulu.
 * @input       rst_ni              Aktívny nízky reset modulu.
 * @output      x_o                 Aktuálna horizontálna súradnica pixelu.
 * @output      y_o                 Aktuálna vertikálna súradnica pixelu.
 * @output      m_axis              AXI4-Stream master rozhranie so signálmi TVALID, TREADY, TDATA, TUSER, TLAST atď.
 *
 * @example
 * axis_frame_streamer #(
 *   .H_RES(1280),
 *   .V_RES(720),
 *   .DATA_WIDTH(24),
 *   .USER_WIDTH(1)
 * ) u_frame_streamer (
 *   .clk_i(clk),
 *   .rst_ni(rstn),
 *   .x_o(x),
 *   .y_o(y),
 *   .m_axis(m_axis_if)
 * );
 */


`ifndef AXIS_FRAME_STREAMER
`define AXIS_FRAME_STREAMER

`default_nettype none

import axi_pkg::*; // Nevyhnutný import pre prístup k AXI definíciám

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
  input  logic         clk_i,
  input  logic         rst_ni,
  output logic [COUNTER_WIDTH-1:0]  x_o,
  output logic [COUNTER_WIDTH-1:0]  y_o,
  axi4s_if.master      m_axis
);

  logic [COUNTER_WIDTH-1:0] x_reg, y_reg;
  assign x_o = x_reg;
  assign y_o = y_reg;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      x_reg        <= '0;
      y_reg        <= '0;
      m_axis.TVALID <= 1'b0;
      m_axis.TUSER  <= '0;
      m_axis.TLAST  <= 1'b0;
    end else begin
      m_axis.TVALID <= 1'b1;

      if (m_axis.TVALID && m_axis.TREADY) begin
        m_axis.TUSER <= (x_reg == 0 && y_reg == 0);
        m_axis.TLAST <= (x_reg == H_RES - 1) && (y_reg == V_RES - 1);

        if (x_reg == H_RES - 1) begin
          x_reg <= 0;
          y_reg <= (y_reg == V_RES - 1) ? 0 : y_reg + 1;
        end else begin
          x_reg <= x_reg + 1;
        end
      end
    end
  end

  // Default hodnoty pre nepoužívané signály
  generate
      if (KEEP_WIDTH > 0) assign m_axis.TKEEP = '1; else assign m_axis.TKEEP = '0;
      if (ID_WIDTH > 0)   assign m_axis.TID   = '0; else assign m_axis.TID = '0;
      if (DEST_WIDTH > 0) assign m_axis.TDEST = '0; else assign m_axis.TDEST = '0;
  endgenerate

endmodule

`endif // AXIS_FRAME_STREAMER
