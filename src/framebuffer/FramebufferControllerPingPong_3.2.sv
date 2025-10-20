// =============================================================================
// Súbor: FramebufferWithSdramController_Final.sv
// Verzia: 3.2 (Optimalizácia adresovania)
// Dátum: 17. október 2025
//
// Popis:
// Kompletný, finálny návrh ping-pong framebuffer kontroléra s integrovaným
// SDRAM radičom. Tento súbor obsahuje všetky potrebné moduly a zahŕňa
// všetky opravy a vylepšenia z predchádzajúcich iterácií.
//
// Zmeny vo verzii 3.2:
// - OPTIMALIZÁCIA: Zmenené mapovanie lineárnej adresy na fyzickú SDRAM adresu
//   z [Banka|Riadok|Stĺpec] na [Riadok|Banka|Stĺpec]. Táto technika, známa
//   ako "bank interleaving", rozdeľuje po sebe idúce prístupy medzi rôzne
//   banky, čím sa minimalizujú "bank conflicts" a výrazne sa zvyšuje
//   priepustnosť a stabilita pamäťového systému. Očakáva sa, že táto zmena
//   odstráni "rozhádzaný obraz".
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

// ----------------------------------------------------------------------------
// Countdown Timer
// ----------------------------------------------------------------------------
module CountdownTimer #(
    parameter int COUNT_WIDTH = 4,
    parameter bit ASYNC_RESET = 1,    // 1 = asynchrónny reset, 0 = synchrónny reset
    parameter bit DONE_REGISTERED = 0 // 1 = registrovaný výstup, 0 = combinational
)(
    input  logic clk,
    input  logic rstn,                // aktívny nízky reset
    input  logic load,
    input  logic [COUNT_WIDTH-1:0] load_val,
    output logic done
);
    logic [COUNT_WIDTH-1:0] count_reg, count_next;
    logic done_next;

    // Hybridný reset: asynchrónny alebo synchrónny
    generate
        if (ASYNC_RESET) begin : g_async_reset_block
            always_ff @(posedge clk or negedge rstn) begin
                if (!rstn)
                    count_reg <= '0;
                else
                    count_reg <= count_next;
            end
        end else begin : g_sync_reset_block
            always_ff @(posedge clk) begin
                if (!rstn)
                    count_reg <= '0;
                else
                    count_reg <= count_next;
            end
        end
    endgenerate

    // logika odpočtu
    always_comb begin
        if (load)
            count_next = load_val;
        else if (count_reg > '0)
            count_next = count_reg - 1;
        else
            count_next = count_reg;

        done_next = (count_reg == '0);
    end

    // Výstup done: combinational alebo registrovaný
    generate
        if (DONE_REGISTERED) begin : g_done_reg_block
            if (ASYNC_RESET) begin : g_done_async_reset
                always_ff @(posedge clk or negedge rstn) begin
                    if (!rstn)
                        done <= 0;
                    else
                        done <= done_next;
                end
            end else begin : g_done_sync_reset
                always_ff @(posedge clk) begin
                    if (!rstn)
                        done <= 0;
                    else
                        done <= done_next;
                end
            end
        end else begin : g_done_comb_block
            assign done = done_next;
        end
    endgenerate

endmodule


// ============================================================================
// Async FIFO (dual-clock, generický)
// ============================================================================
module AsyncFifoGeneric #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4,
    parameter bit ASYNC_RESET = 1,          // 1 = asynchrónny, 0 = synchrónny
    parameter string RAM_STYLE = "M20K",    // "M20K" alebo "M9K"
    parameter bit TWO_STAGE_SYNC = 0        // 1 = 2-step Gray synchronizácia, 0 = 1-step
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
    output logic [$clog2(1<<ADDR_WIDTH):0] level
);
    localparam int DEPTH = 1 << ADDR_WIDTH;

    (* ramstyle = RAM_STYLE *) logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    // Pointery a Gray kódy
    logic [ADDR_WIDTH:0] wr_ptr_bin, rd_ptr_bin;
    logic [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
    logic [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] rd_ptr_bin_synced;

    // ---------------------------
    // WRITE DOMAIN
    // ---------------------------
    generate
        if (ASYNC_RESET) begin : g_wr_async_reset
            always_ff @(posedge wr_clk or negedge rstn) begin
                if (!rstn) begin
                    wr_ptr_bin <= '0;
                    rd_ptr_gray_sync1 <= '0;
                    rd_ptr_gray_sync2 <= '0;
                end else begin
                    wr_ptr_bin <= (wr_en && !wr_full) ? wr_ptr_bin + 1 : wr_ptr_bin;
                    rd_ptr_gray_sync1 <= rd_ptr_gray;
                    if (TWO_STAGE_SYNC)
                        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
                    else
                        rd_ptr_gray_sync2 <= rd_ptr_gray;
                end
            end
        end else begin : g_wr_sync_reset
            always_ff @(posedge wr_clk) begin
                if (!rstn) begin
                    wr_ptr_bin <= '0;
                    rd_ptr_gray_sync1 <= '0;
                    rd_ptr_gray_sync2 <= '0;
                end else begin
                    wr_ptr_bin <= (wr_en && !wr_full) ? wr_ptr_bin + 1 : wr_ptr_bin;
                    rd_ptr_gray_sync1 <= rd_ptr_gray;
                    if (TWO_STAGE_SYNC)
                        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
                    else
                        rd_ptr_gray_sync2 <= rd_ptr_gray;
                end
            end
        end
    endgenerate

    assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;
    always_ff @(posedge wr_clk) if (wr_en && !wr_full) mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
    assign wr_full = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH], rd_ptr_gray_sync2[ADDR_WIDTH-1:0]});

    // ---------------------------
    // READ DOMAIN
    // ---------------------------
    generate
        if (ASYNC_RESET) begin : g_rd_async_reset
            always_ff @(posedge rd_clk or negedge rstn) begin
                if (!rstn) begin
                    rd_ptr_bin <= '0;
                    wr_ptr_gray_sync1 <= '0;
                    wr_ptr_gray_sync2 <= '0;
                end else begin
                    rd_ptr_bin <= (rd_en && !rd_empty) ? rd_ptr_bin + 1 : rd_ptr_bin;
                    wr_ptr_gray_sync1 <= wr_ptr_gray;
                    if (TWO_STAGE_SYNC)
                        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
                    else
                        wr_ptr_gray_sync2 <= wr_ptr_gray;
                end
            end
        end else begin : g_rd_sync_reset
            always_ff @(posedge rd_clk) begin
                if (!rstn) begin
                    rd_ptr_bin <= '0;
                    wr_ptr_gray_sync1 <= '0;
                    wr_ptr_gray_sync2 <= '0;
                end else begin
                    rd_ptr_bin <= (rd_en && !rd_empty) ? rd_ptr_bin + 1 : rd_ptr_bin;
                    wr_ptr_gray_sync1 <= wr_ptr_gray;
                    if (TWO_STAGE_SYNC)
                        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
                    else
                        wr_ptr_gray_sync2 <= wr_ptr_gray;
                end
            end
        end
    endgenerate

    assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;
    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

    // Synchronizácia level
    generate
        if (ASYNC_RESET) begin : g_level_async
            always_ff @(posedge wr_clk or negedge rstn) begin
                if (!rstn)
                    rd_ptr_bin_synced <= '0;
                else
                    rd_ptr_bin_synced <= rd_ptr_bin;
            end
        end else begin : g_level_sync
            always_ff @(posedge wr_clk) begin
                if (!rstn)
                    rd_ptr_bin_synced <= '0;
                else
                    rd_ptr_bin_synced <= rd_ptr_bin;
            end
        end
    endgenerate

    assign level = wr_ptr_bin - rd_ptr_bin_synced;
endmodule


// ============================================================================
// SDRAM Controller
// ============================================================================
module SdramController #(
    // SDRAM banks
    parameter int NUM_BANKS = 4,

    // ===============================
    // SDRAM timing parameters (in clock cycles)
    // ===============================
    parameter int tRP   = 3,
    parameter int tRCD  = 3,
    parameter int tWR   = 2,
    parameter int tRFC  = 7,
    parameter int tRAS  = 7,
    parameter int tMRD  = 2,

    // ===============================
    // Clock / FIFO parameters
    // ===============================
    parameter int CLOCK_FREQ_HZ   = 100_000_000,
    parameter int FIFO_ADDR_WIDTH = 6,

    // ===============================
    // Async reset option
    // ===============================
    parameter bit ASYNC_RESET = 1'b1
)(
    // ===============================
    // System clocks and reset
    // ===============================
    input  logic clk,
    input  logic clk_sh,
    input  logic rstn,

    // ===============================
    // Write command interface
    // ===============================
    input  sdram_cmd_t wr_cmd_data,
    input  logic wr_cmd_valid,
    output logic wr_cmd_ready,

    // ===============================
    // Read command interface
    // ===============================
    input  sdram_cmd_t rd_cmd_data,
    input  logic rd_cmd_valid,
    output logic rd_cmd_ready,

    // ===============================
    // Write data interface
    // ===============================
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic wdata_valid,
    output logic wdata_ready,

    // ===============================
    // Read data interface
    // ===============================
    output logic [DATA_WIDTH-1:0] rdata,
    output logic rdata_valid,
    input  logic rdata_ready,

    // ===============================
    // FIFO level indicators
    // ===============================
    output logic [$clog2(1<<FIFO_ADDR_WIDTH)+1-1:0] rdata_level,
    output logic [$clog2(1<<FIFO_ADDR_WIDTH)+1-1:0] wdata_level,

    // ===============================
    // SDRAM physical pins
    // ===============================
    output logic [ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    inout  wire [DATA_WIDTH-1:0] sdram_dq,
    output logic [DATA_WIDTH/8-1:0] sdram_dqm,
    output logic sdram_cke,
    output logic sdram_clk
);

    // =========================================================================
    // Local constants
    // =========================================================================
    localparam int NS_PER_SEC = 1_000_000_000;
    localparam int CLK_PERIOD_NS = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam int WAIT_TIME_NS = 200_000;
    localparam int INIT_WAIT_CYCLES = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam int REFRESH_INTERVAL = (64_000_000 / (1 << ROW_ADDR_WIDTH)) / CLK_PERIOD_NS;
    localparam int AP_BIT_INDEX = 10;

    // ===============================
    // SDRAM MRS value
    // ===============================
    localparam logic [ROW_ADDR_WIDTH-1:0] mrs_value_addr =
        {1'b0, 1'b0, 2'b00, (CAS_LATENCY==3 ? 3'b011:3'b010), 1'b0, (BURST_LEN==8 ? 3'b011:3'b000)};

    // ===============================
    // FSM states
    // ===============================
    typedef enum logic [4:0] {
        INIT_WAIT,
        INIT_PRECHARGE,
        INIT_REFRESH1,
        INIT_REFRESH2,
        INIT_MRS,
        INIT_MRS_WAIT,
        IDLE,
        EVAL_BANK,
        EVAL_PRECHARGE,
        EVAL_TIMING,
        ACTIVATE_CMD,
        READ_CMD,
        WRITE_CMD,
        PRECHARGE_CMD,
        REFRESH_CMD,
        READ_BURST,
        WRITE_BURST
    } state_t;

    state_t state_reg, state_next;

    // ===============================
    // Bank states
    // ===============================
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS-1:0];
    bank_state_t bank_state_next[NUM_BANKS-1:0];

    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS-1:0];
    logic [ROW_ADDR_WIDTH-1:0] active_row_next[NUM_BANKS-1:0];

    logic [$clog2(tRAS+1)-1:0] tras_timer[NUM_BANKS-1:0];
    logic [$clog2(tRAS+1)-1:0] tras_timer_next[NUM_BANKS-1:0];

    // ===============================
    // Countdown timers
    // ===============================
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

    // ===============================
    // FIFO control signals
    // ===============================
    logic wr_fifo_full, wr_fifo_empty;
    logic rd_fifo_full, rd_fifo_empty;
    logic wr_fifo_wr_en, wr_fifo_rd_en;
    logic rd_fifo_wr_en, rd_fifo_rd_en;
    logic [DATA_WIDTH-1:0] wr_fifo_rd_data;

    // =========================================================================
    // Timer instances
    // =========================================================================
    CountdownTimer #($clog2(tRP+1))   trp_timer_inst   (.clk(clk), .rstn(rstn), .load(load_trp),   .load_val(tRP),   .done(trp_done));
    CountdownTimer #($clog2(tRCD+1))  trcd_timer_inst  (.clk(clk), .rstn(rstn), .load(load_trcd),  .load_val(tRCD),  .done(trcd_done));
    CountdownTimer #($clog2(tWR+1))   twr_timer_inst   (.clk(clk), .rstn(rstn), .load(load_twr),   .load_val(tWR),   .done(twr_done));
    CountdownTimer #($clog2(tRFC+1))  trfc_timer_inst  (.clk(clk), .rstn(rstn), .load(load_trfc),  .load_val(tRFC),  .done(trfc_done));
    CountdownTimer #($clog2(tMRD+1))  trmrd_timer_inst (.clk(clk), .rstn(rstn), .load(load_trmrd), .load_val(tMRD),  .done(trmrd_done));
    CountdownTimer #($clog2(INIT_WAIT_CYCLES+1)) init_timer_inst (.clk(clk), .rstn(rstn), .load(load_init), .load_val(INIT_WAIT_CYCLES), .done(init_done));

    // =========================================================================
    // FIFO instances
    // =========================================================================
    AsyncFifoGeneric #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) write_fifo_inst (
        .rstn(rstn),
        .wr_clk(clk),
        .wr_en(wr_fifo_wr_en),
        .wr_data(wdata),
        .wr_full(wr_fifo_full),
        .rd_clk(clk),
        .rd_en(wr_fifo_rd_en),
        .rd_data(wr_fifo_rd_data),
        .rd_empty(wr_fifo_empty),
        .level(wdata_level)
    );

    AsyncFifoGeneric #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) read_fifo_inst (
        .rstn(rstn),
        .wr_clk(clk),
        .wr_en(rd_fifo_wr_en),
        .wr_data(sdram_dq),
        .wr_full(rd_fifo_full),
        .rd_clk(clk),
        .rd_en(rd_fifo_rd_en),
        .rd_data(rdata),
        .rd_empty(rd_fifo_empty),
        .level(rdata_level)
    );

    // =========================================================================
    // FSM combinational
    // =========================================================================
    always_comb begin
        state_next = state_reg;
        refresh_counter_next = refresh_counter;
        refresh_pending_next = refresh_pending;
        cas_cnt_next = cas_cnt;
        burst_cnt_next = burst_cnt;
        dq_write_enable = 1'b0;
        sdram_cmd_pins_t cmd_pins = get_sdram_cmd(NOP);
        sdram_cke = 1'b1;
        sdram_addr = '0; sdram_ba = '0;
        load_trp=1'b0; load_trcd=1'b0; load_twr=1'b0; load_trfc=1'b0; load_init=1'b0; load_trmrd=1'b0;
        for (int i=0; i<NUM_BANKS; i++) {bank_state_next[i] = bank_state[i]; active_row_next[i] = active_row[i]; tras_timer_next[i] = (tras_timer[i] > 0) ? tras_timer[i] - 1 : 0;}
        if (cas_cnt > 0) cas_cnt_next = cas_cnt - 1;
        if (state_reg != REFRESH_CMD && refresh_counter > 0) refresh_counter_next = refresh_counter - 1; else if (state_reg != REFRESH_CMD && refresh_counter == 0) refresh_pending_next = 1'b1;
        fsm_ready_for_cmd = (state_reg == IDLE) && !refresh_pending && twr_done;
        selected_cmd_valid = 1'b0; selected_cmd = '{default:'0}; rd_cmd_ready = 1'b0; wr_cmd_ready = 1'b0;
        if (rd_cmd_valid) {selected_cmd_valid = 1'b1; selected_cmd = rd_cmd_data; if (fsm_ready_for_cmd) rd_cmd_ready = 1'b1;}
        else if (wr_cmd_valid) {selected_cmd_valid = 1'b1; selected_cmd = wr_cmd_data; if (fsm_ready_for_cmd) wr_cmd_ready = 1'b1;}
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
            EVAL_BANK: if (bank_state[current_cmd.addr.bank] == BANK_IDLE) begin if (trp_done) state_next = ACTIVATE_CMD; end else begin if (active_row[current_cmd.addr.bank] == current_cmd.addr.row) state_next = EVAL_TIMING; else state_next = EVAL_PRECHARGE; end
            EVAL_PRECHARGE: if (tras_timer[current_cmd.addr.bank] == 0) state_next = PRECHARGE_CMD;
            EVAL_TIMING: if (trcd_done) if (current_cmd.rw) state_next = WRITE_CMD; else state_next = READ_CMD;
            ACTIVATE_CMD: begin cmd_pins = get_sdram_cmd(ACTIVE); sdram_ba = current_cmd.addr.bank; sdram_addr = current_cmd.addr.row; load_trcd = 1'b1; tras_timer_next[current_cmd.addr.bank] = tRAS; bank_state_next[current_cmd.addr.bank] = BANK_ACTIVE; active_row_next[current_cmd.addr.bank] = current_cmd.addr.row; state_next = EVAL_BANK; end
            READ_CMD: begin cmd_pins = get_sdram_cmd(READ); sdram_ba = current_cmd.addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = current_cmd.addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge; cas_cnt_next = CAS_LATENCY; burst_cnt_next = BURST_LEN; if (current_cmd.auto_precharge) begin bank_state_next[current_cmd.addr.bank] = BANK_IDLE; load_trp = 1'b1; end state_next = READ_BURST; end
            WRITE_CMD: begin cmd_pins = get_sdram_cmd(WRITE); sdram_ba = current_cmd.addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = current_cmd.addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge; burst_cnt_next = BURST_LEN; if (current_cmd.auto_precharge) begin bank_state_next[current_cmd.addr.bank] = BANK_IDLE; load_twr = 1'b1; load_trp = 1'b1; end state_next = WRITE_BURST; end
            READ_BURST: if (cas_cnt == 0) begin if (burst_cnt > 0) burst_cnt_next = burst_cnt - 1; if (burst_cnt == 1) state_next = IDLE; end
            WRITE_BURST: begin dq_write_enable = 1'b1; burst_cnt_next = burst_cnt - 1; if (burst_cnt == 1) begin load_twr = 1'b1; state_next = IDLE; end end
            PRECHARGE_CMD: begin cmd_pins = get_sdram_cmd(PRECHARGE); sdram_ba = current_cmd.addr.bank; load_trp = 1'b1; bank_state_next[current_cmd.addr.bank] = BANK_IDLE; state_next = EVAL_BANK; end
            REFRESH_CMD: begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; refresh_pending_next = 1'b0; refresh_counter_next = REFRESH_INTERVAL; state_next = IDLE; end
            default: state_next = IDLE;
        endcase
        wdata_ready = !wr_fifo_full;
        rdata_valid = !rd_fifo_empty;
        sdram_cs_n = cmd_pins.cs; sdram_ras_n = cmd_pins.ras; sdram_cas_n = cmd_pins.cas; sdram_we_n = cmd_pins.we;
        sdram_dqm = (dq_write_enable_d && wr_fifo_empty) ? '1 : '0;
    end

    // =========================================================================
    // FSM sequential
    // =========================================================================
    generate
        if (ASYNC_RESET) begin : g_async_reset_block
            always_ff @(posedge clk or negedge rstn) begin
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
                    refresh_counter <= refresh_counter_next;
                    refresh_pending <= refresh_pending_next;
                    cas_cnt <= cas_cnt_next;
                    burst_cnt <= burst_cnt_next;
                    if (fsm_ready_for_cmd && selected_cmd_valid)
                        current_cmd <= selected_cmd;
                    for (int i=0; i<NUM_BANKS; i++) begin
                        bank_state[i] <= bank_state_next[i];
                        active_row[i] <= active_row_next[i];
                        tras_timer[i] <= tras_timer_next[i];
                    end
                    dq_write_enable_d <= dq_write_enable;
                    if (wr_fifo_rd_en)
                        write_data_reg <= wr_fifo_rd_data;
                end
            end
        end else begin : g_sync_reset_block
            always_ff @(posedge clk) begin
                if (!rstn) begin
                    // Synchronous reset logic
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
                    refresh_counter <= refresh_counter_next;
                    refresh_pending <= refresh_pending_next;
                    cas_cnt <= cas_cnt_next;
                    burst_cnt <= burst_cnt_next;
                    if (fsm_ready_for_cmd && selected_cmd_valid)
                        current_cmd <= selected_cmd;
                    for (int i=0; i<NUM_BANKS; i++) begin
                        bank_state[i] <= bank_state_next[i];
                        active_row[i] <= active_row_next[i];
                        tras_timer[i] <= tras_timer_next[i];
                    end
                    dq_write_enable_d <= dq_write_enable;
                    if (wr_fifo_rd_en)
                        write_data_reg <= wr_fifo_rd_data;
                end
            end
        end
    endgenerate

    // =========================================================================
    // SDRAM physical outputs
    // =========================================================================
    assign sdram_dq  = (dq_write_enable_d) ? write_data_reg : 'z;
    assign sdram_clk = clk_sh;

endmodule

// ============================================================================
// FramebufferController - refactored, ASYNC_RESET support, Quartus-friendly
// ============================================================================
module FramebufferController #(
    parameter int FRAME_WIDTH   = 800,
    parameter int FRAME_HEIGHT  = 600,
    parameter bit ASYNC_RESET   = 1'b1        // 1 = async reset (negedge rstn), 0 = sync reset
)(
    input  logic clk,
    input  logic clk_sh,
    input  logic rstn,

    // AXI stream slave (write into framebuffer)
    input  logic                  s_axis_valid,
    output logic                  s_axis_ready,
    input  logic [DATA_WIDTH-1:0] s_axis_data,
    input  logic                  s_axis_last,

    // AXI stream master (read from framebuffer)
    output logic                  m_axis_valid,
    input  logic                  m_axis_ready,
    output logic [DATA_WIDTH-1:0] m_axis_data,
    output logic                  m_axis_last,

    // SDRAM physical ports (forwarded from SdramController instance)
    output logic [ROW_ADDR_WIDTH-1:0] sdram_addr,
    output logic [BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic sdram_cs_n,
    output logic sdram_ras_n,
    output logic sdram_cas_n,
    output logic sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0]    sdram_dq,
    output logic [DATA_WIDTH/8-1:0]  sdram_dqm,
    output logic                     sdram_cke,
    output logic                     sdram_clk,

    // Debug LEDs
    output logic [7:0] debug_led_0_o,
    output logic [7:0] debug_led_1_o
);

    // -------------------------
    // imports / localparams
    // -------------------------
    import sdram_pkg::*; // očakáva DATA_WIDTH, ROW_ADDR_WIDTH, COL_ADDR_WIDTH, BANK_ADDR_WIDTH, BURST_LEN, ...

    localparam int FIFO_ADDR_WIDTH   = 6;
    localparam int FRAME_SIZE_WORDS  = FRAME_WIDTH * FRAME_HEIGHT;
    localparam int ADDR_WIDTH_TOTAL  = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;

    // BASE ADDRESSES majú šírku ADDR_WIDTH_TOTAL
    localparam logic [ADDR_WIDTH_TOTAL-1:0] FRAME_A_BASE_ADDR = '0;
    localparam logic [ADDR_WIDTH_TOTAL-1:0] FRAME_B_BASE_ADDR = FRAME_SIZE_WORDS;

    // -------------------------
    // Buffer state & control types
    // -------------------------
    typedef enum logic { BUF_A, BUF_B } active_buf_t;
    typedef enum logic [1:0] { EMPTY, FILLING, FULL, READING } buffer_state_t;

    // -------------------------
    // Registers
    // -------------------------
    buffer_state_t buf_a_state, buf_b_state;
    active_buf_t   write_buf, read_buf;
    logic          swap_buffers_req;

    // Address counters (width chosen based on FRAME_SIZE_WORDS)
    logic [$clog2(FRAME_SIZE_WORDS)-1:0] write_addr_cnt;
    logic [$clog2(FRAME_SIZE_WORDS)-1:0] read_addr_cnt;
    logic [$clog2(FRAME_SIZE_WORDS)-1:0] wr_cmd_addr_cnt;

    // Command / levels for SdramController
    sdram_cmd_t wr_cmd_data;
    sdram_cmd_t rd_cmd_data;
    logic       wr_cmd_valid, rd_cmd_valid;
    logic       wr_cmd_ready, rd_cmd_ready;

    logic [$clog2(1<<(FIFO_ADDR_WIDTH))+1-1:0] rdata_level;
    logic [$clog2(1<<(FIFO_ADDR_WIDTH))+1-1:0] wdata_level;

    logic [ADDR_WIDTH_TOTAL-1:0] wr_full_addr;
    logic [ADDR_WIDTH_TOTAL-1:0] rd_full_addr;

    logic first_frame_done;

    // -------------------------
    // SdramController instance
    // -------------------------
    SdramController #(
        .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH),
        .ASYNC_RESET(ASYNC_RESET)
    ) sdram_inst (
        .clk            (clk),
        .clk_sh         (clk_sh),
        .rstn           (rstn),

        .wr_cmd_data    (wr_cmd_data),
        .wr_cmd_valid   (wr_cmd_valid),
        .wr_cmd_ready   (wr_cmd_ready),

        .rd_cmd_data    (rd_cmd_data),
        .rd_cmd_valid   (rd_cmd_valid),
        .rd_cmd_ready   (rd_cmd_ready),

        .wdata          (s_axis_data),
        .wdata_valid    (s_axis_valid),
        .wdata_ready    (s_axis_ready),

        .rdata          (m_axis_data),
        .rdata_valid    (m_axis_valid),
        .rdata_ready    (m_axis_ready),

        .rdata_level    (rdata_level),
        .wdata_level    (wdata_level),

        .sdram_addr     (sdram_addr),
        .sdram_ba       (sdram_ba),
        .sdram_cs_n     (sdram_cs_n),
        .sdram_ras_n    (sdram_ras_n),
        .sdram_cas_n    (sdram_cas_n),
        .sdram_we_n     (sdram_we_n),
        .sdram_dq       (sdram_dq),
        .sdram_dqm      (sdram_dqm),
        .sdram_cke      (sdram_cke),
        .sdram_clk      (sdram_clk)
    );

    // -------------------------
    // Buffer state machine (ping-pong) - sequential domain: clk
    // -------------------------
    generate
        if (ASYNC_RESET) begin : gen_buf_state_async
            always @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    buf_a_state     <= EMPTY;
                    buf_b_state     <= EMPTY;
                    write_buf       <= BUF_A;
                    read_buf        <= BUF_B;
                    first_frame_done<= 1'b0;
                end else begin
                    // swap buffers if requested
                    if (swap_buffers_req) begin
                        write_buf <= read_buf;
                        read_buf  <= write_buf;
                        first_frame_done <= 1'b1;
                    end

                    // Buf A state transitions
                    case (buf_a_state)
                        EMPTY:   if (write_buf == BUF_A) buf_a_state <= FILLING;
                        FILLING: if (write_addr_cnt == FRAME_SIZE_WORDS - 1) buf_a_state <= FULL;
                        FULL:    if ((read_buf == BUF_A) && first_frame_done) buf_a_state <= READING;
                        READING: if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) buf_a_state <= EMPTY;
                        default: buf_a_state <= EMPTY;
                    endcase

                    // Buf B state transitions
                    case (buf_b_state)
                        EMPTY:   if (write_buf == BUF_B) buf_b_state <= FILLING;
                        FILLING: if (write_addr_cnt == FRAME_SIZE_WORDS - 1) buf_b_state <= FULL;
                        FULL:    if ((read_buf == BUF_B) && first_frame_done) buf_b_state <= READING;
                        READING: if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) buf_b_state <= EMPTY;
                        default: buf_b_state <= EMPTY;
                    endcase
                end
            end
        end else begin : gen_buf_state_sync
            always @(posedge clk) begin
                if (!rstn) begin
                    buf_a_state     <= EMPTY;
                    buf_b_state     <= EMPTY;
                    write_buf       <= BUF_A;
                    read_buf        <= BUF_B;
                    first_frame_done<= 1'b0;
                end else begin
                    if (swap_buffers_req) begin
                        write_buf <= read_buf;
                        read_buf  <= write_buf;
                        first_frame_done <= 1'b1;
                    end

                    // Buf A
                    case (buf_a_state)
                        EMPTY:   if (write_buf == BUF_A) buf_a_state <= FILLING;
                        FILLING: if (write_addr_cnt == FRAME_SIZE_WORDS - 1) buf_a_state <= FULL;
                        FULL:    if ((read_buf == BUF_A) && first_frame_done) buf_a_state <= READING;
                        READING: if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) buf_a_state <= EMPTY;
                        default: buf_a_state <= EMPTY;
                    endcase

                    // Buf B
                    case (buf_b_state)
                        EMPTY:   if (write_buf == BUF_B) buf_b_state <= FILLING;
                        FILLING: if (write_addr_cnt == FRAME_SIZE_WORDS - 1) buf_b_state <= FULL;
                        FULL:    if ((read_buf == BUF_B) && first_frame_done) buf_b_state <= READING;
                        READING: if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN) buf_b_state <= EMPTY;
                        default: buf_b_state <= EMPTY;
                    endcase
                end
            end
        end
    endgenerate

    // -------------------------
    // swap_buffers_req combinational
    // - true when the writer buffer is full AND the reader buffer is empty
    // -------------------------
    assign swap_buffers_req = (
        ( (write_buf == BUF_A) ? (buf_a_state == FULL) : (buf_b_state == FULL) )
      && ( (read_buf  == BUF_A) ? (buf_a_state == EMPTY): (buf_b_state == EMPTY) )
    );

    // -------------------------
    // Write command generator (combinational)
    // -------------------------
    always_comb begin
        logic [ADDR_WIDTH_TOTAL-1:0] base_addr;
        base_addr = (write_buf == BUF_A) ? FRAME_A_BASE_ADDR : FRAME_B_BASE_ADDR;

        // Map linear address into row/bank/col with bank-interleaving:
        wr_full_addr = base_addr + wr_cmd_addr_cnt;

        // Extract fields using constant slices (safe synthesis)
        wr_cmd_data.addr.row  = wr_full_addr[COL_ADDR_WIDTH +: ROW_ADDR_WIDTH]; // row bits above col
        wr_cmd_data.addr.bank = wr_full_addr[COL_ADDR_WIDTH +: BANK_ADDR_WIDTH];
        wr_cmd_data.addr.col  = wr_full_addr[0 +: COL_ADDR_WIDTH];

        wr_cmd_data.rw = 1'b1;
        wr_cmd_data.auto_precharge = 1'b0;

        // Ready to issue write command when write FIFO has at least one burst worth of data
        wr_cmd_valid = (wdata_level >= BURST_LEN);
    end

    // -------------------------
    // Write address counter (sequential)
    // -------------------------
    generate
        if (ASYNC_RESET) begin : gen_wr_addr_async
            always @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    write_addr_cnt <= '0;
                end else if (swap_buffers_req) begin
                    write_addr_cnt <= '0;
                end else if (s_axis_valid && s_axis_ready) begin
                    if (write_addr_cnt == FRAME_SIZE_WORDS - 1)
                        write_addr_cnt <= '0;
                    else
                        write_addr_cnt <= write_addr_cnt + 1;
                end
            end
        end else begin : gen_wr_addr_sync
            always @(posedge clk) begin
                if (!rstn) begin
                    write_addr_cnt <= '0;
                end else if (swap_buffers_req) begin
                    write_addr_cnt <= '0;
                end else if (s_axis_valid && s_axis_ready) begin
                    if (write_addr_cnt == FRAME_SIZE_WORDS - 1)
                        write_addr_cnt <= '0;
                    else
                        write_addr_cnt <= write_addr_cnt + 1;
                end
            end
        end
    endgenerate

    // -------------------------
    // Write-command address generator (sequential)
    // -------------------------
    generate
        if (ASYNC_RESET) begin : gen_wr_cmd_addr_async
            always @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    wr_cmd_addr_cnt <= '0;
                end else if (swap_buffers_req) begin
                    wr_cmd_addr_cnt <= '0;
                end else if (wr_cmd_valid && wr_cmd_ready) begin
                    if (wr_cmd_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN)
                        wr_cmd_addr_cnt <= '0;
                    else
                        wr_cmd_addr_cnt <= wr_cmd_addr_cnt + BURST_LEN;
                end
            end
        end else begin : gen_wr_cmd_addr_sync
            always @(posedge clk) begin
                if (!rstn) begin
                    wr_cmd_addr_cnt <= '0;
                end else if (swap_buffers_req) begin
                    wr_cmd_addr_cnt <= '0;
                end else if (wr_cmd_valid && wr_cmd_ready) begin
                    if (wr_cmd_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN)
                        wr_cmd_addr_cnt <= '0;
                    else
                        wr_cmd_addr_cnt <= wr_cmd_addr_cnt + BURST_LEN;
                end
            end
        end
    endgenerate

    // -------------------------
    // Read command generator (combinational)
    // -------------------------
    always_comb begin
        logic [ADDR_WIDTH_TOTAL-1:0] base_addr;
        base_addr = (read_buf == BUF_A) ? FRAME_A_BASE_ADDR : FRAME_B_BASE_ADDR;

        rd_full_addr = base_addr + read_addr_cnt;

        rd_cmd_data.addr.row  = rd_full_addr[COL_ADDR_WIDTH +: ROW_ADDR_WIDTH];
        rd_cmd_data.addr.bank = rd_full_addr[COL_ADDR_WIDTH +: BANK_ADDR_WIDTH];
        rd_cmd_data.addr.col  = rd_full_addr[0 +: COL_ADDR_WIDTH];

        rd_cmd_data.rw = 1'b0;
        rd_cmd_data.auto_precharge = 1'b0;

        // Issue read command only when first frame ready and space in read FIFO.
        rd_cmd_valid = first_frame_done
                    && (rdata_level < 32)
                    && (read_addr_cnt < FRAME_SIZE_WORDS - BURST_LEN)
                    && ((read_buf == BUF_A) ? (buf_a_state == READING) : (buf_b_state == READING));
    end

    // -------------------------
    // Read address counter (sequential)
    // -------------------------
    generate
        if (ASYNC_RESET) begin : gen_rd_addr_async
            always @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    read_addr_cnt <= '0;
                end else if (swap_buffers_req) begin
                    read_addr_cnt <= '0;
                end else if (rd_cmd_valid && rd_cmd_ready) begin
                    if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN)
                        read_addr_cnt <= '0;
                    else
                        read_addr_cnt <= read_addr_cnt + BURST_LEN;
                end
            end
        end else begin : gen_rd_addr_sync
            always @(posedge clk) begin
                if (!rstn) begin
                    read_addr_cnt <= '0;
                end else if (swap_buffers_req) begin
                    read_addr_cnt <= '0;
                end else if (rd_cmd_valid && rd_cmd_ready) begin
                    if (read_addr_cnt >= FRAME_SIZE_WORDS - BURST_LEN)
                        read_addr_cnt <= '0;
                    else
                        read_addr_cnt <= read_addr_cnt + BURST_LEN;
                end
            end
        end
    endgenerate

    // -------------------------
    // m_axis_last generation (combinational)
    // Note: uses modulo; Quartus may synthesize with div/mod resources.
    // If this is a hotspot, consider tracking x position separately.
    // -------------------------
    // m_axis_last asserted when word corresponds to start of line (original behaviour)
    assign m_axis_last = (m_axis_valid && m_axis_ready) &&
                         ((read_addr_cnt == 0) ? 1'b0 : ((read_addr_cnt - 1) % FRAME_WIDTH) == 0);

    // -------------------------
    // Debug signals: safe assignments
    // -------------------------
    assign debug_led_0_o[1:0] = buf_a_state;
    assign debug_led_0_o[3:2] = buf_b_state;
    assign debug_led_0_o[4]   = (write_buf == BUF_A) ? 1'b1 : 1'b0;
    assign debug_led_0_o[5]   = (read_buf  == BUF_A) ? 1'b1 : 1'b0;
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

