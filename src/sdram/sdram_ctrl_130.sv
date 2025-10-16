// =============================================================================
// Súbor: sdram_controller_final_v13.sv
// Verzia: 13.0 - Refactored with Modular FIFO
// Dátum: 16. október 2025
//
// Popis:
// Tento súbor predstavuje finálnu, výrazne refaktorovanú verziu SDRAM
// kontroléra. Pôvodná, manuálne implementovaná logika pre FIFO pamäte
// bola nahradená inštanciami nového, znovupoužiteľného a pre syntézu
// robustného modulu `AsyncFifoGeneric`. Tento prístup zvyšuje modularitu,
// čitateľnosť a dlhodobú udržiavateľnosť kódu.
//
// =============================================================================

`ifndef SDRAM_CTRL_V13_SV
`define SDRAM_CTRL_V13_SV

(* default_nettype = "none" *)

// =============================================================================
// Balíček so zdieľanými typmi a parametrami
// =============================================================================
package sdram_pkg;
    // Základné parametre SDRAM
    parameter int DATA_WIDTH      = 16;
    parameter int ROW_ADDR_WIDTH  = 13;
    parameter int COL_ADDR_WIDTH  = 9;
    parameter int BANK_ADDR_WIDTH = 2;
    parameter int BURST_LEN       = 8;
    parameter int CAS_LATENCY     = 3;

    // Štruktúra pre adresu rozdelenú na časti
    typedef struct packed {
        logic [BANK_ADDR_WIDTH-1:0] bank;
        logic [ROW_ADDR_WIDTH-1:0]  row;
        logic [COL_ADDR_WIDTH-1:0]  col;
    } sdram_addr_t;

    // Štruktúra pre príkaz kontroléru
    typedef struct packed {
        sdram_addr_t addr;
        logic        rw; // 1 = write, 0 = read
        logic        auto_precharge;
    } sdram_cmd_t;
endpackage : sdram_pkg

import sdram_pkg::*;

// =============================================================================
// Generický, znovupoužiteľný modul pre asynchrónne FIFO
// Používa Grayove kódy pre bezpečnú synchronizáciu medzi hodinovými doménami.
// =============================================================================
module AsyncFifoGeneric #(
    parameter int DATA_WIDTH = 16,
    parameter int ADDR_WIDTH = 4
)(
    input  logic rstn,
    // Write domain
    input  logic wr_clk,
    input  logic wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic wr_full,
    // Read domain
    input  logic rd_clk,
    input  logic rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic rd_empty
);
    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [DEPTH-1:0];

    // Pointers (binary and gray)
    logic [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_bin_next;
    logic [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_bin_next;
    logic [ADDR_WIDTH:0] wr_ptr_gray, rd_ptr_gray;
    logic [ADDR_WIDTH:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

    // --- Write Domain Logic ---
    always_ff @(posedge wr_clk) begin
        if (!rstn) begin
            wr_ptr_bin <= '0;
            rd_ptr_gray_sync1 <= '0;
            rd_ptr_gray_sync2 <= '0;
        end else begin
            wr_ptr_bin <= wr_ptr_bin_next;
            rd_ptr_gray_sync1 <= rd_ptr_gray; // Synchronizer
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end

    assign wr_ptr_bin_next = (wr_en && !wr_full) ? wr_ptr_bin + 1 : wr_ptr_bin;
    assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;

    always_ff @(posedge wr_clk) begin
        if (wr_en && !wr_full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    assign wr_full = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});

    // --- Read Domain Logic ---
    always_ff @(posedge rd_clk) begin
        if (!rstn) begin
            rd_ptr_bin <= '0;
            wr_ptr_gray_sync1 <= '0;
            wr_ptr_gray_sync2 <= '0;
        end else begin
            rd_ptr_bin <= rd_ptr_bin_next;
            wr_ptr_gray_sync1 <= wr_ptr_gray; // Synchronizer
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end

    assign rd_ptr_bin_next = (rd_en && !rd_empty) ? rd_ptr_bin + 1 : rd_ptr_bin;
    assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;
    assign rd_data = mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    assign rd_empty = (rd_ptr_gray == wr_ptr_gray_sync2);

endmodule : AsyncFifoGeneric


// =============================================================================
// Hlavný modul SDRAM Kontroléra (Refaktorovaná verzia)
// =============================================================================
module SdramControllerFinal #(
    parameter int CLOCK_FREQ_HZ      = 100_000_000,
    parameter int FIFO_DEPTH_BITS    = 4,
    parameter logic ENABLE_DEBUG     = 1'b1,
    parameter int tRP                = 3,
    parameter int tRCD               = 3,
    parameter int tWR                = 2,
    parameter int tRFC               = 9,
    parameter int tRAS               = 7
)(
    input  logic                     clk,
    input  logic                     clk_sh,
    input  logic                     rstn,
    // command FIFO interface
    input  logic                     cmd_fifo_valid,
    output logic                     cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t    cmd_fifo_data,
    // read response interface
    output logic                     resp_valid,
    output logic                     resp_last,
    output logic [DATA_WIDTH-1:0]    resp_data,
    input  logic                     resp_ready,
    // write data interface
    input  logic                     wdata_valid,
    output logic                     wdata_ready,
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  wdata_dqm_i,
    // SDRAM physical pins
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
    // debug
    output logic [4:0]               debug_state_o,
    output logic [1:0]               debug_fifo_error_o // [1]=wr_err, [0]=rd_err
);

    // --- Lokálne parametre ---
    localparam int NS_PER_SEC = 1_000_000_000;
    localparam int CLK_PERIOD_NS = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam int WAIT_TIME_NS = 200_000;
    localparam int INIT_WAIT_CYCLES = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam int REFRESH_INTERVAL = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam int AP_BIT_INDEX = 10;
    localparam logic [ROW_ADDR_WIDTH-1:0] mrs_value_addr = {1'b0, 1'b0, 2'b00, (CAS_LATENCY==3 ? 3'b011:3'b010), 1'b0, (BURST_LEN==8 ? 3'b011:3'b000)};

    // --- Typy a Funkcie ---
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
            default:   return '{cs:1, ras:1, cas:1, we:1}; // NOP
        endcase
    endfunction

    // --- Interné signály a registre ---
    state_t state_reg, state_next;
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS-1:0], bank_state_next[NUM_BANKS-1:0];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS-1:0], active_row_next[NUM_BANKS-1:0];
    logic [$clog2(tRAS+1)-1:0] tras_timer[NUM_BANKS-1:0], tras_timer_next[NUM_BANKS-1:0];

    logic load_trp, load_trcd, load_twr, load_trfc, load_init;
    logic trp_done, trcd_done, twr_done, trfc_done, init_done;

    logic [$clog2(REFRESH_INTERVAL+1)-1:0] refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;
    logic [$clog2(BURST_LEN):0] burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0] cas_cnt, cas_cnt_next;
    sdram_cmd_t current_cmd, current_cmd_next;
    logic dq_write_enable, dq_write_enable_d;

    // Signály pre prepojenie s FIFO modulmi
    logic wr_fifo_full, wr_fifo_empty;
    logic rd_fifo_full, rd_fifo_empty;
    logic wr_fifo_wr_en, wr_fifo_rd_en;
    logic rd_fifo_wr_en, rd_fifo_rd_en;
    logic [DATA_WIDTH-1:0] wr_fifo_rd_data;
    logic last_bit_fifo_empty;
    logic last_bit_out;

    // Debug
    logic rd_fifo_err_l, wr_fifo_err_l;

    logic [DATA_WIDTH-1:0] write_data_reg;
    logic [DATA_WIDTH/8-1:0] write_dqm_reg;

    // --- Inštancie ---
    CountdownTimer #($clog2(tRP+1)) trp_timer_inst (.clk, .rstn, .load(load_trp), .load_val(tRP), .done(trp_done));
    CountdownTimer #($clog2(tRCD+1)) trcd_timer_inst (.clk, .rstn, .load(load_trcd), .load_val(tRCD), .done(trcd_done));
    CountdownTimer #($clog2(tWR+1)) twr_timer_inst (.clk, .rstn, .load(load_twr), .load_val(tWR), .done(twr_done));
    CountdownTimer #($clog2(tRFC+1)) trfc_timer_inst (.clk, .rstn, .load(load_trfc), .load_val(tRFC), .done(trfc_done));
    CountdownTimer #($clog2(INIT_WAIT_CYCLES+1)) init_timer_inst (.clk, .rstn, .load(load_init), .load_val(INIT_WAIT_CYCLES), .done(init_done));

    AsyncFifoGeneric #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(FIFO_DEPTH_BITS)) write_fifo_inst (
        .rstn(rstn), .wr_clk(clk), .wr_en(wr_fifo_wr_en), .wr_data(wdata), .wr_full(wr_fifo_full),
        .rd_clk(clk), .rd_en(wr_fifo_rd_en), .rd_data(wr_fifo_rd_data), .rd_empty(wr_fifo_empty)
    );

    AsyncFifoGeneric #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(FIFO_DEPTH_BITS)) read_fifo_inst (
        .rstn(rstn), .wr_clk(clk), .wr_en(rd_fifo_wr_en), .wr_data(sdram_dq), .wr_full(rd_fifo_full),
        .rd_clk(clk), .rd_en(rd_fifo_rd_en), .rd_data(resp_data), .rd_empty(rd_fifo_empty)
    );

    AsyncFifoGeneric #(.DATA_WIDTH(1), .ADDR_WIDTH(FIFO_DEPTH_BITS)) read_fifo_last_inst (
        .rstn(rstn), .wr_clk(clk), .wr_en(rd_fifo_wr_en), .wr_data(burst_cnt == 1), .wr_full(),
        .rd_clk(clk), .rd_en(rd_fifo_rd_en), .rd_data(last_bit_out), .rd_empty(last_bit_fifo_empty)
    );

    // --- Sekvenčná Logika ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            cas_cnt <= '0;
            burst_cnt <= '0;
            current_cmd <= '{default:'0};
            dq_write_enable_d <= 1'b0;
            write_data_reg <= '0;
            write_dqm_reg <= '0;
            rd_fifo_err_l <= 1'b0;
            wr_fifo_err_l <= 1'b0;
            for (int i=0; i < NUM_BANKS; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
                tras_timer[i] <= '0;
            end
        end else begin
            state_reg       <= state_next;
            burst_cnt       <= burst_cnt_next;
            cas_cnt         <= cas_cnt_next;
            current_cmd     <= current_cmd_next;
            refresh_counter <= refresh_counter_next;
            refresh_pending <= refresh_pending_next;
            for (int i=0; i < NUM_BANKS; i++) begin
                bank_state[i] <= bank_state_next[i];
                active_row[i] <= active_row_next[i];
                tras_timer[i] <= tras_timer_next[i];
            end

            dq_write_enable_d <= dq_write_enable;

            if (wr_fifo_rd_en) begin
                write_data_reg <= wr_fifo_rd_data;
                write_dqm_reg  <= '0; // DQM from wdata_dqm_i needs another FIFO if needed
            end else if (state_reg == WRITE_BURST) begin
                write_dqm_reg <= {(DATA_WIDTH/8){1'b1}};
            end

            // Latch error flags
            if (rd_fifo_wr_en && rd_fifo_full) rd_fifo_err_l <= 1'b1;
            if (wr_fifo_wr_en && wr_fifo_full) wr_fifo_err_l <= 1'b1;
        end
    end

    // --- Kombinačná Logika ---
    always_comb begin
        sdram_addr_t cmd_addr;
        sdram_cmd_pins_t cmd_pins;

        state_next          = state_reg;
        refresh_counter_next= refresh_counter;
        refresh_pending_next= refresh_pending;
        cas_cnt_next        = cas_cnt;
        burst_cnt_next      = burst_cnt;
        current_cmd_next    = current_cmd;
        for (int i=0; i<NUM_BANKS; i++) begin
            bank_state_next[i] = bank_state[i];
            active_row_next[i] = active_row[i];
            tras_timer_next[i] = tras_timer[i];
        end

        cmd_addr = current_cmd.addr;
        cmd_fifo_ready  = 1'b0;
        dq_write_enable = 1'b0;
        sdram_addr = '0;
        sdram_ba = '0;
        cmd_pins = get_sdram_cmd(NOP);

        load_trp = 1'b0; load_trcd = 1'b0; load_twr = 1'b0; load_trfc = 1'b0; load_init = 1'b0;

        for (int i=0; i<NUM_BANKS; i++)
            if(tras_timer[i] > 0) tras_timer_next[i] = tras_timer[i] - 1;

        if (state_reg != REFRESH_CMD && refresh_counter > 0) refresh_counter_next = refresh_counter - 1;
        else refresh_pending_next = 1'b1;

        if (cas_cnt > 0) cas_cnt_next = cas_cnt - 1;

        wr_fifo_wr_en = wdata_valid && !wr_fifo_full;
        wr_fifo_rd_en = 1'b0;
        rd_fifo_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1);
        rd_fifo_rd_en = resp_ready && !rd_fifo_empty;

        case (state_reg)
            INIT_WAIT: if (init_done) state_next = INIT_PRECHARGE; else sdram_cke = 1'b0;
            INIT_PRECHARGE: begin cmd_pins = get_sdram_cmd(PRECHARGE); sdram_addr[AP_BIT_INDEX] = 1'b1; load_trp = 1'b1; state_next = INIT_REFRESH1; end
            INIT_REFRESH1:  if (trp_done)  begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; state_next = INIT_REFRESH2; end
            INIT_REFRESH2:  if (trfc_done) begin cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1; state_next = INIT_MRS; end
            INIT_MRS:       if (trfc_done) begin cmd_pins = get_sdram_cmd(MRS); sdram_addr = mrs_value_addr; state_next = IDLE; end
            IDLE: begin
                if (refresh_pending && twr_done) state_next = REFRESH_CMD;
                else if (cmd_fifo_valid) begin
                    cmd_fifo_ready = 1'b1;
                    current_cmd_next = cmd_fifo_data;
                    state_next = EVAL_BANK;
                end
            end
            EVAL_BANK: begin
                if (bank_state[cmd_addr.bank] == BANK_IDLE) begin
                    if (trp_done) state_next = ACTIVATE_CMD;
                end else begin
                    if (active_row[cmd_addr.bank] == cmd_addr.row) state_next = EVAL_TIMING;
                    else state_next = EVAL_PRECHARGE;
                end
            end
            EVAL_PRECHARGE: if (tras_timer[cmd_addr.bank] == 0) state_next = PRECHARGE_CMD;
            EVAL_TIMING:    if (trcd_done) state_next = (current_cmd.rw == 1'b1) ? WRITE_CMD : READ_CMD;
            ACTIVATE_CMD: begin
                cmd_pins = get_sdram_cmd(ACTIVE); sdram_ba = cmd_addr.bank; sdram_addr = cmd_addr.row;
                load_trcd = 1'b1; tras_timer_next[cmd_addr.bank] = tRAS;
                bank_state_next[cmd_addr.bank] = BANK_ACTIVE; active_row_next[cmd_addr.bank] = cmd_addr.row;
                state_next = EVAL_BANK;
            end
            READ_CMD: begin
                cmd_pins = get_sdram_cmd(READ); sdram_ba = cmd_addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge;
                cas_cnt_next = CAS_LATENCY; burst_cnt_next = BURST_LEN;
                if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next = READ_BURST;
            end
            WRITE_CMD: begin
                cmd_pins = get_sdram_cmd(WRITE); sdram_ba = cmd_addr.bank; sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col; sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge;
                burst_cnt_next = BURST_LEN;
                if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next = WRITE_BURST;
            end
            READ_BURST: begin
                if (rd_fifo_wr_en) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && rd_fifo_wr_en) state_next = IDLE;
            end
            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                burst_cnt_next = burst_cnt - 1;
                wr_fifo_rd_en = !wr_fifo_empty;
                if (burst_cnt == 1) begin
                    load_twr = 1'b1;
                    state_next = IDLE;
                end
            end
            PRECHARGE_CMD: begin
                cmd_pins = get_sdram_cmd(PRECHARGE); sdram_ba = cmd_addr.bank;
                load_trp = 1'b1; bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next = EVAL_BANK;
            end
            REFRESH_CMD: begin
                cmd_pins = get_sdram_cmd(REFRESH); load_trfc = 1'b1;
                refresh_pending_next = 1'b0; refresh_counter_next = REFRESH_INTERVAL;
                state_next = IDLE;
            end
            default: state_next = IDLE;
        endcase

        resp_valid  = !rd_fifo_empty && !last_bit_fifo_empty;
        resp_last   = last_bit_out;
        wdata_ready = !wr_fifo_full;

        sdram_cs_n = cmd_pins.cs;
        sdram_ras_n = cmd_pins.ras;
        sdram_cas_n = cmd_pins.cas;
        sdram_we_n = cmd_pins.we;

        sdram_dqm = (dq_write_enable_d) ? write_dqm_reg : '0;
    end

    assign sdram_dq  = (dq_write_enable_d) ? write_data_reg : 'z;
    assign sdram_clk  = clk_sh;

    generate
        if (ENABLE_DEBUG) begin : g_debug_outputs
            assign debug_state_o = state_reg;
            assign debug_fifo_error_o = {wr_fifo_err_l, rd_fifo_err_l};
        end else begin : g_no_debug_outputs
            assign debug_state_o = '0;
            assign debug_fifo_error_o = '0;
        end
    endgenerate

endmodule : SdramControllerFinal

`endif // SDRAM_CTRL_V13_SV
