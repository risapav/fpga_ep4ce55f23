/**
 * @file        sdram_cmd_checker.sv
 * @brief       SDRAM Command Validator (Gatekeeper).
 * @details     Validuje príkazy pred vstupom do radiča.
 * - Bráni nelegálnym operáciám (Row Conflict, Bank Busy).
 * - Udržiava "tieňový stav" (Shadow State) bánk pre predikciu konfliktov.
 * - Rieši deadlocky tým, že chybné príkazy zahodí (akceptuje handshake, ale nepošle ďalej).
 *
 * @param C_NUM_BANKS  Počet bánk (automaticky).
 * @param T_*_CYCLES   Časovanie pre kontrolu busy stavov.
 */

`default_nettype none

`ifndef SDRAM_CMD_CHECKER_SV
`define SDRAM_CMD_CHECKER_SV

import sdram_pkg::*;

module sdram_cmd_checker #(
    parameter int C_NUM_BANKS  = 1 << sdram_pkg::BANK_ADDR_WIDTH,
    // Timing Parameters propagated from Top
    parameter int T_RAS_CYCLES = sdram_pkg::T_RAS_CYCLES,
    parameter int T_RP_CYCLES  = sdram_pkg::T_RP_CYCLES,
    parameter int T_WR_CYCLES  = sdram_pkg::T_WR_CYCLES
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  logic                     clear_errors_i,

    // Input (From Master/Arbiter)
    input  sdram_cmd_t               wr_cmd_i,
    input  logic                     wr_cmd_valid_i,
    output logic                     wr_cmd_ready_o,

    input  sdram_cmd_t               rd_cmd_i,
    input  logic                     rd_cmd_valid_i,
    output logic                     rd_cmd_ready_o,

    // Output (To Controller)
    output sdram_cmd_t               wr_cmd_o,
    output logic                     wr_cmd_valid_o,
    input  logic                     wr_cmd_ready_i,

    output sdram_cmd_t               rd_cmd_o,
    output logic                     rd_cmd_valid_o,
    input  logic                     rd_cmd_ready_i,

    // Diagnostics
    output logic                     cmd_error_o,
    output logic [15:0]              error_code_o
);

    // -------------------------------------------------------------------------
    // 1. Interné Typy a Signály
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] { BANK_IDLE, BANK_ACTIVE, BANK_PRECHARGING } bank_state_t;

    localparam logic [15:0] ERR_NONE         = 16'h0000;
    localparam logic [15:0] ERR_ROW_CONFLICT = 16'h0001;
    localparam logic [15:0] ERR_BANK_BUSY    = 16'h0002;

    // Shadow State
    bank_state_t bank_state [C_NUM_BANKS];
    logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] active_row [C_NUM_BANKS];

    // Timers
    logic [$clog2(T_RAS_CYCLES+1)-1:0] tras_timer [C_NUM_BANKS];
    logic [$clog2(T_WR_CYCLES+1)-1:0]  twr_timer  [C_NUM_BANKS];
    logic [$clog2(T_RP_CYCLES+1)-1:0]  trp_timer  [C_NUM_BANKS];
    
    logic load_tras [C_NUM_BANKS];
    logic load_twr  [C_NUM_BANKS];
    logic load_trp  [C_NUM_BANKS];

    // Error Registers
    logic [15:0] error_code_reg;
    logic        cmd_error_reg;
    
    logic        cmd_error_next;
    logic [15:0] error_code_next;

    // -------------------------------------------------------------------------
    // 2. Bank Timers (Shadow Timing)
    // -------------------------------------------------------------------------
    generate
        for (genvar i = 0; i < C_NUM_BANKS; i++) begin : g_bank_timers
            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    tras_timer[i] <= '0; 
                    twr_timer[i]  <= '0; 
                    trp_timer[i]  <= '0;
                end else begin
                    // Decrement logic
                    if (tras_timer[i] > 0) tras_timer[i] <= tras_timer[i] - 1'b1;
                    if (twr_timer[i] > 0)  twr_timer[i]  <= twr_timer[i]  - 1'b1;
                    if (trp_timer[i] > 0)  trp_timer[i]  <= trp_timer[i]  - 1'b1;

                    // Load logic (Priority over decrement)
                    if (load_tras[i]) tras_timer[i] <= T_RAS_CYCLES;
                    if (load_twr[i])  twr_timer[i]  <= T_WR_CYCLES;
                    if (load_trp[i])  trp_timer[i]  <= T_RP_CYCLES;
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 3. Shadow State Machine
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < C_NUM_BANKS; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
            end
            cmd_error_reg  <= 0;
            error_code_reg <= ERR_NONE;
        end else begin
            if (clear_errors_i) begin
                cmd_error_reg  <= 0;
                error_code_reg <= ERR_NONE;
            end else begin
                cmd_error_reg <= cmd_error_next;
                // Zachytíme prvú chybu
                if (cmd_error_next && !cmd_error_reg) 
                    error_code_reg <= error_code_next;
            end

            // Auto-transition z Precharge do Idle po vypršaní časovačov
            for (int i = 0; i < C_NUM_BANKS; i++) begin
                if (bank_state[i] == BANK_PRECHARGING) begin
                     if (trp_timer[i] == 0 && twr_timer[i] == 0) 
                        bank_state[i] <= BANK_IDLE;
                end
            end

            // Update State on Valid & Accepted Commands (Write)
            if (wr_cmd_valid_i && wr_cmd_ready_i && !cmd_error_next) begin
                automatic int b = wr_cmd_i.addr.bank;
                if (bank_state[b] == BANK_IDLE) begin
                    bank_state[b] <= BANK_ACTIVE;
                    active_row[b] <= wr_cmd_i.addr.row;
                end
                if (wr_cmd_i.auto_precharge) 
                    bank_state[b] <= BANK_PRECHARGING;
            end

            // Update State on Valid & Accepted Commands (Read)
            if (rd_cmd_valid_i && rd_cmd_ready_i && !cmd_error_next) begin
                automatic int b = rd_cmd_i.addr.bank;
                if (bank_state[b] == BANK_IDLE) begin
                    bank_state[b] <= BANK_ACTIVE;
                    active_row[b] <= rd_cmd_i.addr.row;
                end
                if (rd_cmd_i.auto_precharge) 
                    bank_state[b] <= BANK_PRECHARGING;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. Check & Gatekeeper Logic (Combinatorial)
    // -------------------------------------------------------------------------
    always_comb begin
        cmd_error_next  = 0;
        error_code_next = ERR_NONE;
        
        for (int i=0; i<C_NUM_BANKS; i++) begin 
            load_tras[i]=0; load_twr[i]=0; load_trp[i]=0; 
        end

        // --- Check Write Command ---
        if (wr_cmd_valid_i) begin
            automatic int b = wr_cmd_i.addr.bank;
            
            // 1. Bank is Busy (Precharging)
            if (bank_state[b] == BANK_PRECHARGING) begin
                cmd_error_next = 1; 
                error_code_next = ERR_BANK_BUSY;
            end 
            // 2. Row Conflict (Active but different row)
            else if (bank_state[b] == BANK_ACTIVE && active_row[b] != wr_cmd_i.addr.row) begin
                cmd_error_next = 1; 
                error_code_next = ERR_ROW_CONFLICT;
            end
            
            // If valid, predict timer loads
            if (!cmd_error_next && wr_cmd_ready_i) begin
                if (bank_state[b] == BANK_IDLE) load_tras[b] = 1;
                if (wr_cmd_i.auto_precharge) begin 
                    load_twr[b] = 1; 
                    load_trp[b] = 1; 
                end
            end
        end

        // --- Check Read Command ---
        if (rd_cmd_valid_i) begin
            automatic int b = rd_cmd_i.addr.bank;
            
            if (bank_state[b] == BANK_PRECHARGING) begin
                cmd_error_next = 1; 
                error_code_next = ERR_BANK_BUSY;
            end 
            else if (bank_state[b] == BANK_ACTIVE && active_row[b] != rd_cmd_i.addr.row) begin
                cmd_error_next = 1; 
                error_code_next = ERR_ROW_CONFLICT;
            end
            
            if (!cmd_error_next && rd_cmd_ready_i) begin
                if (bank_state[b] == BANK_IDLE) load_tras[b] = 1;
                if (rd_cmd_i.auto_precharge) load_trp[b] = 1;
            end
        end
        
        if (clear_errors_i) begin 
            cmd_error_next = 0; 
            error_code_next = ERR_NONE; 
        end
    end

    // -------------------------------------------------------------------------
    // 5. Output Forwarding & Deadlock Fix
    // -------------------------------------------------------------------------
    // Ak nastane chyba, nepošleme príkaz ďalej (valid_o = 0),
    // ale povieme mastrowi, že sme pripravení (ready_o = 1),
    // čím príkaz "skonzumujeme" a zahodíme, aby nezasekol zbernicu.

    assign wr_cmd_valid_o = wr_cmd_valid_i && !cmd_error_next;
    assign rd_cmd_valid_o = rd_cmd_valid_i && !cmd_error_next;
    
    assign wr_cmd_ready_o = wr_cmd_ready_i || cmd_error_next;
    assign rd_cmd_ready_o = rd_cmd_ready_i || cmd_error_next;

    assign wr_cmd_o = wr_cmd_i;
    assign rd_cmd_o = rd_cmd_i;
    
    assign cmd_error_o  = cmd_error_reg;
    assign error_code_o = error_code_reg;

endmodule

`endif // SDRAM_CMD_CHECKER_SV

`default_nettype wire
