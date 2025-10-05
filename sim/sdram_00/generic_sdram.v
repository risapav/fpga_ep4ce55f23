// generic_sdram.v - Jednoduchý, ale funkčný SDR SDRAM simulačný model
// Zdroj: Inšpirované open-source modelmi (napr. ZipCPU, m-k-s)
`timescale 1ns / 1ps
(* default_nettype = "none" *)

module generic_sdram (
    inout  wire [15:0] DQ,
    input  wire [12:0] A,
    input  wire [1:0]  BA,
    input  wire        CLK,
    input  wire        CKE,
    input  wire        CS_n,
    input  wire        RAS_n,
    input  wire        CAS_n,
    input  wire        WE_n,
    input  wire [1:0]  DQM
);

    // Konfigurácia pamäte (zodpovedá W9825G6KH)
    localparam C_COLS = 9;   // 2^9 = 512 stĺpcov
    localparam C_ROWS = 13;  // 2^13 = 8192 riadkov
    localparam C_BANKS = 4;
    localparam C_DQ_BITS = 16;
    localparam C_CAS_LATENCY = 3;

    // Pamäťové pole
    reg [C_DQ_BITS-1:0] mem [0:C_BANKS-1][0:(1<<C_ROWS)-1][0:(1<<C_COLS)-1];

    // Interné registre
    reg [3:0]  command;
    reg [C_ROWS-1:0] row_addr [0:C_BANKS-1];
    reg        bank_active [0:C_BANKS-1];
    reg [1:0]  read_bank, write_bank;
    reg [C_COLS-1:0] read_col, write_col;
    reg [C_CAS_LATENCY-1:0] read_pipe_valid;
    reg [C_DQ_BITS-1:0]     read_pipe_data [0:C_CAS_LATENCY-1];
    reg [3:0] write_burst_counter;

    // Priradenie pre obojsmerný DQ port
    reg  [C_DQ_BITS-1:0] dq_out;
    reg                  dq_oe;
    assign DQ = dq_oe ? dq_out : {C_DQ_BITS{1'bz}};

    // Dekódovanie príkazu
    always @(*) begin
        command = {CS_n, RAS_n, CAS_n, WE_n};
    end

    always @(posedge CLK) begin
        if (CKE) begin
            // --- Logika Zápisu ---
            if (write_burst_counter > 0) begin
                write_burst_counter <= write_burst_counter - 1;
                if(DQM[0] == 1'b0) mem[write_bank][row_addr[write_bank]][write_col][7:0]   <= DQ[7:0];
                if(DQM[1] == 1'b0) mem[write_bank][row_addr[write_bank]][write_col][15:8] <= DQ[15:8];
                write_col <= write_col + 1;
            end

            // --- Logika Čítania (Pipeline) ---
            dq_oe <= read_pipe_valid[C_CAS_LATENCY-1];
            dq_out <= read_pipe_data[C_CAS_LATENCY-1];

            for (integer i = C_CAS_LATENCY-1; i > 0; i=i-1) begin
                read_pipe_valid[i] <= read_pipe_valid[i-1];
                read_pipe_data[i]  <= read_pipe_data[i-1];
            end
            read_pipe_valid[0] <= 1'b0; // Default

            // --- Dekódovanie a Vykonanie Príkazov ---
            case (command)
                4'b0100: begin // ACTIVATE
                    bank_active[BA] <= 1'b1;
                    row_addr[BA]    <= A;
                end
                4'b0101: begin // READ
                    read_bank <= BA;
                    read_col  <= A[C_COLS-1:0];
                    if (bank_active[BA]) begin
                        read_pipe_valid[0] <= 1'b1;
                    end
                end
                4'b0110: begin // WRITE
                    write_bank <= BA;
                    write_col  <= A[C_COLS-1:0];
                    write_burst_counter <= 8; // Predpokladáme burst 8
                end
                4'b0111: begin // NOP / DESELECT
                    // No operation
                end
                4'b0010: begin // PRECHARGE
                    bank_active[BA] <= 1'b0;
                end
            endcase

            // Vloženie dát do pipeline pri čítaní
            if (read_pipe_valid[0]) begin
                read_pipe_data[0] <= mem[read_bank][row_addr[read_bank]][read_col];
                read_col <= read_col + 1;
            end
        end
    end
endmodule

