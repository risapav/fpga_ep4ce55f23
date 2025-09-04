//=============================================================================
// Rozšírený ResetController s podporou ľubovoľného počtu domén (cez generate)
// + Testbench (ResetController_tb.sv)
//=============================================================================

//===========================
// Modul: ResetSync (základ)
//===========================
module ResetSync #(
    parameter int N_STAGES = 2
) (
    input  logic clk,
    input  logic resetn_async,
    output logic resetn_sync
);
    logic [N_STAGES-1:0] sync_reg;

    always_ff @(posedge clk or negedge resetn_async) begin
        if (!resetn_async)
            sync_reg <= '0;
        else
            sync_reg <= {sync_reg[N_STAGES-2:0], 1'b1};
    end

    assign resetn_sync = sync_reg[N_STAGES-1];
endmodule


//===========================================
// Modul: ResetController (rozšírená verzia)
//===========================================
module ResetController #(
    parameter int N_DOMAINS = 3,
    parameter int N_STAGES = 2
)(
    input  logic RESET_N,
    input  logic pll_locked,

    input  logic [N_DOMAINS-1:0] clk,
    output logic [N_DOMAINS-1:0] resetn_sync
);

    logic global_resetn_async;
    assign global_resetn_async = RESET_N & pll_locked;

    genvar i;
    generate
        for (i = 0; i < N_DOMAINS; i++) begin : gen_reset_sync
            ResetSync #(.N_STAGES(N_STAGES)) sync_inst (
                .clk           (clk[i]),
                .resetn_async  (global_resetn_async),
                .resetn_sync   (resetn_sync[i])
            );
        end
    endgenerate
endmodule


//=============================
// Testbench: ResetController
//=============================
module ResetController_tb;
    parameter int N_DOMAINS = 3;
    logic [N_DOMAINS-1:0] clk;
    logic [N_DOMAINS-1:0] resetn_sync;

    logic RESET_N;
    logic pll_locked;

    // Generate different clocks
    initial begin
        clk[0] = 0;
        forever #5 clk[0] = ~clk[0]; // 100 MHz
    end

    initial begin
        clk[1] = 0;
        forever #7 clk[1] = ~clk[1]; // ~71 MHz
    end

    initial begin
        clk[2] = 0;
        forever #11 clk[2] = ~clk[2]; // ~45 MHz
    end

    // DUT
    ResetController #(
        .N_DOMAINS(N_DOMAINS),
        .N_STAGES(2)
    ) dut (
        .RESET_N      (RESET_N),
        .pll_locked   (pll_locked),
        .clk          (clk),
        .resetn_sync  (resetn_sync)
    );

    // Stimulus
    initial begin
        $display("=== Začínam test reset synchronizácie ===");

        // Start with reset asserted
        RESET_N = 0;
        pll_locked = 0;
        #50;

        RESET_N = 1;
        pll_locked = 0;
        #50;

        RESET_N = 1;
        pll_locked = 1;
        #200;

        RESET_N = 0;
        #30;

        RESET_N = 1;
        #200;

        $display("=== Test hotov ===");
        $finish;
    end

    // Monitor
    always @(posedge clk[0]) begin
        $display("[clk0] resetn_sync = %b", resetn_sync[0]);
    end
endmodule
