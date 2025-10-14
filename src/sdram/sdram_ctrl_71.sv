// sdram_controller_final.sv - Verzia 7.10 - Finalizované pre robustnosť
// Zmeny (v7.10):
// 1. DOLADENIE (Robustnosť): Všetka kombinačná logika bola presunutá do `always_comb`
//    bloku s použitím `_next` signálov pre všetky registre (časovače, FSM, FIFO).
//    `always_ff` blok teraz obsahuje iba nekondičné priradenia.
// 2. DOLADENIE (Robustnosť): Reset bol zmenený z asynchrónneho na plne synchrónny,
//    čo je preferovaná prax pre moderné FPGA návrhy.

`ifndef SDRAM_CTRL_FINAL_SV
`define SDRAM_CTRL_FINAL_SV

(* default_nettype = "none" *)

module SdramControllerFinal #(
    // --- System Parameters ---
    parameter CLOCK_FREQ_HZ     = 100_000_000,
    parameter DATA_WIDTH        = 16,
    parameter integer FIFO_DEPTH_BITS  = 4,
    parameter logic ENABLE_DEBUG = 1'b1,

    // --- SDRAM Geometry Parameters ---
    parameter integer ROW_ADDR_WIDTH    = 13,
    parameter integer COL_ADDR_WIDTH    = 9,
    parameter integer BANK_ADDR_WIDTH   = 2,

    // --- SDRAM Protocol Parameters ---
    parameter BURST_LEN         = 8,
    parameter integer CAS_LATENCY     = 3,

    // --- SDRAM Timing Parameters (v cykloch) ---
    parameter integer tRP             = 3,
    parameter integer tRCD            = 3,
    parameter integer tWR             = 2,
    parameter integer tRFC            = 9,
    parameter integer tRAS            = 7
)(
    // --- Rozhrania (rovnaké ako v7.00) ---
    input  logic                     clk,
    input  logic                     clk_sh,
    input  logic                     rstn,
    input  logic                     cmd_fifo_valid,
    output logic                     cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t    cmd_fifo_data,
    output logic                     resp_valid,
    output logic                     resp_last,
    output logic [DATA_WIDTH-1:0]    resp_data,
    input  logic                     resp_ready,
    input  logic                     wdata_valid,
    output logic                     wdata_ready,
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  wdata_dqm_i,
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
    output logic [4:0]               debug_state_o,
    output logic [$clog2(FIFO_DEPTH_BITS+1):0] debug_rd_fifo_level_o,
    output logic [$clog2(FIFO_DEPTH_BITS+1):0] debug_wr_fifo_level_o
);

    import sdram_pkg::*;

    // --- Lokálne Parametre (rovnaké ako v7.00) ---
    localparam integer NUM_BANKS          = 2**BANK_ADDR_WIDTH;
    localparam integer ADDR_WIDTH         = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;
    localparam integer BANK_ADDR_HI = ADDR_WIDTH - 1;
    localparam integer BANK_ADDR_LO = BANK_ADDR_HI - BANK_ADDR_WIDTH + 1;
    localparam integer ROW_ADDR_HI  = BANK_ADDR_LO - 1;
    localparam integer ROW_ADDR_LO  = ROW_ADDR_HI - ROW_ADDR_WIDTH + 1;
    localparam integer COL_ADDR_HI  = ROW_ADDR_LO - 1;
    localparam integer COL_ADDR_LO  = 0;
    localparam integer NS_PER_SEC         = 1_000_000_000;
    localparam integer CLK_PERIOD_NS      = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam integer WAIT_TIME_NS       = 200_000;
    localparam integer INIT_WAIT_CYCLES   = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam integer REFRESH_INTERVAL   = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam logic [2:0] burst_len_bits = (BURST_LEN == 1) ? 3'b000 : (BURST_LEN == 2) ? 3'b001 :
                                          (BURST_LEN == 4) ? 3'b010 : (BURST_LEN == 8) ? 3'b011 : 3'b111;
    localparam logic [2:0] cas_latency_bits = (CAS_LATENCY == 2) ? 3'b010 : (CAS_LATENCY == 3) ? 3'b011 : 3'b000;
    localparam logic [12:0] mrs_value = {3'b000, 1'b0, 2'b00, cas_latency_bits, 1'b0, burst_len_bits};
    localparam integer FIFO_DEPTH = 1 << FIFO_DEPTH_BITS;

    // --- FSM States ---
    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS,
        IDLE, EVAL_CMD, ACTIVATE_CMD, READ_CMD, WRITE_CMD,
        PRECHARGE_CMD, REFRESH_CMD, READ_BURST, WRITE_BURST
    } state_t;

    // --- Signály a Registre (s pridanými _next pre robustnosť) ---
    state_t state_reg, state_next;

    // Bank State
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS], bank_state_next[NUM_BANKS];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS], active_row_next[NUM_BANKS];

    // Timers
    logic [$clog2(tRAS+1)-1:0]               tras_timer[NUM_BANKS], tras_timer_next[NUM_BANKS];
    logic [$clog2(INIT_WAIT_CYCLES+1)-1:0]   init_timer, init_timer_next;
    logic [$clog2(tRCD+1)-1:0]               trcd_timer, trcd_timer_next;
    logic [$clog2(tRP+1)-1:0]                trp_timer, trp_timer_next;
    logic [$clog2(tWR+1)-1:0]                twr_timer, twr_timer_next;
    logic [$clog2(tRFC+1)-1:0]               trfc_timer, trfc_timer_next;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0]   refresh_counter, refresh_counter_next;
    logic                                    refresh_pending, refresh_pending_next;
    logic [$clog2(BURST_LEN):0]              burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0]        cas_cnt, cas_cnt_next;

    // Command & Data
    sdram_cmd_t current_cmd, current_cmd_next;
    logic dq_write_enable, dq_write_enable_d;

    // Read FIFO
    logic [DATA_WIDTH-1:0]      read_fifo_data[FIFO_DEPTH];
    logic                       read_fifo_last[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_r_wptr, fifo_r_wptr_next;
    logic [FIFO_DEPTH_BITS-1:0] fifo_r_rptr, fifo_r_rptr_next;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_r_count, fifo_r_count_next;
    logic fifo_r_wr_en, fifo_r_rd_en, fifo_r_full, fifo_r_empty;

    // Write FIFO
    logic [DATA_WIDTH-1:0]      write_fifo_data[FIFO_DEPTH];
    logic [DATA_WIDTH/8-1:0]    write_fifo_dqm[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_w_wptr, fifo_w_wptr_next;
    logic [FIFO_DEPTH_BITS-1:0] fifo_w_rptr, fifo_w_rptr_next;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_w_count, fifo_w_count_next;
    logic fifo_w_wr_en, fifo_w_rd_en, fifo_w_full, fifo_w_empty;


    // --- Sekvenčný Blok (Srdce) ---
    // ZMENA (v7.10): Plne synchrónny, registruje iba `_next` hodnoty
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            init_timer <= INIT_WAIT_CYCLES;
            trcd_timer <= '0; trp_timer <= '0; twr_timer <= '0; trfc_timer <= '0;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            cas_cnt <= '0;
            burst_cnt <= '0;
            current_cmd <= '0;
            fifo_r_wptr <= '0; fifo_r_rptr <= '0; fifo_r_count <= '0;
            fifo_w_wptr <= '0; fifo_w_rptr <= '0; fifo_w_count <= '0;
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
        // Pipelined DQ enable register
        dq_write_enable_d <= dq_write_enable;
    end

    // --- Kombinačný Blok (Mozog) ---
    // ZMENA (v7.10): Všetka logika je tu, počíta `_next` hodnoty
    always_comb begin
        // --- Defaultné priradenia (drž hodnotu) ---
        state_next          = state_reg;
        init_timer_next     = init_timer;
        trcd_timer_next     = trcd_timer;
        trp_timer_next      = trp_timer;
        twr_timer_next      = twr_timer;
        trfc_timer_next     = trfc_timer;
        refresh_counter_next= refresh_counter;
        refresh_pending_next= refresh_pending;
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

        // --- Dekódovanie adresy ---
        logic [BANK_ADDR_WIDTH-1:0] cmd_bank_addr = current_cmd.addr[BANK_ADDR_HI:BANK_ADDR_LO];
        logic [ROW_ADDR_WIDTH-1:0]  cmd_row_addr  = current_cmd.addr[ROW_ADDR_HI:ROW_ADDR_LO];
        logic [COL_ADDR_WIDTH-1:0]  cmd_col_addr  = current_cmd.addr[COL_ADDR_HI:COL_ADDR_LO];

        // --- Riadiace signály ---
        cmd_fifo_ready  = 1'b0;
        dq_write_enable = 1'b0;
        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1; sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_addr = '0; sdram_ba = '0; sdram_dqm = '0; sdram_cke = 1'b1;

        // --- Dekrementácia časovačov ---
        if (init_timer > 0) init_timer_next = init_timer - 1;
        if (trcd_timer > 0) trcd_timer_next = trcd_timer - 1;
        if (trp_timer > 0)  trp_timer_next  = trp_timer - 1;
        if (twr_timer > 0)  twr_timer_next  = twr_timer - 1;
        if (trfc_timer > 0) trfc_timer_next = trfc_timer - 1;
        if (cas_cnt > 0)    cas_cnt_next    = cas_cnt - 1;
        for (int i=0; i<NUM_BANKS; i++)
            if(tras_timer[i] > 0) tras_timer_next[i] = tras_timer[i] - 1;

        // --- Refresh logika ---
        if (state_reg != REFRESH_CMD) begin
            if (refresh_counter == 0) refresh_pending_next = 1'b1;
            else refresh_counter_next = refresh_counter - 1;
        end

        // --- FIFO logika ---
        fifo_r_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1);
        fifo_r_rd_en = !fifo_r_empty && resp_ready;
        fifo_r_full  = (fifo_r_count == FIFO_DEPTH);
        fifo_r_empty = (fifo_r_count == 0);
        if (fifo_r_wr_en && !fifo_r_full) begin
            read_fifo_data[fifo_r_wptr] = sdram_dq; // Note: this is a simplification for modeling
            read_fifo_last[fifo_r_wptr] = (burst_cnt == 1);
            fifo_r_wptr_next = fifo_r_wptr + 1;
        end
        if (fifo_r_rd_en && !fifo_r_empty) fifo_r_rptr_next = fifo_r_rptr + 1;
        if (fifo_r_wr_en && !fifo_r_full && !(fifo_r_rd_en && !fifo_r_empty)) fifo_r_count_next = fifo_r_count + 1;
        else if (!fifo_r_wr_en && fifo_r_rd_en && !fifo_r_empty) fifo_r_count_next = fifo_r_count - 1;

        fifo_w_wr_en = wdata_valid && !fifo_w_full;
        fifo_w_rd_en = (state_reg == WRITE_BURST);
        fifo_w_full  = (fifo_w_count == FIFO_DEPTH);
        fifo_w_empty = (fifo_w_count == 0);
        if (fifo_w_wr_en) begin
            write_fifo_data[fifo_w_wptr] = wdata;
            write_fifo_dqm[fifo_w_wptr]  = wdata_dqm_i;
            fifo_w_wptr_next = fifo_w_wptr + 1;
        end
        if (fifo_w_rd_en && !fifo_w_empty) fifo_w_rptr_next = fifo_w_rptr + 1;
        if (fifo_w_wr_en && !(fifo_w_rd_en && !fifo_w_empty)) fifo_w_count_next = fifo_w_count + 1;
        else if (!fifo_w_wr_en && fifo_w_rd_en && !fifo_w_empty) fifo_w_count_next = fifo_w_count - 1;

        // --- Hlavný FSM ---
        case (state_reg)
            INIT_WAIT: if (init_timer == 0) state_next = INIT_PRECHARGE; else sdram_cke = 1'b0;
            INIT_PRECHARGE: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_addr[10] = 1'b1;
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
                sdram_addr = mrs_value[ROW_ADDR_WIDTH-1:0]; state_next = IDLE;
            end

            IDLE: begin
                if (refresh_pending && twr_timer == 0 && trfc_timer == 0) state_next = REFRESH_CMD;
                else if (cmd_fifo_valid && !fifo_r_full) begin
                    cmd_fifo_ready = 1'b1;
                    current_cmd_next = cmd_fifo_data;
                    state_next = EVAL_CMD;
                end
            end

            EVAL_CMD: begin
                if (bank_state[cmd_bank_addr] == BANK_IDLE) begin
                    if (trp_timer == 0) state_next = ACTIVATE_CMD; else state_next = IDLE;
                end else begin // Bank ACTIVE
                    if (active_row[cmd_bank_addr] == cmd_row_addr) begin // Row Hit
                         if (trcd_timer == 0) state_next = (current_cmd.rw == READ_CMD) ? READ_CMD : WRITE_CMD; else state_next = IDLE;
                    end else begin // Row Miss
                        if (tras_timer[cmd_bank_addr] == 0) state_next = PRECHARGE_CMD; else state_next = IDLE;
                    end
                end
            end

            ACTIVATE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_ba = cmd_bank_addr; sdram_addr = cmd_row_addr;
                trcd_timer_next = tRCD;
                tras_timer_next[cmd_bank_addr] = tRAS;
                bank_state_next[cmd_bank_addr] = BANK_ACTIVE;
                active_row_next[cmd_bank_addr] = cmd_row_addr;
                state_next = IDLE; // Plánovač sa vráti do IDLE a môže obslúžiť inú banku
            end

            READ_CMD: begin
                sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; sdram_ba = cmd_bank_addr;
                sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_col_addr; sdram_addr[10] = current_cmd.auto_precharge;
                cas_cnt_next = CAS_LATENCY;
                burst_cnt_next = BURST_LEN;
                if (current_cmd.auto_precharge) bank_state_next[cmd_bank_addr] = BANK_IDLE;
                state_next = READ_BURST;
            end

            WRITE_CMD: begin
                if (!fifo_w_empty) begin
                    sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; sdram_we_n = 1'b0; sdram_ba = cmd_bank_addr;
                    sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_col_addr; sdram_addr[10] = current_cmd.auto_precharge;
                    burst_cnt_next = BURST_LEN;
                    if (current_cmd.auto_precharge) bank_state_next[cmd_bank_addr] = BANK_IDLE;
                    state_next = WRITE_BURST;
                end else state_next = IDLE; // Počkaj na dáta
            end

            READ_BURST: begin
                if(fifo_r_wr_en) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && fifo_r_wr_en) state_next = IDLE;
            end

            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                sdram_dqm = write_fifo_dqm[fifo_w_rptr];
                if(fifo_w_rd_en) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && fifo_w_rd_en) begin
                    twr_timer_next = tWR;
                    state_next = IDLE;
                end
            end

            PRECHARGE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_ba = cmd_bank_addr;
                trp_timer_next = tRP;
                bank_state_next[cmd_bank_addr] = BANK_IDLE;
                state_next = IDLE; // Plánovač sa vráti do IDLE
            end

            REFRESH_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                trfc_timer_next = tRFC;
                refresh_pending_next = 1'b0;
                refresh_counter_next = REFRESH_INTERVAL;
                state_next = IDLE;
            end
            default: state_next = IDLE;
        endcase
    end

    // --- Výstupy a Priradenia ---
    assign resp_valid = !fifo_r_empty;
    assign resp_last  = read_fifo_last[fifo_r_rptr];
    assign resp_data  = read_fifo_data[fifo_r_rptr];
    assign wdata_ready= !fifo_w_full;
    assign sdram_dq   = (dq_write_enable_d) ? write_fifo_data[fifo_w_rptr] : {DATA_WIDTH{1'bz}};
    assign sdram_clk  = clk_sh;

    // --- Ladiace Výstupy ---
    generate
    if (ENABLE_DEBUG) begin : g_debug_outputs
        assign debug_state_o = state_reg;
        assign debug_rd_fifo_level_o = fifo_r_count;
        assign debug_wr_fifo_level_o = fifo_w_count;
    end else begin : g_no_debug_outputs
        assign debug_state_o = IDLE;
        assign debug_rd_fifo_level_o = '0;
        assign debug_wr_fifo_level_o = '0;
    end
    endgenerate

endmodule

`default_nettype wire

`endif
