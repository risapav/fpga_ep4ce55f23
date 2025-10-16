`ifndef SDRAM_CTRL_FINAL_SV
`define SDRAM_CTRL_FINAL_SV

(* default_nettype = "none" *)

import sdram_pkg::*;

// =============================================================================
// Countdown Timer Modul
// =============================================================================
module CountdownTimer #(
    parameter int COUNT_WIDTH = 4
)(
    input  logic clk,
    input  logic rstn,
    input  logic load,
    input  logic [COUNT_WIDTH-1:0] load_val,
    output logic done
);
    logic [COUNT_WIDTH-1:0] count_reg, count_next;

    always_ff @(posedge clk) begin
        if (!rstn)
            count_reg <= '0;
        else
            count_reg <= count_next;
    end

    always_comb begin
        if (load)
            count_next = load_val;
        else if (count_reg > 0)
            count_next = count_reg - 1;
        else
            count_next = count_reg;

        done = (count_reg == 0);
    end
endmodule

// =============================================================================
// Hlavný SDRAM Kontrolér
// =============================================================================
module SdramControllerFinal #(
    parameter logic ENABLE_DEBUG = 1'b1,
    parameter int CMD_FIFO_DEPTH = 16
)(
    input  logic                     clk,
    input  logic                     clk_sh,
    input  logic                     rstn,
    input  logic                     cmd_fifo_valid,
    output logic                     cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t    cmd_fifo_data,
    output logic                     resp_valid,
    output logic                     resp_last,
    output logic [sdram_pkg::DATA_WIDTH-1:0]    resp_data,
    input  logic                     resp_ready,
    input  logic                     wdata_valid,
    output logic                     wdata_ready,
    input  logic [sdram_pkg::DATA_WIDTH-1:0]    wdata,
    input  logic [sdram_pkg::DATA_WIDTH/8-1:0]  wdata_dqm_i,
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0]  sdram_addr,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic                     sdram_cs_n,
    output logic                     sdram_ras_n,
    output logic                     sdram_cas_n,
    output logic                     sdram_we_n,
    inout  wire  [sdram_pkg::DATA_WIDTH-1:0]    sdram_dq,
    output logic [sdram_pkg::DATA_WIDTH/8-1:0]  sdram_dqm,
    output logic                     sdram_cke,
    output logic                     sdram_clk,
    output logic [4:0]               debug_state_o,
    output logic [$clog2((1<<4)+1)-1:0] debug_rd_fifo_level_o,
    output logic [$clog2((1<<4)+1)-1:0] debug_wr_fifo_level_o,
    output logic [$clog2(CMD_FIFO_DEPTH)-1:0] debug_cmd_fifo_level_o
);

    // --- Lokálne parametre ---
    localparam integer FIFO_DEPTH_BITS = 4;
    localparam integer FIFO_DEPTH = 1 << FIFO_DEPTH_BITS;
    localparam integer NUM_BANKS = 2**BANK_ADDR_WIDTH;
    localparam integer NS_PER_SEC = 1_000_000_000;
    localparam integer CLK_PERIOD_NS = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam integer WAIT_TIME_NS = 200_000;
    localparam integer INIT_WAIT_CYCLES = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam integer REFRESH_INTERVAL = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam integer AP_BIT_INDEX = 10;

    // --- Typy ---
    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS,
        IDLE, EVAL_BANK, EVAL_PRECHARGE, EVAL_TIMING,
        ACTIVATE_CMD, READ_CMD, WRITE_CMD,
        PRECHARGE_CMD, REFRESH_CMD, READ_BURST, WRITE_BURST
    } state_t;

    typedef enum { NOP, ACTIVE, READ, WRITE, PRECHARGE, REFRESH, MRS } cmd_type_e;

    typedef struct packed {
        logic cs, ras, cas, we;
    } sdram_cmd_pins_t;

    function automatic sdram_cmd_pins_t get_sdram_cmd(cmd_type_e cmd_type);
        case(cmd_type)
            ACTIVE:    return '{cs:0, ras:0, cas:1, we:1};
            READ:      return '{cs:0, ras:1, cas:0, we:1};
            WRITE:     return '{cs:0, ras:1, cas:0, we:0};
            PRECHARGE: return '{cs:0, ras:0, cas:1, we:0};
            REFRESH:   return '{cs:0, ras:0, cas:0, we:1};
            MRS:       return '{cs:0, ras:0, cas:0, we:0};
            default:   return '{cs:1, ras:1, cas:1, we:1};
        endcase
    endfunction

    // --- Registre ---
    state_t state_reg, state_next;
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS-1:0], bank_state_next[NUM_BANKS-1:0];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS-1:0], active_row_next[NUM_BANKS-1:0];
    logic [$clog2(tRAS+1)-1:0] tras_timer[NUM_BANKS-1:0], tras_timer_next[NUM_BANKS-1:0];

    logic [$clog2(REFRESH_INTERVAL+1)-1:0] refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;
    logic [$clog2(BURST_LEN):0] burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0] cas_cnt, cas_cnt_next;
    sdram_cmd_t current_cmd, current_cmd_next;

    logic dq_write_enable, dq_write_enable_d;

    logic [DATA_WIDTH-1:0]      read_fifo_data[FIFO_DEPTH];
    logic                       read_fifo_last[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_r_wptr, fifo_r_wptr_next;
    logic [FIFO_DEPTH_BITS-1:0] fifo_r_rptr, fifo_r_rptr_next;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_r_count, fifo_r_count_next;
    logic [DATA_WIDTH-1:0]      write_fifo_data[FIFO_DEPTH];
    logic [DATA_WIDTH/8-1:0]    write_fifo_dqm[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_w_wptr, fifo_w_wptr_next;
    logic [FIFO_DEPTH_BITS-1:0] fifo_w_rptr, fifo_w_rptr_next;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_w_count, fifo_w_count_next;

    logic [DATA_WIDTH-1:0] write_data_reg;
    logic [DATA_WIDTH/8-1:0] write_dqm_reg;
    logic do_write_fifo_read;

    // --- Inštancie Časovačov ---
    CountdownTimer #($clog2(tRP+1)) trp_timer_inst (.clk(clk), .rstn(rstn), .load(load_trp), .load_val(tRP), .done(trp_done));
    CountdownTimer #($clog2(tRCD+1)) trcd_timer_inst (.clk(clk), .rstn(rstn), .load(load_trcd), .load_val(tRCD), .done(trcd_done));
    CountdownTimer #($clog2(tWR+1)) twr_timer_inst (.clk(clk), .rstn(rstn), .load(load_twr), .load_val(tWR), .done(twr_done));
    CountdownTimer #($clog2(tRFC+1)) trfc_timer_inst (.clk(clk), .rstn(rstn), .load(load_trfc), .load_val(tRFC), .done(trfc_done));
    CountdownTimer #($clog2(INIT_WAIT_CYCLES+1)) init_timer_inst (.clk(clk), .rstn(rstn), .load(load_init), .load_val(INIT_WAIT_CYCLES), .done(init_done));

    // --- Sekvenčná logika ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            cas_cnt <= '0;
            burst_cnt <= '0;
            current_cmd <= '0;
            fifo_r_wptr <= '0; fifo_r_rptr <= '0; fifo_r_count <= '0;
            fifo_w_wptr <= '0; fifo_w_rptr <= '0; fifo_w_count <= '0;
            dq_write_enable_d <= 1'b0;
            write_data_reg <= '0;
            write_dqm_reg <= '0;
            for (int i=0;i<NUM_BANKS;i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
                tras_timer[i] <= '0;
            end
        end else begin
            state_reg <= state_next;
            burst_cnt <= burst_cnt_next;
            cas_cnt <= cas_cnt_next;
            fifo_r_wptr <= fifo_r_wptr_next;
            fifo_r_rptr <= fifo_r_rptr_next;
            fifo_r_count <= fifo_r_count_next;
            fifo_w_wptr <= fifo_w_wptr_next;
            fifo_w_rptr <= fifo_w_rptr_next;
            fifo_w_count <= fifo_w_count_next;
            refresh_counter <= refresh_counter_next;
            refresh_pending <= refresh_pending_next;
            for (int i=0;i<NUM_BANKS;i++) begin
                bank_state[i] <= bank_state_next[i];
                active_row[i] <= active_row_next[i];
                tras_timer[i] <= tras_timer_next[i];
            end

            dq_write_enable_d <= (state_reg == WRITE_BURST);
            if (do_write_fifo_read) begin
                write_data_reg <= write_fifo_data[fifo_w_rptr];
                write_dqm_reg <= write_fifo_dqm[fifo_w_rptr];
            end else if (state_reg == WRITE_BURST) begin
                write_dqm_reg <= {(DATA_WIDTH/8){1'b1}};
            end
        end
    end

    // --- Kombinačná logika ---
    always_comb begin
        sdram_addr_t cmd_addr;
        logic fifo_r_full, fifo_r_empty;
        logic fifo_w_full, fifo_w_empty;
        sdram_cmd_pins_t cmd_pins;

        // Predvolené hodnoty
        state_next = state_reg;
        burst_cnt_next = burst_cnt;
        cas_cnt_next = cas_cnt;
        fifo_r_wptr_next = fifo_r_wptr;
        fifo_r_rptr_next = fifo_r_rptr;
        fifo_r_count_next = fifo_r_count;
        fifo_w_wptr_next = fifo_w_wptr;
        fifo_w_rptr_next = fifo_w_rptr;
        fifo_w_count_next = fifo_w_count;
        refresh_counter_next = refresh_counter;
        refresh_pending_next = refresh_pending;
        for (int i=0;i<NUM_BANKS;i++) begin
            bank_state_next[i] = bank_state[i];
            active_row_next[i] = active_row[i];
            tras_timer_next[i] = tras_timer[i];
        end
        cmd_pins = get_sdram_cmd(NOP);

        fifo_r_full = (fifo_r_count == FIFO_DEPTH);
        fifo_r_empty = (fifo_r_count == 0);
        fifo_w_full = (fifo_w_count == FIFO_DEPTH);
        fifo_w_empty = (fifo_w_count == 0);

        do_write_fifo_read  = (!fifo_w_empty && state_reg == WRITE_BURST);

        cmd_addr = sdram_addr_t'(current_cmd.addr);

        // --- State Machine Next-State ---
        case (state_reg)
            IDLE: if (cmd_fifo_valid && !fifo_r_full) state_next = EVAL_BANK;
            READ_BURST: if (burst_cnt == 1) state_next = IDLE;
            WRITE_BURST: if (burst_cnt == 1) state_next = IDLE;
            default: state_next = state_reg;
        endcase

        // FIFO next-state
        if (do_write_fifo_read) fifo_w_rptr_next = fifo_w_rptr + 1;
    end

    assign sdram_dq = (dq_write_enable_d) ? write_data_reg : 'z;
    assign sdram_clk = clk_sh;

endmodule

`endif
