/**
 * @brief       Dvojstupňový synchronizátor signálu pre CDC (Clock Domain Crossing).
 * @details     Modul slúži na bezpečné prenesenie asynchrónneho signálu do cieľovej hodinovej domény
 *              pomocou dvoch postupných registrov (flip-flopov). Tým sa minimalizuje riziko metastability.
 *              Šírka synchronizovaného signálu je parametrická (`WIDTH`).
 *
 * @param[in]   WIDTH       Počet bitov vstupného a výstupného signálu (predvolené 1).
 * @input       clk_i       Hodinový signál cieľovej domény.
 * @input       rst_ni      Asynchrónny reset, aktívny nízky (negatívna logika).
 * @input       d_i         Asynchrónny vstupný signál (z inej hodinovej domény).
 * @output      q_o         Synchronizovaný výstupný signál, bezpečne prenesený do cieľovej domény.
 *
 * @example
 * cdc_two_flop_synchronizer #(
 *   .WIDTH(8)
 * ) u_sync (
 *   .clk_i(clk_target),
 *   .rst_ni(rst_n),
 *   .d_i(async_signal),
 *   .q_o(sync_signal)
 * );
 */


`ifndef TWO_FLOP_SYNCHRONIZER_SV
`define TWO_FLOP_SYNCHRONIZER_SV

`default_nettype none  // Zakazuje implicitné deklarácie - zvyšuje robustnosť

module cdc_two_flop_synchronizer #(
    parameter int WIDTH = 1 // Počet bitov synchronizovaného signálu
)(
  input  logic             clk_i,     // Hodinový signál cieľovej domény
  input  logic             rst_ni,    // Asynchrónny reset aktívny v L (negatívna logika)
  input  logic [WIDTH-1:0] d_i,       // Vstupný signál z inej (asynchrónnej) domény
  output logic [WIDTH-1:0] q_o        // Výstupný, synchronizovaný signál
);

  // === Prvý stupeň synchronizácie ===
  // Tento FF zachytáva asynchrónny vstup. Označený pre Quartus ako CDC synchronizátor.
  // Atribút `SYNCHRONIZER_IDENTIFICATION` zabezpečí automatické rozpoznanie nástrojom.
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
  logic [WIDTH-1:0] sync1_reg;

  // === Sekvenčná logika ===
  // Vykonáva dvojstupňovú synchronizáciu v cieľovej hodinovej doméne.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Inicializácia počas resetu - zabraňuje neznámym stavom
      sync1_reg <= 'd0;
      q_o       <= 'd0;
    end else begin
      // Prvý FF zachytí asynchrónny signál
      sync1_reg <= d_i;
      // Druhý FF produkuje synchronizovaný výstup
      q_o       <= sync1_reg;
    end
  end

endmodule

`endif // TWO_FLOP_SYNCHRONIZER_SV
