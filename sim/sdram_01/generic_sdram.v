// generic_sdram.sv - Verzia 5.2.1 - Finálna oprava "multiple drivers"
//
// Popis:
// Finálna, robustná verzia simulačného modelu SDRAM.
//
// Kľúčové zmeny v tejto verzii:
// 1. OPRAVA (Multiple Drivers): Inicializácia pamäte bola presunutá z `initial` bloku
//    priamo do resetovacej vetvy `always_ff`, čím sa odstránil problém s viacerými drivermi.
//
// Author: refactor by assistant & user feedback

`timescale 1ns / 1ps
(* default_nettype = "none" *)

module generic_sdram #(
    // --- Fyzická Konfigurácia ---
    parameter int C_DQ_BITS     = 16,
    parameter int C_COLS        = 9,
    parameter int C_ROWS        = 13,
    parameter int C_BANKS       = 4,
    // --- Konfigurácia Časovania v Cykloch ---
    parameter int CLOCK_FREQ_HZ = 100_000_000,
    parameter int tRP           = 3,
    parameter int tRCD          = 3,
    parameter int tWR           = 2,
    parameter int tRAS          = 7,
    parameter int tRFC          = 9
) (
    inout  wire [C_DQ_BITS-1:0] DQ,
    input  wire [12:0]           A,
    input  wire [1:0]            BA,
    input  wire                  CLK,
    input  wire                  rstn,
    input  wire                  CKE,
    input  wire                  CS_n,
    input  wire                  RAS_n,
    input  wire                  CAS_n,
    input  wire                  WE_n,
    input  wire [1:0]            DQM
);

    wire [3:0] cmd = {CS_n, RAS_n, CAS_n, WE_n};
    localparam [3:0] CMD_MRS   = 4'b0000, CMD_AR    = 4'b0001, CMD_PRE   = 4'b0010,
                     CMD_ACT   = 4'b0011, CMD_WRITE = 4'b0100, CMD_READ  = 4'b0101;

    localparam int REFRESH_INTERVAL = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam int MAX_CAS_LATENCY  = 8;

    // --- Pamäť a Stavové Registre ---
    reg [C_DQ_BITS-1:0] mem [0:C_BANKS-1][0:(1<<C_ROWS)-1][0:(1<<C_COLS)-1];
    logic [C_ROWS-1:0] active_row [0:C_BANKS-1];
    logic              bank_is_active [0:C_BANKS-1];
    logic              auto_precharge_req [0:C_BANKS-1];

    // --- Detailné Časovače ---
    logic [$clog2(tRCD+1):0] bank_trcd_timer [0:C_BANKS-1];
    logic [$clog2(tRP+1):0]  bank_trp_timer [0:C_BANKS-1];
    logic [$clog2(tRAS+1):0] bank_tras_timer [0:C_BANKS-1];
    logic [$clog2(tWR+1):0]  write_recovery_timer;
    logic [$clog2(tRFC+1):0] refresh_cycle_timer;
    logic [23:0]             refresh_request_timer;

    // --- Dynamické parametre z Mode Registra ---
    logic [2:0]  cas_latency;
    logic [9:0]  burst_length;

    // --- Registre pre Burst a Pipeline ---
    logic [9:0]                 read_burst_cnt, write_burst_cnt;
    logic [C_COLS-1:0]          read_col, write_col;
    logic [1:0]                 read_bank, write_bank;
    logic [MAX_CAS_LATENCY-1:0] cas_pipe_valid;
    logic [C_DQ_BITS-1:0]       cas_pipe_data [0:MAX_CAS_LATENCY-1];
    logic [1:0]                 cas_pipe_dqm [0:MAX_CAS_LATENCY-1];

    // --- Riadenie DQ Zbernice ---
    logic [C_DQ_BITS-1:0] dq_out;
    logic                 dq_oe;

    function automatic [C_DQ_BITS-1:0] mask_data(input [C_DQ_BITS-1:0] data, input [1:0] dqm);
        logic [C_DQ_BITS-1:0] temp = data;
        if (dqm[0]) temp[7:0]   = 'z;
        if (dqm[1]) temp[15:8] = 'z;
        return temp;
    endfunction

    assign DQ = dq_oe ? mask_data(dq_out, cas_pipe_dqm[cas_latency-1]) : {C_DQ_BITS{1'bz}};

    // --- Hlavný Sekvenčný Proces ---
    always_ff @(posedge CLK) begin
        automatic int safe_cl = 0;

        if (!rstn) begin
            for (integer i = 0; i < C_BANKS; i = i + 1) begin
                bank_is_active[i] <= 1'b0; bank_trcd_timer[i] <= 0;
                bank_trp_timer[i] <= 0; bank_tras_timer[i] <= 0;
                auto_precharge_req[i] <= 1'b0;
            end
            read_burst_cnt <= 0; write_burst_cnt <= 0;
            cas_pipe_valid <= '0;
            write_recovery_timer <= 0; refresh_cycle_timer <= 0; refresh_request_timer <= 0;
            cas_latency  <= 'x;
            burst_length <= 'x;
            dq_oe <= 1'b0;
            dq_out <= '0;

            // OPRAVA: Inicializácia pamäte sa teraz deje tu, v synchrónnom resete
            for (integer b = 0; b < C_BANKS; b = b + 1)
                for (integer r = 0; r < (1<<C_ROWS); r = r + 1)
                    for (integer c = 0; c < (1<<C_COLS); c = c + 1)
                        mem[b][r][c] = 0;

        end else if (CKE) begin
            // Znižovanie časovačov
            for (integer i = 0; i < C_BANKS; i = i + 1) begin
                if (bank_trcd_timer[i] > 0) bank_trcd_timer[i] <= bank_trcd_timer[i] - 1;
                if (bank_trp_timer[i] > 0)  bank_trp_timer[i]  <= bank_trp_timer[i] - 1;
                if (bank_tras_timer[i] > 0) bank_tras_timer[i] <= bank_tras_timer[i] - 1;
            end
            if (write_recovery_timer > 0) write_recovery_timer <= write_recovery_timer - 1;
            if (refresh_cycle_timer > 0)  refresh_cycle_timer  <= refresh_cycle_timer - 1;

            // Kontrola požiadavky na Refresh
            if (refresh_request_timer >= REFRESH_INTERVAL) begin
                $display("[%0t] ERROR: Refresh interval exceeded!", $time);
                refresh_request_timer <= 0;
            end else begin
                refresh_request_timer <= refresh_request_timer + 1;
            end

            // Pipeline pre Čítanie (Posuvný register)
            // 1. Vždy posunieme existujúce dáta v pipeline
            cas_pipe_valid <= {cas_pipe_valid[MAX_CAS_LATENCY-2:0], 1'b0};
            for (integer i = MAX_CAS_LATENCY-1; i > 0; i = i - 1) begin
                cas_pipe_data[i] <= cas_pipe_data[i-1];
                cas_pipe_dqm[i]  <= cas_pipe_dqm[i-1];
            end
            cas_pipe_valid[0] <= 1'b0;

            // Dekódovanie Príkazov
            if (read_burst_cnt == 0 && write_burst_cnt == 0 && refresh_cycle_timer == 0) begin
                if (!CS_n) begin
                    case (cmd)
                        CMD_MRS: begin
                            unique case(A[2:0])
                                3'b000: burst_length <= 1; 3'b001: burst_length <= 2;
                                3'b010: burst_length <= 4; 3'b011: burst_length <= 8;
                                3'b111: burst_length <= (1 << C_COLS);
                                default: burst_length <= 'x;
                            endcase
                            cas_latency <= A[6:4];
                        end
                        CMD_ACT: begin
                            if (bank_trp_timer[BA] == 0) begin
                                bank_is_active[BA]  <= 1'b1; active_row[BA]      <= A;
                                bank_trcd_timer[BA] <= tRCD; bank_tras_timer[BA] <= tRAS;
                            end else $display("[%0t] ERROR: tRP Violation on Bank %d", $time, BA);
                        end
                        CMD_READ: begin
                            if (bank_is_active[BA] && bank_trcd_timer[BA] == 0) begin
                                read_bank <= BA; read_col <= A[C_COLS-1:0];
                                read_burst_cnt <= burst_length;
                                cas_pipe_dqm[0] <= DQM;
                                auto_precharge_req[BA] <= A[10];
                            end else $display("[%0t] ERROR: tRCD Violation on Bank %d", $time, BA);
                        end
                        CMD_WRITE: begin
                            if (bank_is_active[BA] && bank_trcd_timer[BA] == 0) begin
                                write_bank <= BA; write_col <= A[C_COLS-1:0];
                                write_burst_cnt <= burst_length;
                                auto_precharge_req[BA] <= A[10];
                            end else $display("[%0t] ERROR: tRCD Violation on Bank %d", $time, BA);
                        end
                        CMD_PRE: begin
                            if (bank_tras_timer[BA] == 0 && write_recovery_timer == 0) begin
                                bank_is_active[BA] <= 1'b0; bank_trp_timer[BA] <= tRP;
                            end else $display("[%0t] ERROR: tRAS or tWR Violation on Bank %d", $time, BA);
                        end
                        CMD_AR: begin
                            refresh_cycle_timer <= tRFC;
                            refresh_request_timer <= 0;
                        end
                    endcase
                end
            end

            // 2. Vkladáme nové dáta, ak je aktívny burst
            if (read_burst_cnt > 0) begin
                cas_pipe_valid[0] <= 1'b1;
                cas_pipe_data[0]  <= mem[read_bank][active_row[read_bank]][read_col];
                read_col          <= read_col + 1;
                read_burst_cnt    <= read_burst_cnt - 1;

                // Auto-precharge sa plánuje po poslednom slove
                if (read_burst_cnt == 1 && auto_precharge_req[read_bank]) begin
                    auto_precharge_req[read_bank] <= 1'b0;
                    if (bank_tras_timer[read_bank] == 0) begin
                        bank_is_active[read_bank] <= 1'b0;
                        bank_trp_timer[read_bank] <= cas_latency + burst_length + tRP;
                    end else $display("[%0t] ERROR: Auto-Precharge failed tRAS violation on Bank %d", $time, read_bank);
                end
            end else begin
                cas_pipe_valid[0] <= 1'b0;
            end

            // Spracovanie zapisovacieho burstu
            if (write_burst_cnt > 0) begin
                if (!DQM[0]) mem[write_bank][active_row[write_bank]][write_col][7:0]   <= DQ[7:0];
                if (!DQM[1]) mem[write_bank][active_row[write_bank]][write_col][15:8] <= DQ[15:8];
                write_col       <= write_col + 1;
                write_burst_cnt <= write_burst_cnt - 1;
                if (write_burst_cnt == 1) begin
                    write_recovery_timer <= tWR;
                    if (auto_precharge_req[write_bank]) begin
                        auto_precharge_req[write_bank] <= 1'b0;
                        if(bank_tras_timer[write_bank] == 0) begin
                            bank_is_active[write_bank] <= 1'b0;
                            bank_trp_timer[write_bank] <= tWR + tRP;
                        end else $display("[%0t] ERROR: Auto-Precharge failed tRAS violation on Bank %d", $time, write_bank);
                    end
                end
            end

            // Výstupná logika (registrovaná)
            if (!$isunknown(cas_latency) && cas_latency >= 1 && cas_latency <= MAX_CAS_LATENCY) begin
                safe_cl = $unsigned(cas_latency);
            end

            if (safe_cl > 0 && cas_pipe_valid[safe_cl-1]) begin
                dq_oe  <= 1'b1;
                dq_out <= cas_pipe_data[safe_cl-1];
            end else begin
                dq_oe <= 1'b0;
            end
        end // if CKE
    end

endmodule

`default_nettype wire
