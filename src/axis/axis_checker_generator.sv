/**
 * @brief       AXI4-Stream generátor šachovnicového vzoru (checkerboard pattern)
 * @details     Modul `axis_checker_generator` generuje statický šachovnicový obrazec s definovateľným rozlíšením,
 *              šírkou a výškou buniek pomocou submodulu `CheckerPattern`. Dáta sú posielané cez AXI4-Stream rozhranie
 *              v štandarde RGB565. Modul generuje obrazce na základe súradníc (X,Y) získaných z modulu
 *              `axis_frame_streamer`, ktorý zabezpečuje správne načasovanie pixelových pozícií.
 *
 *              Vznikajúci obrazec je ideálny na testovanie a overovanie funkčnosti zobrazovacích ciest (napr. VGA, HDMI),
 *              ako aj diagnostiku problémov s časovaním alebo FIFO podtečením.
 *
 * @param[in]   DATA_WIDTH         Šírka dátového poľa v AXI4-Stream (bitov) – typicky 16 pre RGB565.
 * @param[in]   USER_WIDTH         Šírka TUSER signálu v AXI4-Stream rozhraní.
 * @param[in]   ID_WIDTH           Šírka TID signálu (identifikácia) v AXI4-Stream.
 * @param[in]   DEST_WIDTH         Šírka TDEST signálu v AXI4-Stream.
 *
 * @param[in]   H_RES              Horizontálne rozlíšenie (pixelov na riadok).
 * @param[in]   V_RES              Vertikálne rozlíšenie (počet riadkov).
 * @param[in]   COUNTER_WIDTH      Šírka počítadiel pre X/Y – odvodená z H_RES ako $clog2(H_RES).
 *
 * @input       clk_i              Vstupný hodinový signál (pixel clock).
 * @input       rst_ni             Asynchrónny reset, aktívny v L.
 *
 * @output      m_axis             Výstupné AXI4-Stream rozhranie, obsahujúce šachovnicový obrazec.
 *                                 Polia: TVALID, TDATA (RGB565), TLAST, TUSER, TREADY.
 *
 * @example
 * Názorný príklad použitia:
 *   axis_checker_generator #(
 *     .H_RES(800),
 *     .V_RES(600),
 *     .DATA_WIDTH(16),
 *     .USER_WIDTH(1)
 *   ) u_checker (
 *     .clk_i(clk),
 *     .rst_ni(rst_n),
 *     .m_axis(m_axi_checker)
 *   );
 */


`ifndef AXIS_CHECKERBOARD_GENERATOR
`define AXIS_CHECKERBOARD_GENERATOR

`default_nettype none

import axi_pkg::*; // Nevyhnutný import pre prístup k AXI definíciám

//================================================================
// Modul: CheckerPattern (Verzia 2.1 - Opravená syntax pre staršie nástroje)
//================================================================
module CheckerPattern #(
  parameter int H_RES       = 1024,
  parameter int V_RES       = 768,

  parameter int CELL_W_BITS = 7,
  parameter int CELL_H_BITS = 6,
  parameter logic [15:0] COLOR_1 = 16'hFFFF,
  parameter logic [15:0] COLOR_2 = 16'h0000

  parameter int unsigned COUNTER_WIDTH = $clog2(H_RES)
)(
  input logic [COUNTER_WIDTH-1:0]  x_i,
  input logic [COUNTER_WIDTH-1:0]  y_i,
  output logic [15:0]  color_o
);
  logic cell_x_is_odd;
  logic cell_y_is_odd;

  // ---- OPRAVA SYNTAXE ----
  // Krok 1: Výsledok bitového posunu uložíme do pomocných signálov.
  // Šírka musí zodpovedať šírke vstupných signálov x a y.
  logic [COUNTER_WIDTH-1:0 shifted_x;
  logic [COUNTER_WIDTH-1:0 shifted_y;

  assign shifted_x = x_i >> CELL_W_BITS;
  assign shifted_y = y_i >> CELL_H_BITS;

  // Krok 2: Až teraz vyberieme najnižší bit z pomocných signálov.
  assign cell_x_is_odd = shifted_x[0];
  assign cell_y_is_odd = shifted_y[0];

  // Finálna farba zostáva rovnaká.
  assign color_o = (cell_x_is_odd ^ cell_y_is_odd) ? COLOR_1 : COLOR_2;
endmodule

module axis_checker_generator #(
  parameter int unsigned DATA_WIDTH = 16,
  parameter int unsigned USER_WIDTH = 1,
  parameter int unsigned ID_WIDTH   = 0,
  parameter int unsigned DEST_WIDTH = 0,

  parameter int unsigned H_RES      = 1024,
  parameter int unsigned V_RES      = 768,

  parameter int unsigned COUNTER_WIDTH = $clog2(H_RES)
)(
    input  logic        clk_i,
    input  logic        rst_ni,
    axi4s_if.master     m_axis
);
  logic [COUNTER_WIDTH-1:0] x, y;
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

  CheckerPattern #(
    .H_RES(H_RES), .V_RES(V_RES)
  ) pattern (
    .x_i(x), .y_i(y), .color_o(pattern_color)
  );

  always_ff @(posedge clk) begin
    if (!rst_ni) begin
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

`endif //AXIS_CHECKERBOARD_GENERATOR
