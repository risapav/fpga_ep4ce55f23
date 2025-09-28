// sdram_controller.sv - Verzia 5.4 - Finálna oprava multiple drivers
//
// Popis:
// Finálna, robustná verzia nízkoúrovňového SDRAM radiča.
//
// Kľúčové zmeny v tejto verzii:
// 1. FINÁLNA OPRAVA (Multiple Drivers): Všetky registre riadené z FSM
//    (časovače, počítadlá, flagy) sú teraz riadené výlučne zo sekvenčného
//    bloku `always_ff` pomocou `_next` a `load_*` signálov z kombinačného bloku.
//
// Author: refactor by assistant & user feedback

`include "sdram_pkg.sv"
(* default_nettype = "none" *)

module SdramController #(
    parameter CLOCK_FREQ_HZ  = 100_000_000,
    parameter ADDR_WIDTH     = 24,
    parameter DATA_WIDTH     = 16,
    parameter BURST_LEN      = 8,
    parameter int NUM_BANKS    = 4,
    parameter int tRP          = 3,
    parameter int tRCD         = 3,
    parameter int tWR          = 2,
    parameter int tRFC         = 9,
    parameter int tRAS         = 7,
    parameter int CAS_LATENCY  = 3
)(
    input  logic                   clk,
    input  logic                   rstn,
    input  logic                   cmd_fifo_valid,
    output logic                   cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t  cmd_fifo_data,
    output logic                   resp_valid,
    output logic                   resp_last,
    output logic [DATA_WIDTH-1:0]  resp_data,
    input  logic                   resp_ready,
    input  logic                   wdata_valid,
    input  logic [DATA_WIDTH-1:0]  wdata,
    input  logic [1:0]             wdata_dqm_i,
    output logic                   wdata_ready,
    output logic [12:0]            sdram_addr,
    output logic [1:0]             sdram_ba,
    output logic                   sdram_cs_n,
    output logic                   sdram_ras_n,
    output logic                   sdram_cas_n,
    output logic                   sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0]  sdram_dq,
    output logic [1:0]             sdram_dqm,
    output logic                   sdram_cke
);

    import sdram_pkg::*;

    localparam int INIT_WAIT_CYCLES = (200 * 1000) / (1_000_000_000 / CLOCK_FREQ_HZ);
    localparam int REFRESH_INTERVAL = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam int C_COLS = 9;
    localparam int MAX_CAS_LATENCY = 8;

    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS,
        IDLE, ACTIVE_CMD, ACTIVE_WAIT, PREFETCH_WDATA, RW_CMD,
        READ_BURST, WRITE_BURST,
        PRECHARGE_CMD, REFRESH_CMD
    } state_t;

    // --- Registre (riadené VÝLUČNE z `always_ff`) ---
    state_t state_reg;
    sdram_cmd_t current_cmd;
    logic [$clog2(INIT_WAIT_CYCLES+1)-1:0]   init_timer;
    logic [$clog2(tRCD+1)-1:0]               trcd_timer;
    logic [$clog2(tRP+1)-1:0]                trp_timer;
    logic [$clog2(tWR+1)-1:0]                twr_timer;
    logic [$clog2(tRFC+1)-1:0]               trfc_timer;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0]   refresh_counter;
    logic [$clog2(BURST_LEN):0]              burst_cnt;
    logic [C_COLS-1:0]                       col_addr_reg;
    logic [MAX_CAS_LATENCY-1:0]              read_pipe_valid;
    logic [DATA_WIDTH-1:0]                   read_pipe_data [0:MAX_CAS_LATENCY-1];
    logic                                    auto_precharge_pending;
    logic [1:0]                              auto_precharge_bank;

    // --- Kombinačné signály (riadené z `always_comb`) ---
    state_t state_next;
    logic load_trcd, load_trp, load_twr, load_trfc, load_burst_cnt, load_col_addr;
    logic decrement_burst, inc_col_addr;
    logic [$clog2(tRCD+1)-1:0]               next_trcd;
    logic [$clog2(tRP+1)-1:0]                next_trp;
    logic [$clog2(tWR+1)-1:0]                next_twr;
    logic [$clog2(tRFC+1)-1:0]               next_trfc;
    logic [$clog2(BURST_LEN):0]              next_burst_cnt;
    logic auto_precharge_pending_next;
    logic [1:0]                              auto_precharge_bank_next;
    logic dq_write_enable;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state_reg           <= INIT_WAIT;
            init_timer      <= INIT_WAIT_CYCLES;
            trcd_timer      <= 0; trp_timer <= 0; twr_timer <= 0; trfc_timer <= 0;
            burst_cnt       <= 0; current_cmd <= '0; refresh_counter <= 0; col_addr_reg <= '0;
            read_pipe_valid <= '0; auto_precharge_pending <= 1'b0; auto_precharge_bank <= '0;
        end else begin
            state_reg <= state_next;

            if (init_timer > 0) init_timer <= init_timer - logic'(1);
            if(load_trcd)            trcd_timer <= next_trcd; else if (trcd_timer > 0) trcd_timer <= trcd_timer - logic'(1);
            if(load_trp)             trp_timer  <= next_trp;  else if (trp_timer > 0)  trp_timer  <= trp_timer - logic'(1);
            if(load_twr)             twr_timer  <= next_twr;  else if (twr_timer > 0)  twr_timer  <= twr_timer - logic'(1);
            if(load_trfc)            trfc_timer <= next_trfc; else if (trfc_timer > 0) trfc_timer <= trfc_timer - logic'(1);

            if(load_burst_cnt)       burst_cnt <= next_burst_cnt;
            else if (decrement_burst)burst_cnt <= burst_cnt - logic'(1);

            if (load_col_addr)       col_addr_reg <= current_cmd.addr[8:0];
            else if (inc_col_addr)   col_addr_reg <= col_addr_reg + logic'(1);

            if (refresh_counter >= REFRESH_INTERVAL) refresh_counter <= 0;
            else refresh_counter <= refresh_counter + logic'(1);

            if (cmd_fifo_ready && cmd_fifo_valid) current_cmd <= cmd_fifo_data;

            auto_precharge_pending <= auto_precharge_pending_next;
            auto_precharge_bank    <= auto_precharge_bank_next;

            read_pipe_valid <= {read_pipe_valid[MAX_CAS_LATENCY-2:0], 1'b0};
            for (integer i = MAX_CAS_LATENCY-1; i > 0; i = i - 1) read_pipe_data[i] <= read_pipe_data[i-1];
            if ((state_reg == READ_BURST) && (trcd_timer == 0)) begin
                read_pipe_valid[0] <= 1'b1;
                read_pipe_data[0]  <= sdram_dq;
            end else begin
                read_pipe_valid[0] <= 1'b0;
            end
        end
    end

    always_comb begin
        state_next = state_reg;
        cmd_fifo_ready = 1'b0; wdata_ready = 1'b0;
        dq_write_enable = 1'b0; decrement_burst = 1'b0;
        load_trcd = 1'b0; next_trcd = '0; load_trp = 1'b0; next_trp = '0;
        load_twr  = 1'b0; next_twr  = '0; load_trfc = 1'b0; next_trfc = '0;
        load_burst_cnt = 1'b0; next_burst_cnt = '0;
        load_col_addr = 1'b0; inc_col_addr = 1'b0;

        auto_precharge_pending_next = auto_precharge_pending;
        auto_precharge_bank_next    = auto_precharge_bank;

        resp_valid = read_pipe_valid[CAS_LATENCY-1];
        resp_last  = resp_valid && (burst_cnt == (BURST_LEN - CAS_LATENCY));
        resp_data  = read_pipe_data[CAS_LATENCY-1];

        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1; sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_addr = '0; sdram_ba = '0; sdram_dqm = 2'b00; sdram_cke = 1'b1;

        case (state_reg)
            INIT_WAIT: if (init_timer == 0) state_next = INIT_PRECHARGE; else sdram_cke = 1'b0;
            INIT_PRECHARGE: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_addr[10] = 1'b1;
                load_trp = 1'b1; next_trp = tRP;
                state_next = INIT_REFRESH1;
            end
            INIT_REFRESH1: if (trp_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                load_trfc = 1'b1; next_trfc = tRFC;
                state_next = INIT_REFRESH2;
            end
            INIT_REFRESH2: if (trfc_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                state_next = INIT_MRS;
            end
            INIT_MRS: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0; sdram_we_n = 1'b0;
                sdram_ba = '0; sdram_addr = 13'b000_00_011_0_011;
                state_next = IDLE;
            end

            IDLE: begin
                if (trp_timer > 0 || twr_timer > 0 || trfc_timer > 0) state_next = IDLE;
                else if (auto_precharge_pending) state_next = PRECHARGE_CMD;
                else if (refresh_counter >= REFRESH_INTERVAL) state_next = REFRESH_CMD;
                else begin
                    cmd_fifo_ready = 1'b1;
                    if (cmd_fifo_valid) state_next = ACTIVE_CMD;
                end
            end

            ACTIVE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0;
                sdram_ba   = current_cmd.addr[23:22]; sdram_addr = current_cmd.addr[21:9];
                load_trcd = 1'b1; next_trcd = tRCD;
                state_next = ACTIVE_WAIT;
            end

            ACTIVE_WAIT: if (trcd_timer == 0) state_next = (current_cmd.rw == WRITE_CMD) ? PREFETCH_WDATA : RW_CMD;

            PREFETCH_WDATA: if (wdata_valid) state_next = RW_CMD; else wdata_ready = 1'b1;

            RW_CMD: begin
                sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; sdram_we_n = (current_cmd.rw == WRITE_CMD);
                sdram_ba   = current_cmd.addr[23:22];
                sdram_addr = {current_cmd.auto_precharge_en, 1'b0, 2'b00, current_cmd.addr[8:0]};
                load_col_addr = 1'b1;
                load_burst_cnt = 1'b1; next_burst_cnt = logic'((BURST_LEN-1));
                if (current_cmd.rw == WRITE_CMD) begin
                    dq_write_enable = 1'b1;
                    sdram_dqm       = wdata_dqm_i;
                    decrement_burst = 1'b1;
                    state_next      = WRITE_BURST;
                end else begin
                    state_next = READ_BURST;
                end
            end

            READ_BURST: begin
                decrement_burst = resp_ready;
                if (burst_cnt == 0 && resp_ready) begin
                    if (current_cmd.auto_precharge_en) begin
                        auto_precharge_pending_next = 1'b1;
                        auto_precharge_bank_next    = current_cmd.addr[23:22];
                    end
                    state_next = IDLE;
                end
            end

            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                wdata_ready     = 1'b1;
                sdram_dqm       = wdata_dqm_i;
                decrement_burst = wdata_valid;
                if (burst_cnt == 0 && wdata_valid) begin
                    load_twr = 1'b1; next_twr = tWR;
                    if (current_cmd.auto_precharge_en) begin
                        auto_precharge_pending_next = 1'b1;
                        auto_precharge_bank_next    = current_cmd.addr[23:22];
                    end
                    state_next = IDLE;
                end
            end

            PRECHARGE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0;
                if (auto_precharge_pending) begin
                    sdram_ba = auto_precharge_bank;
                    auto_precharge_pending_next = 1'b0;
                end else begin
                    sdram_ba = current_cmd.addr[23:22];
                end
                sdram_addr[10] = 1'b0;
                load_trp = 1'b1; next_trp = tRP;
                state_next = IDLE;
            end

            REFRESH_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                load_trfc = 1'b1; next_trfc = tRFC;
                state_next = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end

    assign sdram_dq = (dq_write_enable) ? wdata : {DATA_WIDTH{1'bz}};

endmodule

`default_nettype wire
