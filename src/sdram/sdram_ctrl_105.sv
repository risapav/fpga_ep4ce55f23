// sdram_controller_final.sv - Verzia 10.36 - Final Data Path Pipeline Fix
//
// Zmeny (v10.36) - Definitívna oprava zaseknutia (Deadlock):
// 1. ROBUSTNOSŤ (Pipeline Fix): Bola opravená kritická chyba v časovaní
//    zapisovacej dátovej cesty. Do `always_ff` bloku bola pridaná `else if`
//    podmienka, ktorá zaručuje, že sa `write_dqm_reg` správne nastaví na '1'
//    (maskovanie), ak sa počas `WRITE_BURST` minú dáta vo FIFO.
//
// Zmeny (v10.35):
// 1. Predchádzajúci pokus o opravu pipeline.

`ifndef SDRAM_CTRL_FINAL_SV
`define SDRAM_CTRL_FINAL_SV

(* default_nettype = "none" *)

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

    import sdram_pkg::*;

    localparam integer FIFO_DEPTH_BITS    = 4;
    localparam integer FIFO_DEPTH         = 1 << FIFO_DEPTH_BITS;
    localparam integer NUM_BANKS          = 2**BANK_ADDR_WIDTH;
    localparam integer NS_PER_SEC         = 1_000_000_000;
    localparam integer CLK_PERIOD_NS      = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam integer WAIT_TIME_NS       = 200_000;
    localparam integer INIT_WAIT_CYCLES   = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam integer REFRESH_INTERVAL   = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam integer URGENT_REFRESH_MULTIPLIER = 2;
    localparam integer URGENT_REFRESH_CYCLES = REFRESH_INTERVAL * URGENT_REFRESH_MULTIPLIER;
    localparam logic [2:0] burst_len_bits = (BURST_LEN == 1) ? 3'b000 : (BURST_LEN == 2) ? 3'b001 :
                                          (BURST_LEN == 4) ? 3'b010 : (BURST_LEN == 8) ? 3'b011 : 3'b111;
    localparam logic [2:0] cas_latency_bits = (CAS_LATENCY == 2) ? 3'b010 : (CAS_LATENCY == 3) ? 3'b011 : 3'b000;
    localparam logic [ROW_ADDR_WIDTH-1:0] mrs_value_addr = {1'b0, 1'b0, 2'b00, cas_latency_bits, 1'b0, burst_len_bits};
    localparam integer AP_BIT_INDEX = 10;

    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS,
        IDLE,
        EVAL_BANK, EVAL_PRECHARGE, EVAL_TIMING,
        ACTIVATE_CMD, READ_CMD, WRITE_CMD,
        PRECHARGE_CMD, REFRESH_CMD, READ_BURST, WRITE_BURST
    } state_t;

    state_t state_reg, state_next;
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS-1:0], bank_state_next[NUM_BANKS-1:0];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS-1:0], active_row_next[NUM_BANKS-1:0];
    logic [$clog2(tRAS+1)-1:0]  tras_timer[NUM_BANKS-1:0], tras_timer_next[NUM_BANKS-1:0];
    logic [$clog2(INIT_WAIT_CYCLES+1)-1:0]   init_timer, init_timer_next;
    logic [$clog2(tRCD+1)-1:0]  trcd_timer, trcd_timer_next;
    logic [$clog2(tRP+1)-1:0]   trp_timer, trp_timer_next;
    logic [$clog2(tWR+1)-1:0]   twr_timer, twr_timer_next;
    logic [$clog2(tRFC+1)-1:0]  trfc_timer, trfc_timer_next;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0]   refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;
    logic [$clog2(URGENT_REFRESH_CYCLES+1)-1:0] urgent_refresh_counter, urgent_refresh_counter_next;
    logic urgent_refresh_req, urgent_refresh_req_next;
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

    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            init_timer <= INIT_WAIT_CYCLES;
            trcd_timer <= '0;
            trp_timer <= '0;
            twr_timer <= '0;
            trfc_timer <= '0;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            urgent_refresh_counter <= URGENT_REFRESH_CYCLES;
            urgent_refresh_req <= 1'b0;
            cas_cnt <= '0;
            burst_cnt <= '0;
            current_cmd <= '0;
            fifo_r_wptr <= '0;
            fifo_r_rptr <= '0;
            fifo_r_count <= '0;
            fifo_w_wptr <= '0;
            fifo_w_rptr <= '0;
            fifo_w_count <= '0;
            for (int i=0; i < NUM_BANKS; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
                tras_timer[i] <= '0;
            end
        end else begin
            state_reg       <= state_next;
            init_timer      <= init_timer_next;
            trcd_timer      <= trcd_timer_next;
            trp_timer       <= trp_timer_next;
            twr_timer       <= twr_timer_next;
            trfc_timer      <= trfc_timer_next;
            refresh_counter <= refresh_counter_next;
            refresh_pending <= refresh_pending_next;
            urgent_refresh_counter <= urgent_refresh_counter_next;
            urgent_refresh_req     <= urgent_refresh_req_next;
            cas_cnt         <= cas_cnt_next;
            burst_cnt       <= burst_cnt_next;
            current_cmd     <= current_cmd_next;
            fifo_r_wptr     <= fifo_r_wptr_next;
            fifo_r_rptr     <= fifo_r_rptr_next;
            fifo_r_count    <= fifo_r_count_next;
            fifo_w_wptr     <= fifo_w_wptr_next;
            fifo_w_rptr     <= fifo_w_rptr_next;
            fifo_w_count    <= fifo_w_count_next;
            for (int i=0; i < NUM_BANKS; i++) begin
                bank_state[i] <= bank_state_next[i];
                active_row[i] <= active_row_next[i];
                tras_timer[i] <= tras_timer_next[i];
            end
        end
        dq_write_enable_d <= dq_write_enable;

        if (do_write_fifo_read) begin
            write_data_reg <= write_fifo_data[fifo_w_rptr];
            write_dqm_reg  <= write_fifo_dqm[fifo_w_rptr];
        end else if (state_reg == WRITE_BURST) begin
            write_dqm_reg <= '1;
        end
    end

    always_comb begin
        sdram_addr_t cmd_addr;
        logic fifo_r_full, fifo_r_empty;
        logic fifo_r_wr_en, fifo_r_rd_en;
        logic do_read_fifo_write;
        logic do_read_fifo_read;
        logic fifo_w_full, fifo_w_empty;
        logic fifo_w_wr_en;
        logic do_write_fifo_write;

        state_next          = state_reg;
        init_timer_next     = init_timer;
        trcd_timer_next     = trcd_timer;
        trp_timer_next      = trp_timer;
        twr_timer_next      = twr_timer;
        trfc_timer_next     = trfc_timer;
        refresh_counter_next= refresh_counter;
        refresh_pending_next= refresh_pending;
        urgent_refresh_counter_next = urgent_refresh_counter;
        urgent_refresh_req_next = urgent_refresh_req;
        cas_cnt_next        = cas_cnt;
        burst_cnt_next      = burst_cnt;
        current_cmd_next    = current_cmd;
        fifo_r_wptr_next    = fifo_r_wptr;
        fifo_r_rptr_next    = fifo_r_rptr;
        fifo_r_count_next   = fifo_r_count;
        fifo_w_wptr_next    = fifo_w_wptr;
        fifo_w_rptr_next    = fifo_w_rptr;
        fifo_w_count_next   = fifo_w_count;
        for (int i=0; i<NUM_BANKS; i++) begin
            bank_state_next[i] = bank_state[i];
            active_row_next[i] = active_row[i];
            tras_timer_next[i] = tras_timer[i];
        end

        cmd_addr = sdram_addr_t'(current_cmd.addr);
        cmd_fifo_ready  = 1'b0;
        dq_write_enable = 1'b0;
        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1; sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_addr = '0; sdram_ba = '0; sdram_dqm = '0; sdram_cke = 1'b1;

        if (init_timer > 0) init_timer_next = init_timer - 1;
        if (trcd_timer > 0) trcd_timer_next = trcd_timer - 1;
        if (trp_timer > 0)  trp_timer_next  = trp_timer - 1;
        if (twr_timer > 0)  twr_timer_next  = twr_timer - 1;
        if (trfc_timer > 0) trfc_timer_next = trfc_timer - 1;
        if (cas_cnt > 0)    cas_cnt_next    = cas_cnt - 1;
        for (int i=0; i<NUM_BANKS; i++)
            if(tras_timer[i] > 0) tras_timer_next[i] = tras_timer[i] - 1;

        if (state_reg != REFRESH_CMD) begin
            if (refresh_counter == 0) refresh_pending_next = 1'b1;
            else refresh_counter_next = refresh_counter - 1;

            if (urgent_refresh_counter > 0) urgent_refresh_counter_next = urgent_refresh_counter - 1;
            else urgent_refresh_req_next = 1'b1;
        end

        fifo_r_full  = (fifo_r_count == FIFO_DEPTH);
        fifo_r_empty = (fifo_r_count == 0);
        fifo_w_full  = (fifo_w_count == FIFO_DEPTH);
        fifo_w_empty = (fifo_w_count == 0);

        fifo_w_wr_en = wdata_valid && !fifo_w_full;
        do_write_fifo_write = fifo_w_wr_en;
        do_write_fifo_read  = 1'b0; // Default

        fifo_r_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1);
        fifo_r_rd_en = !fifo_r_empty && resp_ready;
        do_read_fifo_write = fifo_r_wr_en && !fifo_r_full;
        do_read_fifo_read  = fifo_r_rd_en;

        case (state_reg)
            INIT_WAIT: if (init_timer == 0) state_next = INIT_PRECHARGE; else sdram_cke = 1'b0;
            INIT_PRECHARGE: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_addr[AP_BIT_INDEX] = 1'b1;
                trp_timer_next = tRP; state_next = INIT_REFRESH1;
            end
            INIT_REFRESH1: if (trp_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                trfc_timer_next = tRFC; state_next = INIT_REFRESH2;
            end
            INIT_REFRESH2: if (trfc_timer == 0) begin
                 sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                 trfc_timer_next = tRFC; state_next = INIT_MRS;
            end
            INIT_MRS: if (trfc_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_cas_n = 1'b0;
                sdram_addr = mrs_value_addr; state_next = IDLE;
            end
            IDLE: begin
                if ((refresh_pending || urgent_refresh_req) && twr_timer == 0 && trfc_timer == 0) begin
                    state_next = REFRESH_CMD;
                end else if (cmd_fifo_valid && !fifo_r_full) begin
                    cmd_fifo_ready = 1'b1;
                    current_cmd_next = cmd_fifo_data;
                    state_next = EVAL_BANK;
                end
            end

            EVAL_BANK: begin
                if (bank_state[cmd_addr.bank] == BANK_IDLE) begin
                    if (trp_timer == 0) state_next = ACTIVATE_CMD;
                    else state_next = EVAL_BANK;
                end else begin
                    if (active_row[cmd_addr.bank] == cmd_addr.row) state_next = EVAL_TIMING;
                    else state_next = EVAL_PRECHARGE;
                end
            end

            EVAL_PRECHARGE: begin
                if (tras_timer[cmd_addr.bank] == 0) state_next = PRECHARGE_CMD;
                else state_next = EVAL_PRECHARGE;
            end

            EVAL_TIMING: begin
                if (trcd_timer == 0) begin
                    if (current_cmd.rw == READ_CMD) state_next = READ_CMD;
                    else state_next = WRITE_CMD;
                end else begin
                    state_next = EVAL_TIMING;
                end
            end

            ACTIVATE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_ba = cmd_addr.bank; sdram_addr = cmd_addr.row;
                trcd_timer_next = tRCD;
                tras_timer_next[cmd_addr.bank] = tRAS;
                bank_state_next[cmd_addr.bank] = BANK_ACTIVE;
                active_row_next[cmd_addr.bank] = cmd_addr.row;
                state_next = EVAL_BANK;
            end
            READ_CMD: begin
                sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; sdram_ba = cmd_addr.bank;
                sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge;
                cas_cnt_next = CAS_LATENCY;
                burst_cnt_next = BURST_LEN;
                if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next = READ_BURST;
            end
            WRITE_CMD: begin
                sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; sdram_we_n = 1'b0; sdram_ba = cmd_addr.bank;
                sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge;
                burst_cnt_next = BURST_LEN;
                if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next = WRITE_BURST;
            end
            READ_BURST: begin
                if(do_read_fifo_write) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && do_read_fifo_write) state_next = IDLE;
            end
            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                burst_cnt_next = burst_cnt - 1;

                if (!fifo_w_empty) begin
                    do_write_fifo_read = 1'b1;
                end

                if (burst_cnt == 1) begin
                    twr_timer_next = tWR;
                    state_next = IDLE;
                end
            end
            PRECHARGE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_ba = cmd_addr.bank;
                trp_timer_next = tRP;
                bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next = EVAL_BANK;
            end
            REFRESH_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                trfc_timer_next = tRFC;
                refresh_pending_next = 1'b0;
                refresh_counter_next = REFRESH_INTERVAL;
                urgent_refresh_req_next = 1'b0;
                urgent_refresh_counter_next = URGENT_REFRESH_CYCLES;
                state_next = IDLE;
            end
            default: state_next = IDLE;
        endcase

        if (do_read_fifo_write) begin
            read_fifo_data[fifo_r_wptr] = sdram_dq;
            read_fifo_last[fifo_r_wptr] = (burst_cnt == 1);
            fifo_r_wptr_next = fifo_r_wptr + 1;
        end
        if (do_read_fifo_read) fifo_r_rptr_next = fifo_r_rptr + 1;
        fifo_r_count_next = fifo_r_count + do_read_fifo_write - do_read_fifo_read;

        if (do_write_fifo_write) begin
            write_fifo_data[fifo_w_wptr] = wdata;
            write_fifo_dqm[fifo_w_wptr]  = wdata_dqm_i;
            fifo_w_wptr_next = fifo_w_wptr + 1;
        end
        if (do_write_fifo_read) begin
            fifo_w_rptr_next = fifo_w_rptr + 1;
        end
        fifo_w_count_next = fifo_w_count + do_write_fifo_write - do_write_fifo_read;

        resp_valid  = !fifo_r_empty;
        resp_last   = read_fifo_last[fifo_r_rptr];
        resp_data   = read_fifo_data[fifo_r_rptr];
        wdata_ready = !fifo_w_full;

        sdram_dqm = (dq_write_enable_d) ? write_dqm_reg : '0;
    end

    assign sdram_dq  = (dq_write_enable_d) ? write_data_reg : 'z;
    assign sdram_clk  = clk_sh;

    generate
    if (ENABLE_DEBUG) begin : g_debug_outputs
        assign debug_state_o = state_reg;
        assign debug_rd_fifo_level_o = fifo_r_count;
        assign debug_wr_fifo_level_o = fifo_w_count;
        assign debug_cmd_fifo_level_o = (state_reg == IDLE && !((refresh_pending || urgent_refresh_req) && twr_timer == 0 && trfc_timer == 0)) ? 0 : 1;
    end else begin : g_no_debug_outputs
        assign debug_state_o = '0;
        assign debug_rd_fifo_level_o = '0;
        assign debug_wr_fifo_level_o = '0;
        assign debug_cmd_fifo_level_o = '0;
    end
    endgenerate

endmodule

`endif

