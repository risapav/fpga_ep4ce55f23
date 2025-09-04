/**
 * @brief       Generuje AXI4-Stream výstup s farebným gradientom.
 * @details     Modul vytvára diagonálny farebný gradient podľa pozície pixelu (x, y).
 *              Používa vnútorný frame streamer, ktorý generuje súradnice pixelov,
 *              a kombinačný modul `GradientPattern`, ktorý vypočíta farbu podľa súčtu x a y.
 *              Výsledný dátový tok je vystavený ako AXI4-Stream master rozhranie.
 *
 * @param[in]   DATA_WIDTH          Šírka dát (počet bitov pre farbu).
 * @param[in]   USER_WIDTH          Šírka USER signálu AXI4-Stream.
 * @param[in]   ID_WIDTH            Šírka ID signálu AXI4-Stream (ak je využívaný).
 * @param[in]   DEST_WIDTH          Šírka DEST signálu AXI4-Stream (ak je využívaný).
 * @param[in]   H_RES               Horizontálne rozlíšenie generovaného obrazu (pixely).
 * @param[in]   V_RES               Vertikálne rozlíšenie generovaného obrazu (pixely).
 *
 * @input       clk_i               Hodinový signál pre generovanie dát.
 * @input       rst_ni              Aktívny nízky asynchrónny reset modulu.
 * @output      m_axis              AXI4-Stream master rozhranie s generovanými dátami.
 *
 * @example
 * axis_gradient_generator #(
 *   .DATA_WIDTH(16),
 *   .USER_WIDTH(1),
 *   .ID_WIDTH(0),
 *   .DEST_WIDTH(0),
 *   .H_RES(1024),
 *   .V_RES(768)
 * ) u_gradient_gen (
 *   .clk_i(clk),
 *   .rst_ni(rstn),
 *   .m_axis(m_axis_if)
 * );
 */


`ifndef AXIS_GRADIENT_GENERATOR
`define AXIS_GRADIENT_GENERATOR

`default_nettype none

import axi_pkg::*; // Nevyhnutný import pre prístup k AXI definíciám

//================================================================
// Modul: GradientPattern
// Účel: Kombinačne vypočíta farbu pre diagonálny prechod.
//================================================================
module GradientPattern #(
  parameter int H_RES       = 1024,
  parameter int V_RES       = 768,

  parameter int unsigned COUNTER_WIDTH = $clog2(H_RES)
)(
  input logic [COUNTER_WIDTH-1:0]  x_i,
  input logic [COUNTER_WIDTH-1:0]  y_i,
  output logic [15:0]  color_o
);
  logic [COUNTER_WIDTH:0] sum;

  // Logika je dostatočne jednoduchá a rýchla, optimalizácia nie je nutná.
  assign sum = x + y;
  assign color_o = {sum[10:6], sum[9:4], sum[8:3]};
endmodule

module axis_gradient_generator #(
  parameter int unsigned DATA_WIDTH = 16,
  parameter int unsigned USER_WIDTH = 1,
  parameter int unsigned ID_WIDTH   = 0,
  parameter int unsigned DEST_WIDTH = 0,

  parameter int unsigned H_RES      = 1024,
  parameter int unsigned V_RES      = 768
)(
  input  logic        clk_i,
  input  logic        rst_ni,
  axi4s_if.master     m_axis
);
  logic [11:0] x, y;
  logic [15:0] pattern_color;

  axi4s_if #(
    .DATA_WIDTH(DATA_WIDTH),
    .USER_WIDTH(USER_WIDTH),
    .ID_WIDTH(ID_WIDTH),
    .DEST_WIDTH(DEST_WIDTH)
  ) streamer_axis(clk);

  axis_frame_streamer #(
    .H_RES(H_RES), .V_RES(V_RES),
    .DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
    .ID_WIDTH(ID_WIDTH), .DEST_WIDTH(DEST_WIDTH)
  ) streamer (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .x_o(x),
    .y_o(y),
    .m_axis(streamer_axis)
  );

  GradientPattern #(
    .H_RES(H_RES), .V_RES(V_RES)
  ) pattern (
    .x_i(x), .y_i(y), .color_o(pattern_color)
  );

  always_ff @(posedge clk) begin
    if (!rstn) begin
      m_axis.TVALID <= 1'b0;
      m_axis.TDATA  <= '0;
      m_axis.TLAST  <= 1'b0;
      m_axis.TUSER  <= 1'b0;
    end else begin
      m_axis.TVALID <= streamer_axis.TVALID;

      if (streamer_axis.TVALID) begin
        m_axis.TDATA <= pattern_color;
        m_axis.TLAST <= streamer_axis.TLAST;
        m_axis.TUSER <= streamer_axis.TUSER;
      end
    end
  end

  assign streamer_axis.TREADY = m_axis.TREADY;

endmodule

`endif AXIS_GRADIENT_GENERATOR
