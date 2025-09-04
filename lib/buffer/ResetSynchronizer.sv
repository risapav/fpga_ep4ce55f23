// ResetSynchronizer.sv - Modul pre bezpečnú synchronizáciu resetu
//
// Popis:
// Tento modul prijíma externý, asynchrónny reset a generuje z neho
// čistý, synchrónny reset pre cieľovú hodinovú doménu. Tým sa predchádza
// problémom s "reset recovery/removal timing".
`ifndef RESET_SYNCHRONIZER_SV
`define RESET_SYNCHRONIZER_SV

`default_nettype none
module ResetSynchronizer (
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
