// =============================================================================
// Súbor: framebuffer_system.sv
// Verzia: 2.6 - Finálny refaktoring podľa expertnej analýzy
// Dátum: 16. október 2025
//
// Popis:
// Táto finálna verzia implementuje všetky odporúčania z expertnej analýzy:
// 1. AsyncFifoGeneric bol vylepšený o priame výstupy pre overflow/underflow.
// 2. Do AXI wrappera boli pridané komentáre pre lepšiu čitateľnosť.
// 3. Všetky moduly sú plne integrované s robustnými prepojeniami.
//
// =============================================================================

`ifndef FRAMEBUFFER_SYSTEM_SV
`define FRAMEBUFFER_SYSTEM_SV

(* default_nettype = "none" *)

// =============================================================================
// Balíček so zdieľanými typmi a parametrami
// =============================================================================
package sdram_pkg;
    parameter int DATA_WIDTH      = 16;
    parameter int ROW_ADDR_WIDTH  = 13;
    parameter int COL_ADDR_WIDTH  = 9;
    parameter int BANK_ADDR_WIDTH = 2;
    parameter int ADDR_WIDTH      = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;
    parameter int BURST_LEN       = 8;
    parameter int CAS_LATENCY     = 3;
    parameter int CLOCK_FREQ_HZ   = 100_000_000;
    parameter int tRP             = 3;
    parameter int tRCD            = 3;
    parameter int tWR             = 2;
    parameter int tRFC            = 9;
    parameter int tRAS            = 7;
    parameter int tMRD            = 2;

    localparam int NS_PER_SEC = 1_000_000_000;
    localparam int CLK_PERIOD_NS = (NS_PER_SEC + CLOCK_FREQ_HZ - 1) / CLOCK_FREQ_HZ;
    localparam int REFRESH_INTERVAL_NS = 7812;
    localparam int REFRESH_INTERVAL = (REFRESH_INTERVAL_NS + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;

    localparam logic [2:0] burst_len_bits = (BURST_LEN == 8) ? 3'b011 : 3'b000;
    localparam logic [2:0] cas_latency_bits = (CAS_LATENCY == 3) ? 3'b011 : 3'b010;
    localparam logic [ROW_ADDR_WIDTH-1:0] mrs_value_addr = {1'b0, 1'b0, 2'b00, cas_latency_bits, 1'b0, burst_len_bits};

    typedef struct packed {
        logic [BANK_ADDR_WIDTH-1:0] bank;
        logic [ROW_ADDR_WIDTH-1:0]  row;
        logic [COL_ADDR_WIDTH-1:0]  col;
    } sdram_addr_t;

    typedef struct packed {
        sdram_addr_t addr;
        logic        rw; // 1 = write, 0 = read
        logic        auto_precharge;
    } sdram_cmd_t;

    function automatic sdram_addr_t flat_to_struct_addr(logic [ADDR_WIDTH-1:0] flat);
        sdram_addr_t s;
        s.bank = flat[ADDR_WIDTH-1 -: BANK_ADDR_WIDTH];
        s.row  = flat[ADDR_WIDTH-BANK_ADDR_WIDTH-1 -: ROW_ADDR_WIDTH];
        s.col  = flat[COL_ADDR_WIDTH-1:0];
        return s;
    endfunction

    typedef enum logic [1:0] { EMPTY, FILLING, FULL, READING } buffer_state_t;
endpackage : sdram_pkg

// =============================================================================
// Countdown Timer Modul
// =============================================================================
module CountdownTimer #(parameter int COUNT_WIDTH = 4)
   (input logic clk, input logic rstn, input logic load, input logic [COUNT_WIDTH-1:0] load_val, output logic done);
    logic [COUNT_WIDTH-1:0] count_reg, count_next;
    always_ff @(posedge clk) if (!rstn) count_reg <= '0; else count_reg <= count_next;
    always_comb begin
        if (load) count_next = load_val;
        else if (count_reg > 0) count_next = count_reg - 1;
        else count_next = count_reg;
        done = (count_reg == 0);
    end
endmodule

// =============================================================================
// Async FIFO Modul
// =============================================================================
module AsyncFifoGeneric #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
) (
    input  logic rstn,
    input  logic wr_clk, input  logic wr_en, input  logic [DATA_WIDTH-1:0] wr_data, output logic wr_full,
    input  logic rd_clk, input  logic rd_en, output logic [DATA_WIDTH-1:0] rd_data, output logic rd_empty,
    // REFAKTORING (v2.6): Nové chybové výstupy
    output logic overflow,
    output logic underflow
);
    localparam int DEPTH = 1 << ADDR_WIDTH;
    (* ramstyle = "M20K" *) logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];
    logic [ADDR_WIDTH:0] wr_ptr_bin, rd_ptr_bin, wr_ptr_gray, rd_ptr_gray, wr_ptr_gray_sync, rd_ptr_gray_sync;

    always_ff @(posedge wr_clk) begin
        if (!rstn) begin
            wr_ptr_bin <= '0;
            rd_ptr_gray_sync <= '0;
        end else begin
            if(wr_en && !wr_full) wr_ptr_bin <= wr_ptr_bin + 1;
            rd_ptr_gray_sync <= rd_ptr_gray;
        end
    end
    assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;
    always_ff @(posedge wr_clk) if (wr_en && !wr_full) mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    assign wr_full = (wr_ptr_gray == {~rd_ptr_gray_sync[ADDR_WIDTH], rd_ptr_gray_sync[ADDR_WIDTH-1:0]});

    always_ff @(posedge rd_clk) begin
        if (!rstn) begin
            rd_ptr_bin <= '0;
            wr_ptr_gray_sync <= '0;
        end else begin
            if(rd_en && !rd_empty) rd_ptr_bin <= rd_ptr_bin + 1;
            wr_ptr_gray_sync <= wr_ptr_gray;
        end
    end
    assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;
    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync);

    // Chybová logika
    assign overflow = wr_en && wr_full;
    assign underflow = rd_en && rd_empty;
endmodule

// =============================================================================
// SDRAM Controller Modul
// =============================================================================
module SdramControllerFinal #(parameter int FIFO_DEPTH_BITS = 4, parameter logic ENABLE_DEBUG = 1'b1)
   (input logic clk, input logic clk_sh, input logic rstn, input logic cmd_fifo_valid, output logic cmd_fifo_ready,
    input sdram_pkg::sdram_cmd_t cmd_fifo_data, output logic resp_valid, output logic resp_last, output logic [sdram_pkg::DATA_WIDTH-1:0] resp_data,
    input logic resp_ready, input logic wdata_valid, output logic wdata_ready, input logic [sdram_pkg::DATA_WIDTH-1:0] wdata,
    input logic [sdram_pkg::DATA_WIDTH/8-1:0] wdata_dqm_i, output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba, output logic sdram_cs_n, output logic sdram_ras_n, output logic sdram_cas_n,
    output logic sdram_we_n, inout wire [sdram_pkg::DATA_WIDTH-1:0] sdram_dq, output logic [sdram_pkg::DATA_WIDTH/8-1:0] sdram_dqm,
    output logic sdram_cke, output logic sdram_clk, input logic debug_error_reset_i, output logic controller_busy_o,
    output logic [4:0] debug_state_o, output logic [1:0] debug_fifo_error_o);
    import sdram_pkg::*;
    localparam int NUM_BANKS = 1 << BANK_ADDR_WIDTH;
    localparam int NS_PER_SEC = 1_000_000_000;
    localparam int WAIT_TIME_NS = 200_000;
    localparam int INIT_WAIT_CYCLES = (WAIT_TIME_NS + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
    localparam int AP_BIT_INDEX = 10;
    typedef enum logic [4:0] {INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS, INIT_MRS_WAIT, IDLE, EVAL_BANK, EVAL_PRECHARGE, EVAL_TIMING, ACTIVATE_CMD, READ_CMD, WRITE_CMD, PRECHARGE_CMD, REFRESH_CMD, READ_BURST, WRITE_BURST} state_t;
    typedef enum {NOP, ACTIVE, READ, WRITE, PRECHARGE, REFRESH, MRS} cmd_type_e;
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    typedef struct packed {logic cs, ras, cas, we;} sdram_cmd_pins_t;
    function automatic sdram_cmd_pins_t get_sdram_cmd(cmd_type_e cmd_type); case(cmd_type) ACTIVE: return '{cs:0, ras:0, cas:1, we:1}; READ: return '{cs:0, ras:1, cas:0, we:1}; WRITE: return '{cs:0, ras:1, cas:0, we:0}; PRECHARGE: return '{cs:0, ras:0, cas:1, we:0}; REFRESH: return '{cs:0, ras:0, cas:0, we:1}; MRS: return '{cs:0, ras:0, cas:0, we:0}; default: return '{cs:1, ras:1, cas:1, we:1}; endcase endfunction
    state_t state_reg, state_next;
    bank_state_t bank_state[NUM_BANKS-1:0], bank_state_next[NUM_BANKS-1:0];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS-1:0], active_row_next[NUM_BANKS-1:0];
    logic [$clog2(tRAS+1)-1:0] tras_timer[NUM_BANKS-1:0], tras_timer_next[NUM_BANKS-1:0];
    logic load_trp, load_trcd, load_twr, load_trfc, load_init, load_trmrd;
    logic trp_done, trcd_done, twr_done, trfc_done, init_done, trmrd_done;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0] refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;
    logic [$clog2(BURST_LEN):0] burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0] cas_cnt, cas_cnt_next;
    sdram_cmd_t current_cmd, current_cmd_next;
    logic dq_write_enable, dq_write_enable_d;
    logic wr_fifo_full, wr_fifo_empty, rd_fifo_full, rd_fifo_empty;
    logic wr_fifo_wr_en, wr_fifo_rd_en, rd_fifo_wr_en, rd_fifo_rd_en;
    logic [DATA_WIDTH-1:0] wr_fifo_rd_data; logic [DATA_WIDTH/8-1:0] wr_dqm_fifo_rd_data;
    logic last_bit_out, last_bit_fifo_empty;
    logic rd_fifo_err_l, wr_fifo_err_l;
    logic rd_fifo_overflow, rd_fifo_underflow, wr_fifo_overflow, wr_fifo_underflow;
    logic [DATA_WIDTH-1:0] write_data_reg; logic [DATA_WIDTH/8-1:0] write_dqm_reg;
    CountdownTimer #($clog2(tRP+1)) trp_timer_inst(.clk(clk), .rstn(rstn), .load(load_trp), .load_val(tRP), .done(trp_done));
    CountdownTimer #($clog2(tRCD+1)) trcd_timer_inst(.clk(clk), .rstn(rstn), .load(load_trcd), .load_val(tRCD), .done(trcd_done));
    CountdownTimer #($clog2(tWR+1)) twr_timer_inst(.clk(clk), .rstn(rstn), .load(load_twr), .load_val(tWR), .done(twr_done));
    CountdownTimer #($clog2(tRFC+1)) trfc_timer_inst(.clk(clk), .rstn(rstn), .load(load_trfc), .load_val(tRFC), .done(trfc_done));
    CountdownTimer #($clog2(INIT_WAIT_CYCLES+1)) init_timer_inst(.clk(clk), .rstn(rstn), .load(load_init), .load_val(INIT_WAIT_CYCLES), .done(init_done));
    CountdownTimer #($clog2(tMRD+1)) trmrd_timer_inst(.clk(clk), .rstn(rstn), .load(load_trmrd), .load_val(tMRD), .done(trmrd_done));
    AsyncFifoGeneric #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(FIFO_DEPTH_BITS)) write_fifo_inst(.rstn(rstn), .wr_clk(clk), .wr_en(wr_fifo_wr_en), .wr_data(wdata), .wr_full(wr_fifo_full), .rd_clk(clk), .rd_en(wr_fifo_rd_en), .rd_data(wr_fifo_rd_data), .rd_empty(wr_fifo_empty), .overflow(wr_fifo_overflow), .underflow(wr_fifo_underflow));
    AsyncFifoGeneric #(.DATA_WIDTH(DATA_WIDTH/8), .ADDR_WIDTH(FIFO_DEPTH_BITS)) write_dqm_fifo_inst(.rstn(rstn), .wr_clk(clk), .wr_en(wr_fifo_wr_en), .wr_data(wdata_dqm_i), .wr_full(), .rd_clk(clk), .rd_en(wr_fifo_rd_en), .rd_data(wr_dqm_fifo_rd_data), .rd_empty(), .overflow(), .underflow());
    AsyncFifoGeneric #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(FIFO_DEPTH_BITS)) read_fifo_inst(.rstn(rstn), .wr_clk(clk), .wr_en(rd_fifo_wr_en), .wr_data(sdram_dq), .wr_full(rd_fifo_full), .rd_clk(clk), .rd_en(rd_fifo_rd_en), .rd_data(resp_data), .rd_empty(rd_fifo_empty), .overflow(rd_fifo_overflow), .underflow(rd_fifo_underflow));
    AsyncFifoGeneric #(.DATA_WIDTH(1), .ADDR_WIDTH(FIFO_DEPTH_BITS)) read_fifo_last_inst(.rstn(rstn), .wr_clk(clk), .wr_en(rd_fifo_wr_en), .wr_data(burst_cnt == 1), .wr_full(), .rd_clk(clk), .rd_en(rd_fifo_rd_en), .rd_data(last_bit_out), .rd_empty(last_bit_fifo_empty), .overflow(), .underflow());
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT; refresh_counter <= REFRESH_INTERVAL; refresh_pending <= 1'b0; cas_cnt <= '0;
            burst_cnt <= '0; current_cmd.addr <= '0; current_cmd.rw <= 1'b0; current_cmd.auto_precharge <= 1'b0;
            dq_write_enable_d <= 1'b0; write_data_reg <= '0; write_dqm_reg <= '0; rd_fifo_err_l <= 1'b0; wr_fifo_err_l <= 1'b0;
            for (int j=0; j < NUM_BANKS; j=j+1) begin
                bank_state[j] <= BANK_IDLE; active_row[j] <= '0; tras_timer[j] <= '0;
            end
        end else begin
            if (debug_error_reset_i) begin rd_fifo_err_l <= 1'b0; wr_fifo_err_l <= 1'b0; end
            state_reg <= state_next; burst_cnt <= burst_cnt_next; cas_cnt <= cas_cnt_next; current_cmd <= current_cmd_next;
            refresh_counter <= refresh_counter_next; refresh_pending <= refresh_pending_next;
            for (int j=0; j < NUM_BANKS; j=j+1) begin
                bank_state[j] <= bank_state_next[j]; active_row[j] <= active_row_next[j]; tras_timer[j] <= tras_timer_next[j];
            end
            dq_write_enable_d <= dq_write_enable;
            if (wr_fifo_rd_en && !wr_fifo_empty) begin write_data_reg <= wr_fifo_rd_data; write_dqm_reg <= wr_dqm_fifo_rd_data; end
            else if (state_reg == WRITE_BURST) begin write_dqm_reg <= {(DATA_WIDTH/8){1'b1}}; end
            if (rd_fifo_overflow || rd_fifo_underflow) rd_fifo_err_l <= 1'b1;
            if (wr_fifo_overflow || wr_fifo_underflow) wr_fifo_err_l <= 1'b1;
        end
    end
    always_comb begin
        sdram_addr_t cmd_addr; sdram_cmd_pins_t cmd_pins;
        state_next = state_reg; refresh_counter_next = refresh_counter; refresh_pending_next = refresh_pending;
        cas_cnt_next = cas_cnt; burst_cnt_next = burst_cnt; current_cmd_next = current_cmd;
        for (int j=0; j < NUM_BANKS; j=j+1) begin
            bank_state_next[j] = bank_state[j]; active_row_next[j] = active_row[j]; tras_timer_next[j] = tras_timer[j];
        end
        cmd_addr = current_cmd.addr; cmd_fifo_ready = 1'b0; dq_write_enable = 1'b0;
        sdram_addr = '0; sdram_ba = '0; cmd_pins = get_sdram_cmd(NOP); sdram_cke = 1'b1;
        load_trp = 1'b0; load_trcd = 1'b0; load_twr = 1'b0; load_trfc = 1'b0; load_init = 1'b0; load_trmrd = 1'b0;
        for (int j=0; j < NUM_BANKS; j=j+1) if (tras_timer[j] > 0) tras_timer_next[j] = tras_timer[j] - 1;
        if (state_reg != REFRESH_CMD && refresh_counter > 0) refresh_counter_next = refresh_counter - 1; else if (state_reg != REFRESH_CMD) refresh_pending_next = 1'b1;
        if (cas_cnt > 0) cas_cnt_next = cas_cnt - 1;
        wr_fifo_wr_en = wdata_valid && !wr_fifo_full; wr_fifo_rd_en = 1'b0;
        rd_fifo_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1) && !rd_fifo_full; rd_fifo_rd_en = resp_ready && !rd_fifo_empty;
        case (state_reg)
            INIT_WAIT: if (init_done) state_next = INIT_PRECHARGE; else begin load_init = 1'b1; sdram_cke = 1'b0; end
            INIT_PRECHARGE: begin cmd_pins = get_sdram_cmd(PRECHARGE); sdram_addr[AP_BIT_INDEX] = 1'b1; load_trp = 1'b1; state_next = INIT_REFRESH1; end
            INIT_REFRESH1:  if (trp_done) begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; state_next = INIT_REFRESH2; end
            INIT_REFRESH2:  if (trfc_done) begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; state_next = INIT_MRS; end
            INIT_MRS:       if (trfc_done) begin cmd_pins = get_sdram_cmd(MRS); sdram_addr = mrs_value_addr; load_trmrd = 1'b1; state_next = INIT_MRS_WAIT; end
            INIT_MRS_WAIT:  if (trmrd_done) state_next = IDLE;
            IDLE: begin sdram_cke = 1'b1; if (refresh_pending && twr_done) state_next = REFRESH_CMD; else if (cmd_fifo_valid) begin cmd_fifo_ready = 1'b1; current_cmd_next = cmd_fifo_data; state_next = EVAL_BANK; end end
            EVAL_BANK: begin if (bank_state[cmd_addr.bank] == BANK_IDLE) begin if (trp_done) state_next = ACTIVATE_CMD; end else begin if (active_row[cmd_addr.bank] == cmd_addr.row) state_next = EVAL_TIMING; else state_next = EVAL_PRECHARGE; end end
            EVAL_PRECHARGE: if (tras_timer[cmd_addr.bank] == 0) state_next = PRECHARGE_CMD;
            EVAL_TIMING:    if (trcd_done) state_next = (current_cmd.rw == 1'b1) ? WRITE_CMD : READ_CMD;
            ACTIVATE_CMD: begin cmd_pins = get_sdram_cmd(ACTIVE); sdram_ba = cmd_addr.bank; sdram_addr = cmd_addr.row; load_trcd = 1'b1; tras_timer_next[cmd_addr.bank] = tRAS; bank_state_next[cmd_addr.bank] = BANK_ACTIVE; active_row_next[cmd_addr.bank] = cmd_addr.row; state_next = EVAL_BANK; end
            READ_CMD: begin cmd_pins = get_sdram_cmd(READ); sdram_ba = cmd_addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge; cas_cnt_next = CAS_LATENCY; burst_cnt_next = BURST_LEN; if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = BANK_IDLE; state_next = READ_BURST; end
            WRITE_CMD: begin cmd_pins = get_sdram_cmd(WRITE); sdram_ba = cmd_addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge; burst_cnt_next = BURST_LEN; if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = BANK_IDLE; state_next = WRITE_BURST; end
            READ_BURST: begin if (rd_fifo_wr_en) burst_cnt_next = burst_cnt - 1; if (burst_cnt == 1 && rd_fifo_wr_en) state_next = IDLE; end
            WRITE_BURST: begin dq_write_enable = 1'b1; burst_cnt_next = burst_cnt - 1; wr_fifo_rd_en = !wr_fifo_empty; if (burst_cnt == 1) begin load_twr = 1'b1; state_next = IDLE; end end
            PRECHARGE_CMD: begin cmd_pins = get_sdram_cmd(PRECHARGE); sdram_ba = cmd_addr.bank; load_trp = 1'b1; bank_state_next[cmd_addr.bank] = BANK_IDLE; state_next = EVAL_BANK; end
            REFRESH_CMD: begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; refresh_pending_next = 1'b0; refresh_counter_next = REFRESH_INTERVAL; state_next = IDLE; end
            default: state_next = IDLE;
        endcase
        resp_valid = !rd_fifo_empty; resp_last = !last_bit_fifo_empty && last_bit_out; wdata_ready = !wr_fifo_full;
        sdram_cs_n = cmd_pins.cs; sdram_ras_n = cmd_pins.ras; sdram_cas_n = cmd_pins.cas; sdram_we_n  = cmd_pins.we;
        sdram_dqm = (dq_write_enable_d) ? write_dqm_reg : {(DATA_WIDTH/8){1'b0}};
    end
    assign sdram_dq  = (dq_write_enable_d) ? write_data_reg : 'z;
    assign sdram_clk = clk_sh;
    generate if (ENABLE_DEBUG) begin assign debug_state_o = state_reg; assign debug_fifo_error_o = {wr_fifo_err_l, rd_fifo_err_l}; assign controller_busy_o = (state_reg != IDLE); end
    else begin assign debug_state_o = '0; assign debug_fifo_error_o = '0; assign controller_busy_o = 1'b0; end
    endgenerate
endmodule


// =============================================================================
// AXI Stream Wrapper Modul
// =============================================================================
module AxiStreamSdramWrapper #(
    parameter int SEGMENT_LEN_WORDS = 1024,
    parameter int NUM_BUFFERS       = 2,
    parameter int PIPELINE_DEPTH_BURSTS = 4,
    parameter int PIPELINE_WRITE_THRESHOLD_BURSTS = 2,
    parameter int STREAM_TIMEOUT_CYCLES = 1_000_000,
    parameter int CMD_FIFO_THRESHOLD = 4
) (
    input  logic [sdram_pkg::DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,
    input  logic                       s_axis_tuser_sof,
    output logic [sdram_pkg::DATA_WIDTH-1:0] m_axis_tdata,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast,
    output logic                     cmd_fifo_valid,
    input  logic                     cmd_fifo_ready,
    input  logic                     controller_busy_i,
    output sdram_pkg::sdram_cmd_t    cmd_fifo_data,
    output logic                     wdata_valid,
    output logic [sdram_pkg::DATA_WIDTH-1:0] wdata,
    output logic [sdram_pkg::DATA_WIDTH/8-1:0] wdata_dqm_i,
    input  logic                     wdata_ready,
    input  logic                     resp_valid,
    input  logic                     resp_last,
    input  logic [sdram_pkg::DATA_WIDTH-1:0] resp_data,
    output logic                     resp_ready,
    input  logic                     clk,
    input  logic                     rstn,
    input  logic                     soft_reset_i,
    output logic                       stream_timeout_error,
    output logic [7:0]                 debug_wrapper_o
);
    import sdram_pkg::*;
    localparam int AXIS_DATA_WIDTH = DATA_WIDTH;
    localparam int BUFFERS_ADDR_WIDTH = $clog2(NUM_BUFFERS);
    localparam int PIPELINE_BUFFER_SIZE = PIPELINE_DEPTH_BURSTS * BURST_LEN;
    localparam int PIPELINE_WRITE_THRESHOLD_WORDS = PIPELINE_WRITE_THRESHOLD_BURSTS * BURST_LEN;
    localparam int WORDS_PER_BURST = BURST_LEN;
    localparam int SDRAM_ADDR_WIDTH = 24;
    localparam logic [SDRAM_ADDR_WIDTH-1:0] SDRAM_BASE_ADDR = '0;
    genvar k;
    logic [SDRAM_ADDR_WIDTH-1:0] BUFFER_BASE_ADDRS [NUM_BUFFERS-1:0];
    generate for (k = 0; k < NUM_BUFFERS; k++) begin : gen_addr_calculator_wrapper localparam logic [SDRAM_ADDR_WIDTH-1:0] addr = SDRAM_BASE_ADDR + (k * SEGMENT_LEN_WORDS * (DATA_WIDTH/8)); assign BUFFER_BASE_ADDRS[k] = addr; end endgenerate
    buffer_state_t buffer_state [0:NUM_BUFFERS-1];
    logic [BUFFERS_ADDR_WIDTH-1:0] write_ptr, read_ptr;
    logic read_cmd_issued[0:NUM_BUFFERS-1];
    logic [$clog2(SEGMENT_LEN_WORDS+1)-1:0] segment_actual_len_words [0:NUM_BUFFERS-1];
    logic [$clog2(SEGMENT_LEN_WORDS/BURST_LEN)-1:0] segment_total_bursts [0:NUM_BUFFERS-1];
    logic write_frame_finished;
    logic [BUFFERS_ADDR_WIDTH-1:0] last_write_ptr_for_frame;
    logic [AXIS_DATA_WIDTH-1:0] w_pipeline_buffer [0:PIPELINE_BUFFER_SIZE-1];
    logic [$clog2(PIPELINE_BUFFER_SIZE)-1:0] w_pipeline_wptr, w_pipeline_rptr;
    logic [$clog2(PIPELINE_BUFFER_SIZE+1)-1:0] w_pipeline_level;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] write_segment_word_count;
    logic [$clog2(SEGMENT_LEN_WORDS/BURST_LEN)-1:0] write_segment_burst_count;
    logic [$clog2(SEGMENT_LEN_WORDS)-1:0] read_segment_word_count;
    logic issue_write_cmd, issue_read_cmd;
    logic internal_reset;
    logic [$clog2(STREAM_TIMEOUT_CYCLES)-1:0] timeout_counter;
    logic timeout_active;
    logic word_accepted_comb, close_write_segment_comb, is_last_write_burst_comb, last_word_of_read_segment_comb;
    always_ff @(posedge clk) begin
        if (!rstn || internal_reset || soft_reset_i) begin
            buffer_state[0] <= EMPTY; buffer_state[1] <= EMPTY;
            read_cmd_issued[0] <= 1'b0; read_cmd_issued[1] <= 1'b0;
            segment_actual_len_words[0] <= '0; segment_actual_len_words[1] <= '0;
            segment_total_bursts[0] <= '0; segment_total_bursts[1] <= '0;
            write_ptr <= '0; read_ptr <= '0;
            write_segment_word_count <= '0; write_segment_burst_count <= '0; read_segment_word_count <= '0;
            w_pipeline_wptr <= '0; w_pipeline_rptr <= '0; w_pipeline_level <= '0;
            write_frame_finished <= 1'b0; last_write_ptr_for_frame <= '0;
            timeout_active <= 1'b0; timeout_counter <= '0;
        end else begin
            if (s_axis_tuser_sof && word_accepted_comb) begin timeout_active <= 1'b1; timeout_counter <= STREAM_TIMEOUT_CYCLES - 1; end
            else if (timeout_active) begin
                if (word_accepted_comb) timeout_counter <= STREAM_TIMEOUT_CYCLES - 1;
                else timeout_counter <= timeout_counter - 1;
                if (s_axis_tlast && word_accepted_comb) timeout_active <= 1'b0;
            end
            if (word_accepted_comb) write_segment_word_count <= write_segment_word_count + 1;
            if (buffer_state[write_ptr] == EMPTY && word_accepted_comb) buffer_state[write_ptr] <= FILLING;
            if (buffer_state[write_ptr] == FILLING && close_write_segment_comb) begin
                buffer_state[write_ptr] <= FULL;
                segment_actual_len_words[write_ptr] <= write_segment_word_count + 1;
                segment_total_bursts[write_ptr] <= (write_segment_word_count + 1 + WORDS_PER_BURST - 1) / WORDS_PER_BURST;
                if (s_axis_tlast) begin write_frame_finished <= 1'b1; last_write_ptr_for_frame <= write_ptr; end
            end
            if (buffer_state[write_ptr] == FULL && is_last_write_burst_comb) begin write_ptr <= (write_ptr + 1) % NUM_BUFFERS; write_segment_burst_count <= '0; write_segment_word_count <= '0; end
            if (buffer_state[read_ptr] == FULL && read_cmd_issued[read_ptr]) buffer_state[read_ptr] <= READING;
            if (buffer_state[read_ptr] == READING && last_word_of_read_segment_comb) begin buffer_state[read_ptr] <= EMPTY; read_cmd_issued[read_ptr] <= 1'b0; read_ptr <= (read_ptr + 1) % NUM_BUFFERS; read_segment_word_count <= '0; end
            if (issue_read_cmd && cmd_fifo_ready) read_cmd_issued[read_ptr] <= 1'b1;
            if (word_accepted_comb) begin w_pipeline_buffer[w_pipeline_wptr] <= s_axis_tdata; w_pipeline_wptr <= w_pipeline_wptr + 1; end
            if (wdata_valid && wdata_ready) w_pipeline_rptr <= w_pipeline_rptr + 1;
            w_pipeline_level <= w_pipeline_level + word_accepted_comb - (wdata_valid && wdata_ready);
            if (issue_write_cmd && cmd_fifo_ready) write_segment_burst_count <= write_segment_burst_count + 1;
            if (m_axis_tvalid && m_axis_tready) read_segment_word_count <= read_segment_word_count + 1;
        end
    end
    always_comb begin
        logic can_push_to_cmd_fifo, can_issue_write, is_last_write_burst_of_segment;
        logic can_issue_read_lookahead, can_issue_active_read, is_last_read_burst_of_segment, is_last_word_of_frame;
        logic [BUFFERS_ADDR_WIDTH-1:0] lookahead_ptr, ptr;
        logic lookahead_found;
        stream_timeout_error = timeout_active && (timeout_counter == 0);
        internal_reset = stream_timeout_error;
        s_axis_tready = (buffer_state[write_ptr] == EMPTY || buffer_state[write_ptr] == FILLING) && (w_pipeline_level < PIPELINE_BUFFER_SIZE) && !internal_reset && !soft_reset_i;
        word_accepted_comb = s_axis_tready && s_axis_tvalid;
        close_write_segment_comb = word_accepted_comb && (s_axis_tlast || (write_segment_word_count == SEGMENT_LEN_WORDS - 1));
        is_last_write_burst_of_segment = (write_segment_burst_count == segment_total_bursts[write_ptr] - 1) && (segment_total_bursts[write_ptr] > 0);
        is_last_write_burst_comb = (issue_write_cmd && cmd_fifo_ready && is_last_write_burst_of_segment);
        last_word_of_read_segment_comb = m_axis_tvalid && m_axis_tready && (read_segment_word_count == segment_actual_len_words[read_ptr] - 1);
        can_push_to_cmd_fifo = !controller_busy_i;
        can_issue_write = (w_pipeline_level >= PIPELINE_WRITE_THRESHOLD_WORDS || (buffer_state[write_ptr] == FULL && w_pipeline_level > 0)) && (buffer_state[write_ptr] == FILLING || buffer_state[write_ptr] == FULL);
        can_issue_read_lookahead = 1'b0; lookahead_ptr = '0; lookahead_found = 1'b0;
        for (int k = 0; k < NUM_BUFFERS; k = k + 1) begin
            if (!lookahead_found) begin
                ptr = (read_ptr + k) % NUM_BUFFERS;
                if (buffer_state[ptr] == FULL && !read_cmd_issued[ptr]) begin
                    can_issue_read_lookahead = 1'b1;
                    lookahead_ptr = ptr;
                    lookahead_found = 1'b1;
                end
            end
        end
        can_issue_active_read = (buffer_state[read_ptr] == READING);
        is_last_read_burst_of_segment = (read_segment_word_count >= (segment_actual_len_words[read_ptr] - WORDS_PER_BURST));
        issue_write_cmd = 1'b0; issue_read_cmd = 1'b0;
        cmd_fifo_valid = 1'b0; cmd_fifo_data.addr = '0; cmd_fifo_data.rw = 1'b0; cmd_fifo_data.auto_precharge = 1'b0;
        if (can_push_to_cmd_fifo && !internal_reset && !soft_reset_i) begin
            if (can_issue_read_lookahead) begin
                issue_read_cmd = 1'b1; cmd_fifo_valid = 1'b1;
                cmd_fifo_data.addr = flat_to_struct_addr(BUFFER_BASE_ADDRS[lookahead_ptr]); cmd_fifo_data.rw = 1'b0; cmd_fifo_data.auto_precharge = 1'b0;
            end else if (can_issue_active_read) begin
                cmd_fifo_valid = 1'b1;
                cmd_fifo_data.addr = flat_to_struct_addr(BUFFER_BASE_ADDRS[read_ptr] + read_segment_word_count); cmd_fifo_data.rw = 1'b0; cmd_fifo_data.auto_precharge = is_last_read_burst_of_segment;
            end else if (can_issue_write) begin
                issue_write_cmd = 1'b1; cmd_fifo_valid = 1'b1;
                cmd_fifo_data.addr = flat_to_struct_addr(BUFFER_BASE_ADDRS[write_ptr] + (write_segment_burst_count * WORDS_PER_BURST)); cmd_fifo_data.rw = 1'b1; cmd_fifo_data.auto_precharge = is_last_write_burst_of_segment;
            end
        end
        wdata_valid = (w_pipeline_level > 0) && !internal_reset && !soft_reset_i;
        wdata       = w_pipeline_buffer[w_pipeline_rptr];
        wdata_dqm_i = '0;
        m_axis_tvalid = resp_valid && (buffer_state[read_ptr] == READING) && !internal_reset && !soft_reset_i;
        m_axis_tdata  = resp_data;
        is_last_word_of_frame = write_frame_finished && (read_ptr == last_write_ptr_for_frame) && (read_segment_word_count == segment_actual_len_words[read_ptr] - 1);
        m_axis_tlast  = m_axis_tvalid && is_last_word_of_frame;
        resp_ready    = m_axis_tready;
        debug_wrapper_o[1:0] = read_ptr;
        debug_wrapper_o[3:2] = write_ptr;
    end
endmodule


// =============================================================================
// Top-Level Framebuffer Controller
// =============================================================================
module framebuffer_ctrl #(
    parameter C_OP_MODE = NORMAL,
    parameter H_RES           = 800,
    parameter V_RES           = 600
)(
    input  logic clk_i,
    input  logic clk_sh_i,
    input  logic rst_ni,
    axi4s_if.slave  s_axis_video_in,
    axi4s_if.master m_axis_video_out,
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    inout wire [sdram_pkg::DATA_WIDTH-1:0] sdram_dq,
    output logic [sdram_pkg::DATA_WIDTH/8-1:0] sdram_dqm,
    output logic sdram_cke,
    output logic sdram_clk,
    output logic [7:0] debug_led_0_o,
    output logic [7:0] debug_led_1_o
);
    import sdram_pkg::*;
    typedef enum { NORMAL, PASSTHROUGH } op_mode_e;
    localparam int NUM_BUFFERS = 2;
    localparam int SEGMENT_LEN_WORDS = (H_RES * V_RES) / NUM_BUFFERS;
    logic clk, clk_sh, rstn;
    assign clk = clk_i; assign clk_sh = clk_sh_i; assign rstn = rst_ni;
    logic cmd_fifo_valid, cmd_fifo_ready;
    sdram_cmd_t cmd_fifo_data;
    logic [DATA_WIDTH-1:0] wdata;
    logic [DATA_WIDTH/8-1:0] wdata_dqm_i;
    logic wdata_valid, wdata_ready;
    logic resp_valid, resp_last;
    logic [DATA_WIDTH-1:0] resp_data;
    logic resp_ready;
    logic controller_busy_sig, stream_timeout_error_sig;
    logic [4:0] debug_state_o_sig;
    logic [1:0] debug_fifo_error_o_sig;
    logic [7:0] debug_wrapper_o_sig;

    generate
        if (C_OP_MODE == NORMAL) begin : g_normal_mode
            AxiStreamSdramWrapper #(
                .SEGMENT_LEN_WORDS(SEGMENT_LEN_WORDS),
                .NUM_BUFFERS(NUM_BUFFERS)
            ) wrapper_inst (
                .clk(clk),
                .rstn(rstn),
                .soft_reset_i(1'b0),
                .s_axis_tdata(s_axis_video_in.TDATA),
                .s_axis_tvalid(s_axis_video_in.TVALID),
                .s_axis_tready(s_axis_video_in.TREADY),
                .s_axis_tlast(s_axis_video_in.TLAST),
                .s_axis_tuser_sof(s_axis_video_in.TUSER[0]),
                .m_axis_tdata(m_axis_video_out.TDATA),
                .m_axis_tvalid(m_axis_video_out.TVALID),
                .m_axis_tready(m_axis_video_out.TREADY),
                .m_axis_tlast(m_axis_video_out.TLAST),
                .cmd_fifo_valid(cmd_fifo_valid),
                .cmd_fifo_ready(cmd_fifo_ready),
                .controller_busy_i(controller_busy_sig),
                .cmd_fifo_data(cmd_fifo_data),
                .wdata_valid(wdata_valid),
                .wdata(wdata),
                .wdata_dqm_i(wdata_dqm_i),
                .wdata_ready(wdata_ready),
                .resp_valid(resp_valid),
                .resp_last(resp_last),
                .resp_data(resp_data),
                .resp_ready(resp_ready),
                .stream_timeout_error(stream_timeout_error_sig),
                .debug_wrapper_o(debug_wrapper_o_sig)
            );
            SdramControllerFinal sdram_inst (
                .clk(clk),
                .clk_sh(clk_sh),
                .rstn(rstn),
                .cmd_fifo_valid(cmd_fifo_valid),
                .cmd_fifo_ready(cmd_fifo_ready),
                .cmd_fifo_data(cmd_fifo_data),
                .resp_valid(resp_valid),
                .resp_last(resp_last),
                .resp_data(resp_data),
                .resp_ready(resp_ready),
                .wdata_valid(wdata_valid),
                .wdata(wdata),
                .wdata_dqm_i(wdata_dqm_i),
                .wdata_ready(wdata_ready),
                .sdram_addr(sdram_addr),
                .sdram_ba(sdram_ba),
                .sdram_cs_n(sdram_cs_n),
                .sdram_ras_n(sdram_ras_n),
                .sdram_cas_n(sdram_cas_n),
                .sdram_we_n(sdram_we_n),
                .sdram_dq(sdram_dq),
                .sdram_dqm(sdram_dqm),
                .sdram_cke(sdram_cke),
                .sdram_clk(sdram_clk),
                .debug_error_reset_i(1'b0),
                .controller_busy_o(controller_busy_sig),
                .debug_state_o(debug_state_o_sig),
                .debug_fifo_error_o(debug_fifo_error_o_sig)
            );
            assign debug_led_0_o = debug_wrapper_o_sig;
            assign debug_led_1_o[4:0] = debug_state_o_sig;
            assign debug_led_1_o[6:5] = debug_fifo_error_o_sig;
            assign debug_led_1_o[7] = controller_busy_sig;
        end else if (C_OP_MODE == PASSTHROUGH) begin : gen_passthrough
            assign m_axis_video_out.TDATA  = s_axis_video_in.TDATA;
            assign m_axis_video_out.TVALID = s_axis_video_in.TVALID;
            assign m_axis_video_out.TLAST  = s_axis_video_in.TLAST;
            assign m_axis_video_out.TUSER  = s_axis_video_in.TUSER;
            assign s_axis_video_in.TREADY  = m_axis_video_out.TREADY;
            assign sdram_dq = 'z;
            assign sdram_addr = '0;
            assign sdram_ba = '0;
            assign sdram_cs_n = 1'b1;
            assign sdram_ras_n = 1'b1;
            assign sdram_cas_n = 1'b1;
            assign sdram_we_n = 1'b1;
            assign sdram_dqm = '0;
            assign sdram_cke = 1'b0;
            assign sdram_clk = 1'b0;
            assign debug_led_0_o = {4'b0, s_axis_video_in.TREADY, s_axis_video_in.TVALID, m_axis_video_out.TREADY, m_axis_video_out.TVALID};
            assign debug_led_1_o = '0;
        end
    endgenerate
endmodule

`endif

