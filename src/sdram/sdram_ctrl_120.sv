// sdram_controller_variantB.sv
// Verzia: Variant B (refactor: combine v7.11 robustness + v11.0 modularity)
// - package s definíciami
// - CountdownTimer modul
// - SdramControllerFinal modul (kompletný)

`ifndef SDRAM_CTRL_VARIANTB_SV
`define SDRAM_CTRL_VARIANTB_SV

(* default_nettype = "none" *)

// ============================================================================
// Package: sdram_pkg - typy a default parametre (upravi podľa tvojej pamäte)
// ============================================================================
package sdram_pkg;
    parameter int DATA_WIDTH = 16;
    parameter int ROW_ADDR_WIDTH = 13;
    parameter int COL_ADDR_WIDTH = 9;
    parameter int BANK_ADDR_WIDTH = 2;
    parameter int BURST_LEN = 8;
    parameter int CAS_LATENCY = 3;

    // adresný struct (čitateľné, bezpečné)
    typedef struct packed {
        logic [ROW_ADDR_WIDTH-1:0] row;
        logic [COL_ADDR_WIDTH-1:0] col;
        logic [BANK_ADDR_WIDTH-1:0] bank;
    } sdram_addr_t;

    // príkaz (addr ako struct)
    typedef struct packed {
        sdram_addr_t addr;
        logic rw; // 1 = write, 0 = read
        logic auto_precharge;
    } sdram_cmd_t;
endpackage : sdram_pkg

import sdram_pkg::*;

// ============================================================================
// CountdownTimer - jednoduchý reusable timer
// ============================================================================
module CountdownTimer #(
    parameter int COUNT_WIDTH = 6 // adjust as needed
)(
    input  logic clk,
    input  logic rstn,
    input  logic load,
    input  logic [COUNT_WIDTH-1:0] load_val,
    output logic done
);
    logic [COUNT_WIDTH-1:0] count_reg, count_next;

    always_ff @(posedge clk) begin
        if (!rstn) count_reg <= '0;
        else count_reg <= count_next;
    end

    always_comb begin
        if (load) count_next = load_val;
        else if (count_reg > 0) count_next = count_reg - 1;
        else count_next = count_reg;
        done = (count_reg == 0);
    end
endmodule : CountdownTimer

// ============================================================================
// SdramControllerFinal - Variant B
// ============================================================================
module SdramControllerFinal #(
    parameter int CLOCK_FREQ_HZ      = 100_000_000,
    parameter int DATA_WIDTH         = sdram_pkg::DATA_WIDTH,
    parameter int FIFO_DEPTH_BITS    = 4,
    parameter bit ENABLE_DEBUG       = 1'b1,
    parameter int ROW_ADDR_WIDTH     = sdram_pkg::ROW_ADDR_WIDTH,
    parameter int COL_ADDR_WIDTH     = sdram_pkg::COL_ADDR_WIDTH,
    parameter int BANK_ADDR_WIDTH    = sdram_pkg::BANK_ADDR_WIDTH,
    parameter int BURST_LEN          = sdram_pkg::BURST_LEN,
    parameter int CAS_LATENCY        = sdram_pkg::CAS_LATENCY,
    parameter int tRP                = 3,
    parameter int tRCD               = 3,
    parameter int tWR                = 2,
    parameter int tRFC               = 9,
    parameter int tRAS               = 7
)(
    input  logic                     clk,
    input  logic                     clk_sh,
    input  logic                     rstn,

    // Command FIFO (single-beat command)
    input  logic                     cmd_fifo_valid,
    output logic                     cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t    cmd_fifo_data,

    // Read response
    output logic                     resp_valid,
    output logic                     resp_last,
    output logic [DATA_WIDTH-1:0]    resp_data,
    input  logic                     resp_ready,

    // Write data
    input  logic                     wdata_valid,
    output logic                     wdata_ready,
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  wdata_dqm_i,

    // SDRAM pins
    output logic [ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic                     sdram_cs_n,
    output logic                     sdram_ras_n,
    output logic                     sdram_cas_n,
    output logic                     sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0]    sdram_dq,
    output logic [DATA_WIDTH/8-1:0]  sdram_dqm,
    output logic                     sdram_cke,
    output logic                     sdram_clk,

    // Debug
    output logic [4:0]               debug_state_o,
    output logic [$clog2((1<<4)+1)-1:0] debug_rd_fifo_level_o,
    output logic [$clog2((1<<4)+1)-1:0] debug_wr_fifo_level_o,
    output logic [$clog2(16)-1:0] debug_cmd_fifo_level_o
);

    // localparams
    localparam int FIFO_DEPTH = 1 << FIFO_DEPTH_BITS;
    localparam int NUM_BANKS = 1 << BANK_ADDR_WIDTH;
    localparam int NS_PER_SEC = 1_000_000_000;
    localparam int CLK_PERIOD_NS = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam int WAIT_TIME_NS = 200_000;
    localparam int INIT_WAIT_CYCLES = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam int REFRESH_INTERVAL = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam int AP_BIT_INDEX = 10;

    // FSM states
    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS,
        IDLE,
        EVAL_BANK, EVAL_PRECHARGE, EVAL_TIMING,
        ACTIVATE_CMD, READ_CMD, WRITE_CMD,
        PRECHARGE_CMD, REFRESH_CMD, READ_BURST, WRITE_BURST
    } state_t;

    // helper enum for SDRAM command type
    typedef enum logic [2:0] { CMD_NOP=0, CMD_ACTIVE, CMD_READ, CMD_WRITE, CMD_PRECHARGE, CMD_REFRESH, CMD_MRS } cmd_type_e;

    // struct for pins
    typedef struct packed { logic cs, ras, cas, we; } sdram_cmd_pins_t;

    // function to generate command pins (centralized)
    function automatic sdram_cmd_pins_t get_sdram_cmd(cmd_type_e t);
        case (t)
            CMD_ACTIVE:  return '{cs:0, ras:0, cas:1, we:1};
            CMD_READ:    return '{cs:0, ras:1, cas:0, we:1};
            CMD_WRITE:   return '{cs:0, ras:1, cas:0, we:0};
            CMD_PRECHARGE:return '{cs:0, ras:0, cas:1, we:0};
            CMD_REFRESH: return '{cs:0, ras:0, cas:0, we:1};
            CMD_MRS:     return '{cs:0, ras:0, cas:0, we:0};
            default:     return '{cs:1, ras:1, cas:1, we:1};
        endcase
    endfunction

    // registers & signals
    state_t state_reg, state_next;
    typedef enum logic { B_IDLE, B_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS-1:0], bank_state_next[NUM_BANKS-1:0];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS-1:0], active_row_next[NUM_BANKS-1:0];
    logic [$clog2(tRAS+1)-1:0] tras_timer[NUM_BANKS-1:0], tras_timer_next[NUM_BANKS-1:0];

    // timers control signals and done flags
    logic load_trp, load_trcd, load_twr, load_trfc, load_init;
    logic trp_done, trcd_done, twr_done, trfc_done, init_done;

    // refresh counters
    logic [$clog2(REFRESH_INTERVAL+1)-1:0] refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;

    // burst/cas counters
    logic [$clog2(BURST_LEN):0] burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0] cas_cnt, cas_cnt_next;

    // current command register
    sdram_pkg::sdram_cmd_t current_cmd, current_cmd_next;

    // dq control pipelines
    logic dq_write_enable, dq_write_enable_d;

    // FIFO storage + pointers + counts
    logic [DATA_WIDTH-1:0] read_fifo_data[FIFO_DEPTH];
    logic                   read_fifo_last[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_r_wptr, fifo_r_wptr_next;
    logic [FIFO_DEPTH_BITS-1:0] fifo_r_rptr, fifo_r_rptr_next;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_r_count, fifo_r_count_next;

    logic [DATA_WIDTH-1:0] write_fifo_data[FIFO_DEPTH];
    logic [DATA_WIDTH/8-1:0] write_fifo_dqm[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_w_wptr, fifo_w_wptr_next;
    logic [FIFO_DEPTH_BITS-1:0] fifo_w_rptr, fifo_w_rptr_next;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_w_count, fifo_w_count_next;

    // pipeline regs for DQ & DQM (loaded when do_write_fifo_read)
    logic [DATA_WIDTH-1:0] write_data_reg;
    logic [DATA_WIDTH/8-1:0] write_dqm_reg;
    logic do_write_fifo_read;

    // instantiate timers (width large enough)
    CountdownTimer #(.COUNT_WIDTH($clog2(tRP+1)))  trp_timer_inst  (.clk(clk), .rstn(rstn), .load(load_trp),  .load_val(tRP), .done(trp_done));
    CountdownTimer #(.COUNT_WIDTH($clog2(tRCD+1))) trcd_timer_inst (.clk(clk), .rstn(rstn), .load(load_trcd), .load_val(tRCD),.done(trcd_done));
    CountdownTimer #(.COUNT_WIDTH($clog2(tWR+1)))  twr_timer_inst  (.clk(clk), .rstn(rstn), .load(load_twr),  .load_val(tWR), .done(twr_done));
    CountdownTimer #(.COUNT_WIDTH($clog2(tRFC+1))) trfc_timer_inst (.clk(clk), .rstn(rstn), .load(load_trfc), .load_val(tRFC),.done(trfc_done));
    CountdownTimer #(.COUNT_WIDTH($clog2(INIT_WAIT_CYCLES+1))) init_timer_inst (.clk(clk), .rstn(rstn), .load(load_init), .load_val(INIT_WAIT_CYCLES), .done(init_done));

    // --------------------------
    // sequential: registers update
    // --------------------------
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            cas_cnt <= '0;
            burst_cnt <= '0;
            current_cmd <= '{addr:'0, rw:1'b0, auto_precharge:1'b0};
            fifo_r_wptr <= '0; fifo_r_rptr <= '0; fifo_r_count <= '0;
            fifo_w_wptr <= '0; fifo_w_rptr <= '0; fifo_w_count <= '0;
            dq_write_enable_d <= 1'b0;
            write_data_reg <= '0;
            write_dqm_reg <= '0;
            for (int i=0; i<NUM_BANKS; i++) begin
                bank_state[i] <= B_IDLE;
                active_row[i] <= '0;
                tras_timer[i] <= '0;
            end
        end else begin
            state_reg <= state_next;
            burst_cnt <= burst_cnt_next;
            cas_cnt <= cas_cnt_next;
            current_cmd <= current_cmd_next;
            fifo_r_wptr <= fifo_r_wptr_next;
            fifo_r_rptr <= fifo_r_rptr_next;
            fifo_r_count <= fifo_r_count_next;
            fifo_w_wptr <= fifo_w_wptr_next;
            fifo_w_rptr <= fifo_w_rptr_next;
            fifo_w_count <= fifo_w_count_next;
            refresh_counter <= refresh_counter_next;
            refresh_pending <= refresh_pending_next;
            for (int i=0; i<NUM_BANKS; i++) begin
                bank_state[i] <= bank_state_next[i];
                active_row[i] <= active_row_next[i];
                tras_timer[i] <= tras_timer_next[i];
            end

            // pipeline DQ enable: align with SDRAM output phase (one cycle)
            dq_write_enable_d <= dq_write_enable;

            // pipeline loading of write data occurs only ONCE when controller requests it
            if (do_write_fifo_read) begin
                write_data_reg <= write_fifo_data[fifo_w_rptr];
                write_dqm_reg  <= write_fifo_dqm[fifo_w_rptr];
            end else if (state_reg == WRITE_BURST) begin
                // if no data available (we tried to write and FIFO empty), mask DQM
                write_dqm_reg <= {(DATA_WIDTH/8){1'b1}};
            end
        end
    end

    // --------------------------
    // combinational: next-state
    // --------------------------
    always_comb begin
        // default next signals
        state_next = state_reg;
        burst_cnt_next = burst_cnt;
        cas_cnt_next = cas_cnt;
        current_cmd_next = current_cmd;
        fifo_r_wptr_next = fifo_r_wptr;
        fifo_r_rptr_next = fifo_r_rptr;
        fifo_r_count_next = fifo_r_count;
        fifo_w_wptr_next = fifo_w_wptr;
        fifo_w_rptr_next = fifo_w_rptr;
        fifo_w_count_next = fifo_w_count;
        refresh_counter_next = refresh_counter;
        refresh_pending_next = refresh_pending;
        for (int i=0; i<NUM_BANKS; i++) begin
            bank_state_next[i] = bank_state[i];
            active_row_next[i] = active_row[i];
            tras_timer_next[i] = tras_timer[i];
        end

        // default SDRAM pins = NOP
        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1; sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_addr = '0; sdram_ba = '0;
        sdram_cke = 1'b1;
        dq_write_enable = 1'b0;
        cmd_fifo_ready = 1'b0;

        // default timer loads
        load_trp = 1'b0; load_trcd = 1'b0; load_twr = 1'b0; load_trfc = 1'b0; load_init = 1'b0;

        // decrement local tras timers
        for (int i=0; i<NUM_BANKS; i++)
            if (tras_timer[i] > 0) tras_timer_next[i] = tras_timer[i] - 1;

        // refresh counter handling (when not issuing refresh command)
        if (state_reg != REFRESH_CMD) begin
            if (refresh_counter == 0) refresh_pending_next = 1'b1;
            else refresh_counter_next = refresh_counter - 1;
        end

        // cas pipeline decrement
        if (cas_cnt > 0) cas_cnt_next = cas_cnt - 1;

        // FIFO status
        logic fifo_r_full = (fifo_r_count == FIFO_DEPTH);
        logic fifo_r_empty = (fifo_r_count == 0);
        logic fifo_w_full = (fifo_w_count == FIFO_DEPTH);
        logic fifo_w_empty = (fifo_w_count == 0);

        // handshake signals for FIFOs
        logic fifo_w_wr_en = wdata_valid && !fifo_w_full;
        logic fifo_w_rd_en = (state_reg == WRITE_BURST) && !fifo_w_empty;

        logic fifo_r_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1);
        logic fifo_r_rd_en = !fifo_r_empty && resp_ready;

        // map to do_ signals
        logic do_write_fifo_write = fifo_w_wr_en;
        do_write_fifo_read = fifo_w_rd_en;

        logic do_read_fifo_write = fifo_r_wr_en && !fifo_r_full;
        logic do_read_fifo_read  = fifo_r_rd_en;

        // decode addr struct convenience
        sdram_pkg::sdram_addr_t cmd_addr = current_cmd.addr;

        // Main FSM (clean, split states; use timer 'done' via load_x / timer instances)
        case (state_reg)
            INIT_WAIT: begin
                load_init = 1'b1;
                if (init_done) state_next = INIT_PRECHARGE;
            end
            INIT_PRECHARGE: begin
                // issue PRECHARGE all banks (AP bit set)
                sdram_cmd_pins_t pins = get_sdram_cmd(CMD_PRECHARGE);
                sdram_cs_n = pins.cs; sdram_ras_n = pins.ras; sdram_we_n = pins.we; sdram_cas_n = pins.cas;
                sdram_addr[AP_BIT_INDEX] = 1'b1;
                load_trp = 1'b1;
                state_next = INIT_REFRESH1;
            end
            INIT_REFRESH1: begin
                if (trp_done) begin
                    sdram_cmd_pins_t pins = get_sdram_cmd(CMD_REFRESH);
                    sdram_cs_n = pins.cs; sdram_ras_n = pins.ras; sdram_cas_n = pins.cas;
                    load_trfc = 1'b1;
                    state_next = INIT_REFRESH2;
                end
            end
            INIT_REFRESH2: begin
                if (trfc_done) begin
                    sdram_cmd_pins_t pins = get_sdram_cmd(CMD_REFRESH);
                    sdram_cs_n = pins.cs; sdram_ras_n = pins.ras; sdram_cas_n = pins.cas;
                    load_trfc = 1'b1;
                    state_next = INIT_MRS;
                end
            end
            INIT_MRS: begin
                if (trfc_done) begin
                    sdram_cmd_pins_t pins = get_sdram_cmd(CMD_MRS);
                    sdram_cs_n = pins.cs; sdram_ras_n = pins.ras; sdram_cas_n = pins.cas; sdram_we_n = pins.we;
                    // Write MRS value to sdram_addr (simplified placeholder)
                    sdram_addr = '0;
                    state_next = IDLE;
                end
            end
            IDLE: begin
                if (refresh_pending && twr_done) begin
                    state_next = REFRESH_CMD;
                end else if (cmd_fifo_valid && !fifo_r_full) begin
                    cmd_fifo_ready = 1'b1;
                    current_cmd_next = cmd_fifo_data;
                    state_next = EVAL_BANK;
                end
            end
            EVAL_BANK: begin
                if (bank_state[cmd_addr.bank] == B_IDLE) begin
                    if (trp_done) state_next = ACTIVATE_CMD;
                end else begin
                    if (active_row[cmd_addr.bank] == cmd_addr.row) state_next = EVAL_TIMING;
                    else state_next = EVAL_PRECHARGE;
                end
            end
            EVAL_PRECHARGE: begin
                if (tras_timer[cmd_addr.bank] == 0) state_next = PRECHARGE_CMD;
            end
            EVAL_TIMING: begin
                if (trcd_done) begin
                    if (current_cmd.rw == 1'b0) state_next = READ_CMD; else state_next = WRITE_CMD;
                end
            end
            ACTIVATE_CMD: begin
                sdram_cmd_pins_t pins = get_sdram_cmd(CMD_ACTIVE);
                sdram_cs_n = pins.cs; sdram_ras_n = pins.ras;
                sdram_ba = cmd_addr.bank;
                sdram_addr = cmd_addr.row;
                load_trcd = 1'b1;
                tras_timer_next[cmd_addr.bank] = tRAS;
                bank_state_next[cmd_addr.bank] = B_ACTIVE;
                active_row_next[cmd_addr.bank] = cmd_addr.row;
                state_next = EVAL_BANK;
            end
            READ_CMD: begin
                sdram_cmd_pins_t pins = get_sdram_cmd(CMD_READ);
                sdram_cs_n = pins.cs; sdram_cas_n = pins.cas;
                sdram_ba = cmd_addr.bank;
                sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge;
                cas_cnt_next = CAS_LATENCY;
                burst_cnt_next = BURST_LEN;
                if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = B_IDLE;
                state_next = READ_BURST;
            end
            WRITE_CMD: begin
                sdram_cmd_pins_t pins = get_sdram_cmd(CMD_WRITE);
                sdram_cs_n = pins.cs; sdram_cas_n = pins.cas; sdram_we_n = pins.we;
                sdram_ba = cmd_addr.bank;
                sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge;
                burst_cnt_next = BURST_LEN;
                if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = B_IDLE;
                state_next = WRITE_BURST;
            end
            READ_BURST: begin
                // on CAS-latency cycles, do_read_fifo_write will be asserted
                if (do_read_fifo_write) burst_cnt_next = burst_cnt - 1;
                if ((burst_cnt == 1) && do_read_fifo_write) state_next = IDLE;
            end
            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                // request pipeline load from write-FIFO if available
                // do_write_fifo_read already computed above (fifo_w_rd_en)
                if (do_write_fifo_read) burst_cnt_next = burst_cnt - 1;
                if ((burst_cnt == 1) && do_write_fifo_read) begin
                    load_twr = 1'b1;
                    state_next = IDLE;
                end
            end
            PRECHARGE_CMD: begin
                sdram_cmd_pins_t pins = get_sdram_cmd(CMD_PRECHARGE);
                sdram_cs_n = pins.cs; sdram_ras_n = pins.ras; sdram_we_n = pins.we;
                sdram_ba = cmd_addr.bank;
                load_trp = 1'b1;
                bank_state_next[cmd_addr.bank] = B_IDLE;
                state_next = EVAL_BANK;
            end
            REFRESH_CMD: begin
                sdram_cmd_pins_t pins = get_sdram_cmd(CMD_REFRESH);
                sdram_cs_n = pins.cs; sdram_ras_n = pins.ras; sdram_cas_n = pins.cas;
                load_trfc = 1'b1;
                refresh_pending_next = 1'b0;
                refresh_counter_next = REFRESH_INTERVAL;
                state_next = IDLE;
            end
            default: state_next = IDLE;
        endcase

        // ----- perform FIFO pointer & count arithmetic (atomic combinational) -----
        if (do_read_fifo_write) begin
            read_fifo_data[fifo_r_wptr] = sdram_dq;
            read_fifo_last[fifo_r_wptr] = (burst_cnt == 1);
            fifo_r_wptr_next = fifo_r_wptr + 1;
        end
        if (do_read_fifo_read) fifo_r_rptr_next = fifo_r_rptr + 1;
        fifo_r_count_next = fifo_r_count + (do_read_fifo_write ? 1 : 0) - (do_read_fifo_read ? 1 : 0);

        if (do_write_fifo_write) begin
            write_fifo_data[fifo_w_wptr] = wdata;
            write_fifo_dqm[fifo_w_wptr]  = wdata_dqm_i;
            fifo_w_wptr_next = fifo_w_wptr + 1;
        end
        if (do_write_fifo_read) fifo_w_rptr_next = fifo_w_rptr + 1;
        fifo_w_count_next = fifo_w_count + (do_write_fifo_write ? 1 : 0) - (do_write_fifo_read ? 1 : 0);

        // ----- response and wdata ready -----
        resp_valid = (fifo_r_count != 0);
        resp_last  = (fifo_r_count != 0) ? read_fifo_last[fifo_r_rptr] : 1'b0;
        resp_data  = (fifo_r_count != 0) ? read_fifo_data[fifo_r_rptr] : '0;
        wdata_ready = !fifo_w_full;
    end

    // physical pin assignments & pipeline outputs
    assign sdram_dq  = (dq_write_enable_d) ? write_data_reg : 'z;
    assign sdram_dqm = (dq_write_enable_d) ? write_dqm_reg : '0;
    assign sdram_clk = clk_sh;

    // debug outputs (compact)
    generate
        if (ENABLE_DEBUG) begin : g_debug
            assign debug_state_o = state_reg;
            assign debug_rd_fifo_level_o = fifo_r_count;
            assign debug_wr_fifo_level_o = fifo_w_count;
            assign debug_cmd_fifo_level_o = (state_reg == IDLE && !refresh_pending) ? '0 : '1;
        end else begin : g_no_debug
            assign debug_state_o = '0;
            assign debug_rd_fifo_level_o = '0;
            assign debug_wr_fifo_level_o = '0;
            assign debug_cmd_fifo_level_o = '0;
        end
    endgenerate

endmodule : SdramControllerFinal

`endif // SDRAM_CTRL_VARIANTB_SV
