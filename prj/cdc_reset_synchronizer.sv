`ifndef RESET_SYNCHRONIZER_SV
`define RESET_SYNCHRONIZER_SV

`default_nettype none

module cdc_reset_synchronizer #(
    parameter int WIDTH = 1,             // Počet bitov resetu
    parameter int STAGES = 2,            // Počet synchronizačných stupňov
    parameter bit REGISTERED_OUT = 1     // 1 = registrovaný výstup, 0 = combinational
)(
    input  logic clk_i,                  // Cieľová hodinová doména
    input  logic [WIDTH-1:0] rst_ni,    // Vstupný reset, aktívny nízky
    output logic [WIDTH-1:0] rst_no     // Výstupný reset, aktívny nízky
);

    // Pole registrov pre synchronizáciu
    logic [WIDTH-1:0] sync_regs [0:STAGES-1];
    logic [WIDTH-1:0] rst_comb;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : reset_bits

            // -------------------------------------------------------------
            // Synchronizácia jednotlivého bitu resetu
            // -------------------------------------------------------------
            always @(posedge clk_i) begin
                if (!rst_ni[i]) begin
                    sync_regs[0][i] <= 1'b0;
                    for (integer j = 1; j < STAGES; j = j + 1)
                        sync_regs[j][i] <= 1'b0;
                end else begin
                    sync_regs[0][i] <= 1'b1;
                    for (integer j = 1; j < STAGES; j = j + 1)
                        sync_regs[j][i] <= sync_regs[j-1][i];
                end
            end

            // -------------------------------------------------------------
            // Kombinačný výstup pre každý bit
            // -------------------------------------------------------------
            assign rst_comb[i] = sync_regs[STAGES-1][i];

        end
    endgenerate

    // -------------------------------------------------------------
    // Výstup: registrovaný alebo combinational
    // -------------------------------------------------------------
    generate
        if (REGISTERED_OUT) begin : g_registered_out
            always @(posedge clk_i) begin
                if (!rst_ni[0])
                    rst_no <= '0; // UPRAVENÉ
                else
                    rst_no <= rst_comb;
            end
        end else begin : g_comb_out
            assign rst_no = rst_comb;
        end
    endgenerate

endmodule

`default_nettype wire

`endif // RESET_SYNCHRONIZER_SV

