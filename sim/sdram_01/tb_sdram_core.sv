// tb_sdram_core.sv - Verzia 3.1 - Opravené volania úloh a inicializácia
`timescale 1ns/1ps
(* default_nettype = "none" *)

module tb_sdram_core;

    localparam int C_DQ_BITS     = 16;
    localparam int C_COLS        = 9;
    localparam int C_ROWS        = 13;
    localparam int C_BANKS       = 4;
    localparam int BURST_LENGTH  = 8;
    localparam int CAS_LATENCY   = 3;
    localparam int tINIT         = 20000;
    localparam int tMRS          = 2;
    localparam int tRCD          = 3;
    localparam int tWR           = 2;
    localparam int tRP           = 3;

    logic CLK = 1'b0;
    logic rstn;
    logic CKE;
    always #5 CLK = ~CLK;

    wire [C_DQ_BITS-1:0] DQ;
    logic [12:0] A;
    logic [1:0]  BA;
    logic CS_n, RAS_n, CAS_n, WE_n;
    logic [1:0] DQM;

    logic [C_DQ_BITS-1:0] dq_out_tb;
    logic dq_oe_tb;
    assign DQ = dq_oe_tb ? dq_out_tb : {C_DQ_BITS{1'bz}};

    generic_sdram #(
        .C_DQ_BITS(C_DQ_BITS), .C_COLS(C_COLS), .C_ROWS(C_ROWS), .C_BANKS(C_BANKS),
        .tRP(tRP), .tRCD(tRCD), .tWR(tWR)
    ) uut (
        .DQ(DQ), .A(A), .BA(BA), .CLK(CLK), .rstn(rstn), .CKE(CKE),
        .CS_n(CS_n), .RAS_n(RAS_n), .CAS_n(CAS_n), .WE_n(WE_n), .DQM(DQM)
    );

    initial begin
        logic test_passed;
        logic [C_DQ_BITS-1:0] read_data;

        // 1. Inicializácia a Reset
        test_passed = 1'b1;
        rstn = 1'b0; CKE = 1'b0;
        CS_n = 1'b1; RAS_n = 1'b1; CAS_n = 1'b1; WE_n = 1'b1;
        A = '0; BA = '0; DQM = '0; dq_oe_tb = 1'b0;

        $display("[%0t] INFO: Spúšťam test. Aplikujem reset...", $time);
        repeat (20) @(posedge CLK);
        rstn = 1'b1;
        $display("[%0t] INFO: Reset uvoľnený. Čakám tINIT...", $time);

        repeat(tINIT) @(posedge CLK);
        CKE = 1'b1;
        $display("[%0t] INFO: CKE aktivované.", $time);

        // 2. Konfigurácia (Mode Register Set)
        sdram_precharge_all();
        repeat(tRP) @(posedge CLK);
        sdram_mrs();
        repeat(tMRS) @(posedge CLK);

        // 3. Aktivácia banky
        sdram_activate(2'b00, 13'd123);
        repeat (tRCD) @(posedge CLK);

        // 4. Zápis celého burstu
        sdram_write_burst(2'b00, 9'd50, 16'hA500);

        // 5. Čakanie na Write Recovery a Precharge
        repeat (tWR) @(posedge CLK);
        sdram_precharge_all();
        repeat (tRP) @(posedge CLK);

        // 6. Opätovná aktivácia a čítanie
        sdram_activate(2'b00, 13'd123);
        repeat (tRCD) @(posedge CLK);
        sdram_read_burst(2'b00, 9'd50);

        // 7. Čakanie na CAS Latency. Po tomto je PRVÉ slovo na zbernici.
        repeat (CAS_LATENCY) @(posedge CLK);
        $display("[%0t] INFO: Dáta sú teraz platné. Začínam overovanie...", $time);

        // 8. Overenie celého burstu - OPRAVENÁ A ROBUSTNÁ VERZIA
        for (integer i = 0; i < BURST_LENGTH; i = i + 1) begin
            // Najprv skontrolujeme dáta, ktoré sú už na zbernici platné
            read_data = DQ;
            if (read_data !== (16'hA500 + i)) begin
                $display("--------------------------------------------------");
                $display(">>>>> [%0t] CHYBA DÁT! Slovo #%0d", $time, i);
                $display(">>>>> Očakávané: %h, Prečítané: %h", 16'hA500 + i, read_data);
                $display("--------------------------------------------------");
                test_passed = 1'b0;
            end else begin
                $display("[%0t] INFO: Slovo #%0d správne: %h", $time, i, read_data);
            end

            // Až potom počkáme na ďalší cyklus pre nasledujúce slovo
            @(posedge CLK);
        end

        if (test_passed) $display("\n>>>>> TEST PREŠIEL! <<<<<");
        else             $display("\n>>>>> TEST ZLYHAL! <<<<<");

        $finish;
    end

    // --- Pomocné Úlohy (Tasks) ---
    task sdram_mrs;
        @(posedge CLK);
        $display("[%0t] TASK: LOAD MODE REGISTER", $time);
        CS_n  = 1'b0; RAS_n = 1'b0; CAS_n = 1'b0; WE_n = 1'b0;
        // Nastavíme BL=8, CL=3, čo zodpovedá nášmu radiču
        A[2:0] = 3'b011; A[6:4] = 3'b011; BA = '0;
        @(posedge CLK);
        CS_n  = 1'b1;
    endtask

    task sdram_activate(input [1:0] bank, input [12:0] row);
        @(posedge CLK);
        $display("[%0t] TASK: ACTIVATE Bank %d, Row %d", $time, bank, row);
        CS_n  = 1'b0; RAS_n = 1'b0; CAS_n = 1'b1; WE_n = 1'b1;
        BA    = bank; A     = row;
        @(posedge CLK);
        CS_n  = 1'b1;
    endtask

    task sdram_precharge_all;
        @(posedge CLK);
        $display("[%0t] TASK: PRECHARGE ALL", $time);
        CS_n  = 1'b0; RAS_n = 1'b0; CAS_n = 1'b1; WE_n = 1'b0;
        A[10] = 1'b1;
        @(posedge CLK);
        CS_n  = 1'b1;
    endtask

    task sdram_write_burst(input [1:0] bank, input [C_COLS-1:0] col, input [C_DQ_BITS-1:0] start_data);
        @(posedge CLK);
        $display("[%0t] TASK: WRITE BURST to Bank %d, Col %d", $time, bank, col);
        CS_n  = 1'b0; RAS_n = 1'b1; CAS_n = 1'b0; WE_n = 1'b0;
        BA    = bank; A[C_COLS-1:0] = col; A[10] = 1'b0;

        dq_oe_tb = 1'b1;
        for (integer i = 0; i < BURST_LENGTH; i = i + 1) begin
            dq_out_tb = start_data + i;
            @(posedge CLK);
        end
        CS_n  = 1'b1;
        dq_oe_tb = 1'b0;
    endtask

    task sdram_read_burst(input [1:0] bank, input [C_COLS-1:0] col);
        @(posedge CLK);
        $display("[%0t] TASK: READ BURST from Bank %d, Col %d", $time, bank, col);
        CS_n  = 1'b0; RAS_n = 1'b1; CAS_n = 1'b0; WE_n = 1'b1;
        BA    = bank; A[C_COLS-1:0] = col; A[10] = 1'b0;
        @(posedge CLK);
        CS_n  = 1'b1;
    endtask

endmodule

`default_nettype wire
