/**
 * @brief       Synchronizátor asynchrónneho resetu pre cieľovú hodinovú doménu.
 * @details     Modul zabezpečuje bezpečné prenesenie asynchrónneho reset signálu
 *              do cieľovej hodinovej domény pomocou dvojstupňového synchronizátora.
 *              Výstupný reset je synchronný a aktívny v logickej nule.
 *
 * @input       clk_i       Hodinový signál cieľovej domény.
 * @input       rst_ni      Asynchrónny reset, aktívny nízky (negatívna logika).
 * @output      rst_no      Synchronný reset, aktívny nízky.
 *
 * @example
 * cdc_reset_synchronizer u_reset_sync (
 *   .clk_i(clk),
 *   .rst_ni(async_rst_n),
 *   .rst_no(sync_rst_n)
 * );
 */


`ifndef RESET_SYNCHRONIZER_SV
`define RESET_SYNCHRONIZER_SV

`default_nettype none
module cdc_reset_synchronizer (
  input  logic clk_i,     // Cieľová hodinová doména
  input  logic rst_ni,    // Vstupný asynchrónny reset, aktívny v nule
  output logic rst_no     // Výstupný synchrónny reset, aktívny v nule
);
  logic rst_n_sync1_d;
  // Dvojstupňový synchronizátor na zachytenie uvoľnenia resetu
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rst_n_sync1_d   <= 1'b0;
      rst_no          <= 1'b0;
    end else begin
      rst_n_sync1_d   <= 1'b1;
      rst_no          <= rst_n_sync1_d;
    end
  end
endmodule

`endif //RESET_SYNCHRONIZER_SV
