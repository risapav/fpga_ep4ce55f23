// =============================================================================
// Súbor: FramebufferWithSdramController_Final.sv
// Verzia: 3.3 (Oprava synchronizácie obrazu)
// Dátum: 17. október 2025
//
// Popis:
// Kompletný, finálny návrh ping-pong framebuffer kontroléra s integrovaným
// SDRAM radičom. Tento súbor obsahuje všetky potrebné moduly a zahŕňa
// všetky opravy a vylepšenia z predchádzajúcich iterácií.
//
// Zmeny vo verzii 3.3:
// - OPRAVA ROZHÁDZANÉHO OBRAZU: Pôvodná logika pre generovanie `m_axis_last`
//   bola chybná. Bolo pridané nové počítadlo `m_axis_x_cnt`, ktoré presne
//   sleduje počet odoslaných pixelov v riadku. Tým sa zabezpečí správna
//   synchronizácia riadkov pre VGA radič a obraz by mal byť stabilný.
// =============================================================================

`ifndef FRAMEBUFFER_PINGPONG_SDRAM_FINAL_SV
`define FRAMEBUFFER_PINGPONG_SDRAM_FINAL_SV

(* default_nettype = "none" *)

// ============================================================================
// Balíček SDRAM: Zdieľané typy a parametre
// ============================================================================
package sdram_pkg;
    parameter int DATA_WIDTH      = 16;
    parameter int ROW_ADDR_WIDTH  = 13;
    parameter int COL_ADDR_WIDTH  = 9;
    parameter int BANK_ADDR_WIDTH = 2;
    parameter int ADDR_WIDTH      = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;
    parameter int BURST_LEN       = 8;
    parameter int CAS_LATENCY     = 3;

    typedef struct packed {
        logic [BANK_ADDR_WIDTH-1:0] bank;
        logic [ROW_ADDR_WIDTH-1:0]  row;
        logic [COL_ADDR_WIDTH-1:0]  col;
    } sdram_addr_t;

    typedef struct packed {
        sdram_addr_t addr;
        logic        rw;
        logic        auto_precharge;
    } sdram_cmd_t;

endpackage : sdram_pkg

import sdram_pkg::*;

// ============================================================================
// Countdown Timer (generický)
// ============================================================================
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
        if (!rstn) count_reg <= 'b0;
        else count_reg <= count_next;
    end

    always_comb begin
        if (load) count_next = load_val;
        else if (count_reg > 0) count_next = count_reg - 1;
        else count_next = count_reg;
        done = (count_reg == 0);
    end
endmodule

// ============================================================================
// Async FIFO (dual-clock, generický)
// ============================================================================
module AsyncFifoGeneric #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
)(
    input  logic rstn,
    input  logic wr_clk,
    input  logic wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic wr_full,
    input  logic rd_clk,
    input  logic rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic rd_empty,
    output logic [$clog2(1<<ADDR_WIDTH):0] level // Zvýšená šírka pre presný výpočet
);
    localparam int DEPTH = 1 << ADDR_WIDTH;
    (* ramstyle = "M20K" *) logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    logic [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_bin_next;
    logic [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_bin_next;
    logic [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
    logic [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] rd_ptr_bin_synced_to_wr_clk, rd_ptr_bin_synced_to_wr_clk_s1;

    always_ff @(posedge wr_clk) begin
        if (!rstn) begin
            wr_ptr_bin <= 'b0;
            rd_ptr_gray_sync1 <= 'b0;
            rd_ptr_gray_sync2 <= 'b0;
        end else begin
            wr_ptr_bin <= wr_ptr_bin_next;
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    always_ff @(posedge wr_clk) begin
        if (!rstn) begin
             rd_ptr_bin_synced_to_wr_clk <= 'b0;
             rd_ptr_bin_synced_to_wr_clk_s1 <= 'b0;
        end else begin
             rd_ptr_bin_synced_to_wr_clk_s1 <= rd_ptr_bin;
             rd_ptr_bin_synced_to_wr_clk <= rd_ptr_bin_synced_to_wr_clk_s1;
        end
    end

    assign wr_ptr_bin_next = (wr_en && !wr_full) ? wr_ptr_bin + 1 : wr_ptr_bin;
    assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;
    always_ff @(posedge wr_clk)
        if (wr_en && !wr_full) mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    assign wr_full = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign level = wr_ptr_bin - rd_ptr_bin_synced_to_wr_clk;

    always_ff @(posedge rd_clk) begin
        if (!rstn) begin
            rd_ptr_bin <= 'b0;
            wr_ptr_gray_sync1 <= 'b0;
            wr_ptr_gray_sync2 <= 'b0;
        end else begin
            rd_ptr_bin <= rd_ptr_bin_next;
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end
    assign rd_ptr_bin_next = (rd_en && !rd_empty) ? rd_ptr_bin + 1 : rd_ptr_bin;
    assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;
    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);
endmodule

// ============================================================================
// >>> FSM #1 (Moore) – SDRAM Controller
// Typ: Moore
// Účel: Riadi inicializáciu, refresh, banky a generuje príkazy SDRAM.
// =====================================================================
module SdramController #(
    parameter int tRP   = 3,
    parameter int tRCD  = 3,
    parameter int tWR   = 2,
    parameter int tRFC  = 7,
    parameter int tRAS  = 7,
    parameter int tMRD  = 2,
    parameter int CLOCK_FREQ_HZ   = 100_000_000,
    parameter int FIFO_ADDR_WIDTH = 6
)(
    input  logic clk, input  logic clk_sh, input  logic rstn,
    input  sdram_cmd_t wr_cmd_data, input  logic wr_cmd_valid, output logic wr_cmd_ready,
    input  sdram_cmd_t rd_cmd_data, input  logic rd_cmd_valid, output logic rd_cmd_ready,
    input  logic [DATA_WIDTH-1:0] wdata, input  logic wdata_valid, output logic wdata_ready,
    output logic [DATA_WIDTH-1:0] rdata, output logic rdata_valid, input  logic rdata_ready,
    output logic [$clog2(1<<FIFO_ADDR_WIDTH)+1-1:0] rdata_level,
    output logic [$clog2(1<<FIFO_ADDR_WIDTH)+1-1:0] wdata_level,
    output logic [ROW_ADDR_WIDTH-1:0] sdram_addr, output logic [BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n, output logic sdram_ras_n, output logic sdram_cas_n, output logic sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0] sdram_dq, output logic [DATA_WIDTH/8-1:0] sdram_dqm,
    output logic sdram_cke, output logic sdram_clk
);
    localparam int NS_PER_SEC = 1_000_000_000;
    localparam int CLK_PERIOD_NS = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam int WAIT_TIME_NS = 200_000;
    localparam int INIT_WAIT_CYCLES = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam int REFRESH_INTERVAL = (64_000_000 / (1 << ROW_ADDR_WIDTH)) / CLK_PERIOD_NS;
    localparam int AP_BIT_INDEX = 10;
    localparam logic [ROW_ADDR_WIDTH-1:0] mrs_value_addr = {1'b0, 1'b0, 2'b00, (CAS_LATENCY==3 ? 3'b011:3'b010), 1'b0, (BURST_LEN==8 ? 3'b011:3'b000)};
    localparam int NUM_BANKS = 1 << BANK_ADDR_WIDTH;

    typedef enum logic [4:0] {
      INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1,
      INIT_REFRESH2, INIT_MRS, INIT_MRS_WAIT,
      IDLE, EVAL_BANK, EVAL_PRECHARGE, EVAL_TIMING,
      ACTIVATE_CMD, READ_CMD, WRITE_CMD, PRECHARGE_CMD, REFRESH_CMD,
      READ_BURST, WRITE_BURST
      } state_t;

    typedef enum { NOP, ACTIVE, READ, WRITE, PRECHARGE, REFRESH, MRS } cmd_type_e;
    typedef struct packed { logic cs, ras, cas, we; } sdram_cmd_pins_t;

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

    state_t state_reg, state_next;

    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS-1:0], bank_state_next[NUM_BANKS-1:0];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS-1:0], active_row_next[NUM_BANKS-1:0];
    logic [$clog2(tRAS+1)-1:0] tras_timer[NUM_BANKS-1:0], tras_timer_next[NUM_BANKS-1:0];
    logic load_trp, load_trcd, load_twr, load_trfc, load_init, load_trmrd;
    logic trp_done, trcd_done, twr_done, trfc_done, init_done, trmrd_done;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0] refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;
    logic [$clog2(BURST_LEN):0] burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0] cas_cnt, cas_cnt_next;
    sdram_cmd_t current_cmd;
    logic dq_write_enable, dq_write_enable_d;
    logic [DATA_WIDTH-1:0] write_data_reg;
    logic fsm_ready_for_cmd;
    sdram_cmd_t selected_cmd;
    logic selected_cmd_valid;
    logic wr_fifo_full, wr_fifo_empty;
    logic rd_fifo_full, rd_fifo_empty;
    logic wr_fifo_wr_en, wr_fifo_rd_en;
    logic rd_fifo_wr_en, rd_fifo_rd_en;
    logic [DATA_WIDTH-1:0] wr_fifo_rd_data;
    CountdownTimer #($clog2(tRP+1))   trp_timer_inst (.clk(clk),.rstn(rstn),.load(load_trp),.load_val(tRP),.done(trp_done));
    CountdownTimer #($clog2(tRCD+1))  trcd_timer_inst(.clk(clk),.rstn(rstn),.load(load_trcd),.load_val(tRCD),.done(trcd_done));
    CountdownTimer #($clog2(tWR+1))   twr_timer_inst (.clk(clk),.rstn(rstn),.load(load_twr),.load_val(tWR),.done(twr_done));
    CountdownTimer #($clog2(tRFC+1))  trfc_timer_inst(.clk(clk),.rstn(rstn),.load(load_trfc),.load_val(tRFC),.done(trfc_done));
    CountdownTimer #($clog2(tMRD+1))  trmrd_timer_inst(.clk(clk),.rstn(rstn),.load(load_trmrd),.load_val(tMRD),.done(trmrd_done));
    CountdownTimer #($clog2(INIT_WAIT_CYCLES+1)) init_timer_inst(.clk(clk),.rstn(rstn),.load(load_init),.load_val(INIT_WAIT_CYCLES),.done(init_done));
    AsyncFifoGeneric #(.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(FIFO_ADDR_WIDTH)) write_fifo_inst(.rstn(rstn),.wr_clk(clk),.wr_en(wr_fifo_wr_en),.wr_data(wdata),.wr_full(wr_fifo_full),.rd_clk(clk),.rd_en(wr_fifo_rd_en),.rd_data(wr_fifo_rd_data),.rd_empty(wr_fifo_empty),.level(wdata_level));
    AsyncFifoGeneric #(.DATA_WIDTH(DATA_WIDTH),.ADDR_WIDTH(FIFO_ADDR_WIDTH)) read_fifo_inst(.rstn(rstn),.wr_clk(clk),.wr_en(rd_fifo_wr_en),.wr_data(sdram_dq),.wr_full(rd_fifo_full),.rd_clk(clk),.rd_en(rd_fifo_rd_en),.rd_data(rdata),.rd_empty(rd_fifo_empty),.level(rdata_level));

    // --- hlavná Moore FSM logika ---
    always_comb begin
        fsm_ready_for_cmd = (state_reg == IDLE) && !refresh_pending && twr_done;
        selected_cmd_valid = 1'b0;
        selected_cmd = '{default:'0};
        rd_cmd_ready = 1'b0;
        wr_cmd_ready = 1'b0;
        if (rd_cmd_valid) begin
            selected_cmd_valid = 1'b1;
            selected_cmd = rd_cmd_data;
            if (fsm_ready_for_cmd) rd_cmd_ready = 1'b1;
        end else if (wr_cmd_valid) begin
            selected_cmd_valid = 1'b1;
            selected_cmd = wr_cmd_data;
            if (fsm_ready_for_cmd) wr_cmd_ready = 1'b1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            cas_cnt <= 'b0;
            burst_cnt <= 'b0;
            current_cmd <= '{default:'0};
            dq_write_enable_d <= 1'b0;
            write_data_reg <= 'b0;
            for (int i=0; i<NUM_BANKS; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= 'b0;
                tras_timer[i] <= 'b0;
            end
        end else begin
            state_reg <= state_next;
            burst_cnt <= burst_cnt_next;
            cas_cnt <= cas_cnt_next;
            refresh_counter <= refresh_counter_next;
            refresh_pending <= refresh_pending_next;
            if (fsm_ready_for_cmd && selected_cmd_valid) current_cmd <= selected_cmd;
            for (int i=0; i<NUM_BANKS; i++) begin
                bank_state[i] <= bank_state_next[i];
                active_row[i] <= active_row_next[i];
                tras_timer[i] <= tras_timer_next[i];
            end
            dq_write_enable_d <= dq_write_enable;
            if (wr_fifo_rd_en) write_data_reg <= wr_fifo_rd_data;
        end
    end

    always_comb begin
        sdram_addr_t cmd_addr;
        sdram_cmd_pins_t cmd_pins;
        state_next = state_reg;
        refresh_counter_next = refresh_counter;
        refresh_pending_next = refresh_pending;
        cas_cnt_next = cas_cnt;
        burst_cnt_next = burst_cnt;
        for (int i=0; i<NUM_BANKS; i++) begin
            bank_state_next[i] = bank_state[i];
            active_row_next[i] = active_row[i];
            tras_timer_next[i] = tras_timer[i];
        end
        cmd_addr = current_cmd.addr;
        dq_write_enable = 1'b0;
        sdram_addr = 'b0;
        sdram_ba = 'b0;
        cmd_pins = get_sdram_cmd(NOP);
        sdram_cke = 1'b1;
        load_trp = 1'b0; load_trcd = 1'b0; load_twr = 1'b0; load_trfc = 1'b0; load_init = 1'b0; load_trmrd = 1'b0;
        for (int i=0; i<NUM_BANKS; i++)
            if (tras_timer[i] > 0) tras_timer_next[i] = tras_timer[i] - 1;
        if (cas_cnt > 0) cas_cnt_next = cas_cnt - 1;
        if (state_reg != REFRESH_CMD && refresh_counter > 0) refresh_counter_next = refresh_counter - 1;
        else if (state_reg != REFRESH_CMD && refresh_counter == 0) refresh_pending_next = 1'b1;
        wr_fifo_wr_en = wdata_valid && !wr_fifo_full;
        wr_fifo_rd_en = (state_reg == WRITE_BURST) && !wr_fifo_empty;
        rd_fifo_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1) && !rd_fifo_full;
        rd_fifo_rd_en = rdata_ready && !rd_fifo_empty;
        case (state_reg)
            INIT_WAIT: begin load_init = 1'b1; sdram_cke = 1'b0; if (init_done) state_next = INIT_PRECHARGE; end
            INIT_PRECHARGE: begin cmd_pins = get_sdram_cmd(PRECHARGE); sdram_addr[AP_BIT_INDEX] = 1'b1; load_trp = 1'b1; state_next = INIT_REFRESH1; end
            INIT_REFRESH1: if (trp_done) begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; state_next = INIT_REFRESH2; end
            INIT_REFRESH2: if (trfc_done) begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; state_next = INIT_MRS; end
            INIT_MRS: if (trfc_done) begin cmd_pins = get_sdram_cmd(MRS); sdram_addr = mrs_value_addr; load_trmrd = 1'b1; state_next = INIT_MRS_WAIT; end
            INIT_MRS_WAIT: if (trmrd_done) state_next = IDLE;
            IDLE: if (refresh_pending && twr_done) state_next = REFRESH_CMD; else if (fsm_ready_for_cmd && selected_cmd_valid) state_next = EVAL_BANK;
            EVAL_BANK: if (bank_state[cmd_addr.bank] == BANK_IDLE) begin if (trp_done) state_next = ACTIVATE_CMD; end else begin if (active_row[cmd_addr.bank] == cmd_addr.row) state_next = EVAL_TIMING; else state_next = EVAL_PRECHARGE; end
            EVAL_PRECHARGE: if (tras_timer[cmd_addr.bank] == 0) state_next = PRECHARGE_CMD;
            EVAL_TIMING: if (trcd_done) if (current_cmd.rw == 1'b1) state_next = WRITE_CMD; else state_next = READ_CMD;
            ACTIVATE_CMD: begin cmd_pins = get_sdram_cmd(ACTIVE); sdram_ba = cmd_addr.bank; sdram_addr = cmd_addr.row; load_trcd = 1'b1; tras_timer_next[cmd_addr.bank] = tRAS; bank_state_next[cmd_addr.bank] = BANK_ACTIVE; active_row_next[cmd_addr.bank] = cmd_addr.row; state_next = EVAL_BANK; end
            READ_CMD: begin cmd_pins = get_sdram_cmd(READ); sdram_ba = cmd_addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge; cas_cnt_next = CAS_LATENCY; burst_cnt_next = BURST_LEN; if (current_cmd.auto_precharge) begin bank_state_next[cmd_addr.bank] = BANK_IDLE; load_trp = 1'b1; end state_next = READ_BURST; end
            WRITE_CMD: begin cmd_pins = get_sdram_cmd(WRITE); sdram_ba = cmd_addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge; burst_cnt_next = BURST_LEN; if (current_cmd.auto_precharge) begin bank_state_next[cmd_addr.bank] = BANK_IDLE; load_twr = 1'b1; load_trp = 1'b1; end state_next = WRITE_BURST; end
            READ_BURST: if (cas_cnt == 0) begin if (burst_cnt > 0) burst_cnt_next = burst_cnt - 1; if (burst_cnt == 1) state_next = IDLE; end
            WRITE_BURST: begin dq_write_enable = 1'b1; burst_cnt_next = burst_cnt - 1; if (burst_cnt == 1) begin load_twr = 1'b1; state_next = IDLE; end end
            PRECHARGE_CMD: begin cmd_pins = get_sdram_cmd(PRECHARGE); sdram_ba = cmd_addr.bank; load_trp = 1'b1; bank_state_next[cmd_addr.bank] = BANK_IDLE; state_next = EVAL_BANK; end
            REFRESH_CMD: begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; refresh_pending_next = 1'b0; refresh_counter_next = REFRESH_INTERVAL; state_next = IDLE; end
            default: state_next = IDLE;
        endcase
        wdata_ready = !wr_fifo_full;
        rdata_valid = !rd_fifo_empty;
        sdram_cs_n  = cmd_pins.cs;
        sdram_ras_n = cmd_pins.ras;
        sdram_cas_n = cmd_pins.cas;
        sdram_we_n  = cmd_pins.we;
        sdram_dqm = (dq_write_enable_d && wr_fifo_empty) ? '1 : 'b0;
    end
    assign sdram_dq  = (dq_write_enable_d) ? write_data_reg : 'z;
    assign sdram_clk = clk_sh;
endmodule

// ============================================================================
// >>> FSM #2 a #3 (Moore) – Ping-Pong Buffer A a B
// Typ: Moore
// Účel: Sledujú stav BUF_A a BUF_B pre ping-pong režim
// ============================================================================
module FramebufferController #(
    parameter int FRAME_WIDTH  = 800,
    parameter int FRAME_HEIGHT = 600
)(
    input  logic clk, input  logic clk_sh, input  logic rstn,
    input  logic s_axis_valid, output logic s_axis_ready, input  logic [DATA_WIDTH-1:0] s_axis_data, input  logic s_axis_last,
    output logic m_axis_valid, input  logic m_axis_ready, output logic [DATA_WIDTH-1:0] m_axis_data, output logic m_axis_last,
    output logic [ROW_ADDR_WIDTH-1:0] sdram_addr, output logic [BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n, output logic sdram_ras_n, output logic sdram_cas_n, output logic sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0] sdram_dq, output logic [DATA_WIDTH/8-1:0] sdram_dqm,
    output logic sdram_cke, output logic sdram_clk,
    output logic [7:0] debug_led_0_o, output logic [7:0] debug_led_1_o
);
    localparam int FIFO_ADDR_WIDTH = 6;
    localparam int FRAME_SIZE_WORDS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int ADDR_WIDTH_TOTAL = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;
    localparam logic [ADDR_WIDTH_TOTAL-1:0] FRAME_A_BASE_ADDR = 'b0;
    localparam logic [ADDR_WIDTH_TOTAL-1:0] FRAME_B_BASE_ADDR = FRAME_SIZE_WORDS;
    typedef enum logic {BUF_A, BUF_B} active_buf_t;
    typedef enum logic [1:0] {EMPTY, FILLING, FULL, READING} buffer_state_t;

    buffer_state_t buf_a_state, buf_b_state;
    active_buf_t   write_buf, read_buf;
    logic          swap_buffers_req;
    logic [$clog2(FRAME_SIZE_WORDS)-1:0] write_addr_cnt, read_addr_cnt, wr_cmd_addr_cnt;
    sdram_cmd_t wr_cmd_data, rd_cmd_data;
    logic       wr_cmd_valid, rd_cmd_valid;
    logic       wr_cmd_ready, rd_cmd_ready;
    logic [$clog2(1<<(FIFO_ADDR_WIDTH))+1-1:0] rdata_level, wdata_level;
    logic [ADDR_WIDTH_TOTAL-1:0] wr_full_addr, rd_full_addr;
    logic       first_frame_done;

    // OPRAVA: Počítadlo pre generovanie m_axis_last
    logic [$clog2(FRAME_WIDTH)-1:0] m_axis_x_cnt;

    SdramController #(.FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)) sdram_inst (
        .clk(clk),.clk_sh(clk_sh),.rstn(rstn),
        .wr_cmd_data(wr_cmd_data),.wr_cmd_valid(wr_cmd_valid),.wr_cmd_ready(wr_cmd_ready),
        .rd_cmd_data(rd_cmd_data),.rd_cmd_valid(rd_cmd_valid),.rd_cmd_ready(rd_cmd_ready),
        .wdata(s_axis_data),.wdata_valid(s_axis_valid),.wdata_ready(s_axis_ready),
        .rdata(m_axis_data),.rdata_valid(m_axis_valid),.rdata_ready(m_axis_ready),.rdata_level(rdata_level),
        .wdata_level(wdata_level),
        .sdram_addr(sdram_addr),.sdram_ba(sdram_ba),.sdram_cs_n(sdram_cs_n),.sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),.sdram_we_n(sdram_we_n),.sdram_dq(sdram_dq),.sdram_dqm(sdram_dqm),
        .sdram_cke(sdram_cke),.sdram_clk(sdram_clk)
    );


    always_ff @(posedge clk) begin
        if (!rstn) begin
            buf_a_state <= EMPTY; buf_b_state <= EMPTY; write_buf <= BUF_A; read_buf <= BUF_B; first_frame_done <= 1'b0;
        end else begin
            if (swap_buffers_req) begin
                write_buf <= read_buf; read_buf <= write_buf; first_frame_done <= 1'b1;
            end
            case (buf_a_state)
                EMPTY:   if (write_buf == BUF_A) buf_a_state <= FILLING;
                FILLING: if (write_addr_cnt == FRAME_SIZE_WORDS - 1) buf_a_state <= FULL;
                FULL:    if (read_buf == BUF_A && first_frame_done) buf_a_state <= READING;
                READING: if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) buf_a_state <= EMPTY;
            endcase
            case (buf_b_state)
                EMPTY:   if (write_buf == BUF_B) buf_b_state <= FILLING;
                FILLING: if (write_addr_cnt == FRAME_SIZE_WORDS - 1) buf_b_state <= FULL;
                FULL:    if (read_buf == BUF_B && first_frame_done) buf_b_state <= READING;
                READING: if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) buf_b_state <= EMPTY;
            endcase
        end
    end

    assign swap_buffers_req = (write_buf == BUF_A ? (buf_a_state == FULL) : (buf_b_state == FULL)) && (read_buf == BUF_A ? (buf_a_state == EMPTY) : (buf_b_state == EMPTY));

    // --- Write Command Generator ---
    always_comb begin
        logic [ADDR_WIDTH_TOTAL-1:0] base_addr;
        base_addr = (write_buf == BUF_A) ? FRAME_A_BASE_ADDR : FRAME_B_BASE_ADDR;
        wr_full_addr = base_addr + wr_cmd_addr_cnt;
        wr_cmd_data.addr.row  = wr_full_addr[COL_ADDR_WIDTH+BANK_ADDR_WIDTH+:ROW_ADDR_WIDTH];
        wr_cmd_data.addr.bank = wr_full_addr[COL_ADDR_WIDTH+:BANK_ADDR_WIDTH];
        wr_cmd_data.addr.col  = wr_full_addr[0+:COL_ADDR_WIDTH];
        wr_cmd_data.rw        = 1'b1;
        wr_cmd_data.auto_precharge = 1'b0;
        wr_cmd_valid = (wdata_level >= BURST_LEN);
    end

    always_ff @(posedge clk) begin
        if (!rstn) write_addr_cnt <= 'b0;
        else if (swap_buffers_req) write_addr_cnt <= 'b0;
        else if (s_axis_valid && s_axis_ready) begin
            if (write_addr_cnt == FRAME_SIZE_WORDS - 1) write_addr_cnt <= 'b0;
            else write_addr_cnt <= write_addr_cnt + 1;
        end
    end

    always_ff @(posedge clk) begin
        if (!rstn) wr_cmd_addr_cnt <= 'b0;
        else if (swap_buffers_req) wr_cmd_addr_cnt <= 'b0;
        else if (wr_cmd_valid && wr_cmd_ready) begin
            if (wr_cmd_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) wr_cmd_addr_cnt <= 'b0;
            else wr_cmd_addr_cnt <= wr_cmd_addr_cnt + BURST_LEN;
        end
    end

    // --- Read Command Generator ---
    always_comb begin
        logic [ADDR_WIDTH_TOTAL-1:0] base_addr;
        base_addr = (read_buf == BUF_A) ? FRAME_A_BASE_ADDR : FRAME_B_BASE_ADDR;
        rd_full_addr = base_addr + read_addr_cnt;
        rd_cmd_data.addr.row  = rd_full_addr[COL_ADDR_WIDTH+BANK_ADDR_WIDTH+:ROW_ADDR_WIDTH];
        rd_cmd_data.addr.bank = rd_full_addr[COL_ADDR_WIDTH+:BANK_ADDR_WIDTH];
        rd_cmd_data.addr.col  = rd_full_addr[0+:COL_ADDR_WIDTH];
        rd_cmd_data.rw        = 1'b0;
        rd_cmd_data.auto_precharge = 1'b0;
        rd_cmd_valid = first_frame_done && (rdata_level < 32) && (read_addr_cnt < FRAME_SIZE_WORDS - BURST_LEN) && (read_buf == BUF_A ? (buf_a_state == READING) : (buf_b_state == READING));
    end
    always_ff @(posedge clk) begin
        if (!rstn) read_addr_cnt <= 'b0;
        else if (swap_buffers_req) read_addr_cnt <= 'b0;
        else if (rd_cmd_valid && rd_cmd_ready) begin
            if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) read_addr_cnt <= 'b0;
            else read_addr_cnt <= read_addr_cnt + BURST_LEN;
        end
    end

    // >>> FSM #4 (Moore) – m_axis_last generation
    always_ff @(posedge clk) begin
        if (!rstn) begin
            m_axis_x_cnt <= 'b0;
        end else if (m_axis_valid && m_axis_ready) begin
            if (m_axis_x_cnt == FRAME_WIDTH - 1) begin
                m_axis_x_cnt <= 'b0;
            end else begin
                m_axis_x_cnt <= m_axis_x_cnt + 1;
            end
        end
    end
    assign m_axis_last = (m_axis_x_cnt == FRAME_WIDTH - 1);

    assign debug_led_0_o[1:0] = buf_a_state;
    assign debug_led_0_o[3:2] = buf_b_state;
    assign debug_led_0_o[4]   = write_buf;
    assign debug_led_0_o[5]   = read_buf;
    assign debug_led_0_o[6]   = swap_buffers_req;
    assign debug_led_0_o[7]   = first_frame_done;
    assign debug_led_1_o[0] = s_axis_valid;
    assign debug_led_1_o[1] = s_axis_ready;
    assign debug_led_1_o[2] = m_axis_valid;
    assign debug_led_1_o[3] = m_axis_ready;
    assign debug_led_1_o[4] = wr_cmd_valid;
    assign debug_led_1_o[5] = wr_cmd_ready;
    assign debug_led_1_o[6] = rd_cmd_valid;
    assign debug_led_1_o[7] = rd_cmd_ready;
endmodule

`endif // FRAMEBUFFER_PINGPONG_SDRAM_FINAL_SV

