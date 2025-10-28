/**
 * @file        SdramController.sv
 * @brief       Hlavný kontrolér pre SDRAM pamäť.
 * @details     Tento modul implementuje kompletný konečný stavový automat (FSM)
 * na riadenie SDRAM pamäte.
 *
 * Zmeny v tejto verzii (v2.3 - Oprava časovačov):
 * - OPRAVA (Deadlock): Vrátený parameter '.DONE_REGISTERED(1)'
 * do VŠETKÝCH inštancií 'CountdownTimer', aby zodpovedali
 * definícii 'CountdownTimer.sv' (v1.1) a zabezpečili
 * správnu (registrovanú) funkciu 'done' signálu pre FSM.
 *
 * Závislosti:
 * - sdram_pkg.sv (v2)
 * - CountdownTimer.sv (v1.1 - s DONE_REGISTERED)
 * - AsyncFifoGeneric.sv (v1.9)
 *
 * @param CFifoAddrWidth Šírka adresy pre interné dátové FIFO buffre.
 */

`ifndef SDRAM_CONTROLLER_SV
`define SDRAM_CONTROLLER_SV

`default_nettype none

import sdram_pkg::*; // Importujeme typy a VŠETKY parametre z balíčka

module SdramController #(
    parameter int CFifoAddrWidth = 6
)(
    input  logic clk,
    input  logic clk_sh,
    input  logic rstn,
    input  sdram_pkg::sdram_cmd_t wr_cmd_data,
    input  logic                  wr_cmd_valid,
    output logic                  wr_cmd_ready,
    input  sdram_pkg::sdram_cmd_t rd_cmd_data,
    input  logic                  rd_cmd_valid,
    output logic                  rd_cmd_ready,
    input  logic [sdram_pkg::DATA_WIDTH-1:0] wdata,
    input  logic                             wdata_valid,
    output logic                             wdata_ready,
    output logic [CFifoAddrWidth:0]          wdata_level,
    output logic [sdram_pkg::DATA_WIDTH-1:0] rdata,
    output logic                             rdata_valid,
    input  logic                             rdata_ready,
    output logic [CFifoAddrWidth:0]          rdata_level,
    output logic [sdram_pkg::ROW_ADDR_WIDTH-1:0]  sdram_addr,
    output logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic                                 sdram_cs_n,
    output logic                                 sdram_ras_n,
    output logic                                 sdram_cas_n,
    output logic                                 sdram_we_n,
    inout  wire  [sdram_pkg::DATA_WIDTH-1:0]     sdram_dq,
    output logic [sdram_pkg::DATA_WIDTH/8-1:0]   sdram_dqm,
    output logic                                 sdram_cke,
    output logic                                 sdram_clk,
    output logic busy_o,
    output logic [1:0] fifo_error_o
);

    localparam int CApBitIndex     = 10;
    localparam int CNumBanks       = 1 << sdram_pkg::BANK_ADDR_WIDTH;

    typedef enum logic [5:0] { // Rozšírené na 6 bitov
      INIT_START, INIT_WAIT,
      INIT_PRECHARGE_CMD, INIT_PRECHARGE_WAIT,
      INIT_REFRESH1_CMD, INIT_REFRESH1_WAIT,
      INIT_REFRESH2_CMD, INIT_REFRESH2_WAIT,
      INIT_MRS_CMD, INIT_MRS_WAIT,
      IDLE, EVAL_BANK, EVAL_PRECHARGE,
      ACTIVATE_CMD,
      WAIT_TRCD,
      READ_CMD, WRITE_CMD, PRECHARGE_CMD, REFRESH_CMD,
      READ_BURST, WRITE_BURST
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

    state_t state_reg, state_next;

    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state      [CNumBanks];
    bank_state_t bank_state_next [CNumBanks];
    logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] active_row      [CNumBanks];
    logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] active_row_next [CNumBanks];
    logic [$clog2(sdram_pkg::T_RAS_CYCLES+1)-1:0] tras_timer      [CNumBanks];
    logic [$clog2(sdram_pkg::T_RAS_CYCLES+1)-1:0] tras_timer_next [CNumBanks];

    logic load_trp, load_trcd, load_twr, load_trfc, load_init, load_trmrd;
    logic trp_done, trcd_done, twr_done, trfc_done, init_done, trmrd_done;

    logic [$clog2(sdram_pkg::REFRESH_INTERVAL_CYCLES+1)-1:0] refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;

    logic [$clog2(sdram_pkg::BURST_LEN):0]       burst_cnt, burst_cnt_next;
    logic [$clog2(sdram_pkg::CAS_LATENCY+1)-1:0] cas_cnt, cas_cnt_next;

    sdram_pkg::sdram_cmd_t current_cmd;
    logic dq_write_enable, dq_write_enable_d;
    logic [sdram_pkg::DATA_WIDTH-1:0] write_data_reg;
    logic fsm_ready_for_cmd;
    sdram_pkg::sdram_cmd_t selected_cmd;
    logic selected_cmd_valid;

    logic wr_fifo_full, wr_fifo_empty;
    logic rd_fifo_full, rd_fifo_empty;
    logic wr_fifo_wr_en, wr_fifo_rd_en;
    logic rd_fifo_wr_en, rd_fifo_rd_en;
    logic [sdram_pkg::DATA_WIDTH-1:0] wr_fifo_rd_data;
    logic wr_fifo_overflow, wr_fifo_underflow;
    logic rd_fifo_overflow, rd_fifo_underflow;

    logic all_banks_idle;

    // --- Inštancie časovačov ---
    // OPRAVA: Vrátený parameter .DONE_REGISTERED(1)
    CountdownTimer #(
      .COUNT_WIDTH($clog2(sdram_pkg::T_RP_CYCLES+1)), .DONE_REGISTERED(1)
    ) trp_timer_inst (
      .clk(clk), .rstn(rstn), .load(load_trp), .load_val(sdram_pkg::T_RP_CYCLES), .done(trp_done)
    );
    CountdownTimer #(
      .COUNT_WIDTH($clog2(sdram_pkg::T_RCD_CYCLES+1)), .DONE_REGISTERED(1)
    ) trcd_timer_inst(
      .clk(clk), .rstn(rstn), .load(load_trcd), .load_val(sdram_pkg::T_RCD_CYCLES), .done(trcd_done)
    );
    CountdownTimer #(
      .COUNT_WIDTH($clog2(sdram_pkg::T_WR_CYCLES+1)), .DONE_REGISTERED(1)
    ) twr_timer_inst (
      .clk(clk), .rstn(rstn), .load(load_twr), .load_val(sdram_pkg::T_WR_CYCLES), .done(twr_done)
    );
    CountdownTimer #(
      .COUNT_WIDTH($clog2(sdram_pkg::T_RFC_CYCLES+1)), .DONE_REGISTERED(1)
    ) trfc_timer_inst(
      .clk(clk), .rstn(rstn), .load(load_trfc), .load_val(sdram_pkg::T_RFC_CYCLES), .done(trfc_done)
    );
    CountdownTimer #(
      .COUNT_WIDTH($clog2(sdram_pkg::T_MRD_CYCLES+1)), .DONE_REGISTERED(1)
    ) trmrd_timer_inst(
      .clk(clk), .rstn(rstn), .load(load_trmrd), .load_val(sdram_pkg::T_MRD_CYCLES), .done(trmrd_done)
    );
    CountdownTimer #(
      .COUNT_WIDTH($clog2(sdram_pkg::CInitWaitCycles+1)), .DONE_REGISTERED(1)
    ) init_timer_inst(
      .clk(clk), .rstn(rstn), .load(load_init), .load_val(sdram_pkg::CInitWaitCycles), .done(init_done)
    );

    // --- Inštancie dátových FIFO ---
    AsyncFifoGeneric #(
      .DATA_WIDTH(sdram_pkg::DATA_WIDTH), .ADDR_WIDTH(CFifoAddrWidth),
      .RAM_STYLE("auto"), .TWO_STAGE_SYNC(1)
    ) write_fifo_inst (
      .wr_rst_ni(rstn), .rd_rst_ni(rstn),
      .wr_clk(clk), .wr_en(wr_fifo_wr_en), .wr_data(wdata), .wr_full(wr_fifo_full),
      .rd_clk(clk), .rd_en(wr_fifo_rd_en), .rd_data(wr_fifo_rd_data), .rd_empty(wr_fifo_empty),
      .level(wdata_level),
      .wr_overflow(wr_fifo_overflow),
      .rd_underflow(wr_fifo_underflow)
    );

    AsyncFifoGeneric #(
      .DATA_WIDTH(sdram_pkg::DATA_WIDTH), .ADDR_WIDTH(CFifoAddrWidth),
      .RAM_STYLE("auto"), .TWO_STAGE_SYNC(1)
    ) read_fifo_inst (
      .wr_rst_ni(rstn), .rd_rst_ni(rstn),
      .wr_clk(clk), .wr_en(rd_fifo_wr_en), .wr_data(sdram_dq), .wr_full(rd_fifo_full),
      .rd_clk(clk), .rd_en(rd_fifo_rd_en), .rd_data(rdata), .rd_empty(rd_fifo_empty),
      .level(rdata_level),
      .wr_overflow(rd_fifo_overflow),
      .rd_underflow(rd_fifo_underflow)
    );

    // --- Arbitrácia ---
    always_comb begin
        fsm_ready_for_cmd = (state_reg == IDLE) && !refresh_pending && twr_done;

        selected_cmd_valid = 1'b0;
        selected_cmd       = '0;
        rd_cmd_ready       = 1'b0;
        wr_cmd_ready       = 1'b0;

        if (rd_cmd_valid) begin
            selected_cmd_valid = 1'b1;
            selected_cmd       = rd_cmd_data;
            if (fsm_ready_for_cmd)
                rd_cmd_ready = 1'b1;
        end else if (wr_cmd_valid) begin
            selected_cmd_valid = 1'b1;
            selected_cmd       = wr_cmd_data;
            if (fsm_ready_for_cmd)
                wr_cmd_ready = 1'b1;
        end
    end

    // --- Sekvenčná logika ---
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg         <= INIT_START;
            refresh_counter   <= sdram_pkg::REFRESH_INTERVAL_CYCLES;
            refresh_pending   <= 1'b0;
            cas_cnt           <= '0;
            burst_cnt         <= '0;
            current_cmd       <= '0;
            dq_write_enable_d <= 1'b0;
            write_data_reg    <= '0;
            for (int i = 0; i < CNumBanks; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
                tras_timer[i] <= '0;
            end
        end else begin
            state_reg <= state_next;

            burst_cnt       <= burst_cnt_next;
            cas_cnt         <= cas_cnt_next;
            refresh_counter <= refresh_counter_next;
            refresh_pending <= refresh_pending_next;

            if (fsm_ready_for_cmd && selected_cmd_valid)
                current_cmd <= selected_cmd;

            for (int i = 0; i < CNumBanks; i++) begin
                bank_state[i] <= bank_state_next[i];
                active_row[i] <= active_row_next[i];
                tras_timer[i] <= tras_timer_next[i];
            end

            dq_write_enable_d <= dq_write_enable;
            if (wr_fifo_rd_en)
                write_data_reg <= wr_fifo_rd_data;
        end
    end

    // --- Kombinačná logika FSM ---
    always_comb begin
        sdram_pkg::sdram_addr_t cmd_addr;
        sdram_cmd_pins_t        cmd_pins;

        state_next           = state_reg;
        refresh_counter_next = refresh_counter;
        refresh_pending_next = refresh_pending;
        cas_cnt_next         = cas_cnt;
        burst_cnt_next       = burst_cnt;
        for (int i = 0; i < CNumBanks; i++) begin
            bank_state_next[i] = bank_state[i];
            active_row_next[i] = active_row[i];
            tras_timer_next[i] = tras_timer[i];
        end

        cmd_addr = current_cmd.addr;
        cmd_pins = get_sdram_cmd(NOP);

        dq_write_enable = 1'b0;
        sdram_addr      = '0;
        sdram_ba        = '0;
        sdram_cke       = 1'b1;

        load_trp   = 1'b0;
        load_trcd  = 1'b0;
        load_twr   = 1'b0;
        load_trfc  = 1'b0;
        load_init  = 1'b0;
        load_trmrd = 1'b0;

        for (int i = 0; i < CNumBanks; i++)
            if (tras_timer[i] > 0)
                tras_timer_next[i] = tras_timer[i] - 1'b1;

        if (cas_cnt > 0)
            cas_cnt_next = cas_cnt - 1'b1;

        if (state_reg != REFRESH_CMD && refresh_counter > 0)
            refresh_counter_next = refresh_counter - 1'b1;
        else if (state_reg != REFRESH_CMD && refresh_counter == 0)
            refresh_pending_next = 1'b1;

        wr_fifo_rd_en = (state_reg == WRITE_BURST) && (burst_cnt > 0) && !wr_fifo_empty;
        wr_fifo_wr_en = wdata_valid && !wr_fifo_full;
        rd_fifo_wr_en = (state_reg == READ_BURST) && (cas_cnt == 0) && (burst_cnt > 0) && !rd_fifo_full;
        rd_fifo_rd_en = rdata_ready && !rd_fifo_empty;

        all_banks_idle = 1'b1;
        for (int i = 0; i < CNumBanks; i++) begin
            if (bank_state[i] != BANK_IDLE)
                all_banks_idle = 1'b0;
        end

        case (state_reg)
            INIT_START: begin
                load_init = 1'b1;
                sdram_cke = 1'b0;
                state_next = INIT_WAIT;
            end

            INIT_WAIT: begin
                sdram_cke = 1'b0;
                if (init_done)
                    state_next = INIT_PRECHARGE_CMD;
            end

            INIT_PRECHARGE_CMD: begin
                cmd_pins                 = get_sdram_cmd(PRECHARGE);
                sdram_addr[CApBitIndex] = 1'b1;
                load_trp                 = 1'b1;
                state_next               = INIT_PRECHARGE_WAIT;
            end

            INIT_PRECHARGE_WAIT: begin
                if (trp_done)
                    state_next = INIT_REFRESH1_CMD;
            end

            INIT_REFRESH1_CMD: begin
                cmd_pins   = get_sdram_cmd(REFRESH);
                load_trfc  = 1'b1;
                state_next = INIT_REFRESH1_WAIT;
            end

            INIT_REFRESH1_WAIT: begin
                if (trfc_done)
                    state_next = INIT_REFRESH2_CMD;
            end

            INIT_REFRESH2_CMD: begin
                cmd_pins   = get_sdram_cmd(REFRESH);
                load_trfc  = 1'b1;
                state_next = INIT_REFRESH2_WAIT;
            end

            INIT_REFRESH2_WAIT: begin
                if (trfc_done)
                    state_next = INIT_MRS_CMD;
            end

            INIT_MRS_CMD: begin
                cmd_pins   = get_sdram_cmd(MRS);
                sdram_addr = sdram_pkg::CMrsValueAddr;
                load_trmrd = 1'b1;
                state_next = INIT_MRS_WAIT;
            end

            INIT_MRS_WAIT: begin
                if (trmrd_done)
                    state_next = IDLE;
            end

            IDLE: begin
                if (refresh_pending && twr_done && all_banks_idle)
                    state_next = REFRESH_CMD;
                else if (fsm_ready_for_cmd && selected_cmd_valid)
                    state_next = EVAL_BANK;
            end

            EVAL_BANK: begin
                if (bank_state[cmd_addr.bank] == BANK_IDLE) begin
                    if (trp_done)
                        state_next = ACTIVATE_CMD;
                end else begin
                    if (active_row[cmd_addr.bank] == cmd_addr.row)
                        state_next = WAIT_TRCD;
                    else
                        state_next = EVAL_PRECHARGE;
                end
            end

            EVAL_PRECHARGE: begin
                if (tras_timer[cmd_addr.bank] == 0) begin
                    tras_timer_next[cmd_addr.bank] = 0;
                    state_next = PRECHARGE_CMD;
                end
            end

            ACTIVATE_CMD: begin
                cmd_pins                       = get_sdram_cmd(ACTIVE);
                sdram_ba                       = cmd_addr.bank;
                sdram_addr                     = cmd_addr.row;
                load_trcd                      = 1'b1;
                tras_timer_next[cmd_addr.bank] = sdram_pkg::T_RAS_CYCLES;
                bank_state_next[cmd_addr.bank] = BANK_ACTIVE;
                active_row_next[cmd_addr.bank] = cmd_addr.row;
                state_next                     = WAIT_TRCD;
            end

            WAIT_TRCD: begin
                if (trcd_done) begin
                    if (bank_state[cmd_addr.bank] == BANK_IDLE) begin
                        state_next = EVAL_BANK;
                    end else if (active_row[cmd_addr.bank] != cmd_addr.row) begin
                        state_next = EVAL_BANK;
                    end else begin
                        state_next = (current_cmd.rw == 1'b1) ? WRITE_CMD : READ_CMD;
                    end
                end
            end

            READ_CMD: begin
                cmd_pins                               = get_sdram_cmd(READ);
                sdram_ba                               = cmd_addr.bank;
                sdram_addr[sdram_pkg::COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr[CApBitIndex]                = current_cmd.auto_precharge;
                cas_cnt_next                           = sdram_pkg::CAS_LATENCY;
                burst_cnt_next                         = sdram_pkg::BURST_LEN;
                if (current_cmd.auto_precharge) begin
                    bank_state_next[cmd_addr.bank] = BANK_IDLE;
                    load_trp                       = 1'b1;
                    tras_timer_next[cmd_addr.bank] = 0;
                end
                state_next = READ_BURST;
            end

            WRITE_CMD: begin
                cmd_pins                               = get_sdram_cmd(WRITE);
                sdram_ba                               = cmd_addr.bank;
                sdram_addr[sdram_pkg::COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr[CApBitIndex]                = current_cmd.auto_precharge;
                burst_cnt_next                         = sdram_pkg::BURST_LEN;
                if (current_cmd.auto_precharge) begin
                    bank_state_next[cmd_addr.bank] = BANK_IDLE;
                    load_twr                       = 1'b1;
                    load_trp                       = 1'b1;
                    tras_timer_next[cmd_addr.bank] = 0;
                end
                state_next = WRITE_BURST;
            end

            READ_BURST: begin
                if (cas_cnt == 0) begin
                    if (burst_cnt > 0) begin
                        if (!rd_fifo_full) begin
                            burst_cnt_next = burst_cnt - 1'b1;
                        end
                    end

                    if (burst_cnt == 1 && !rd_fifo_full) begin
                        state_next = IDLE;
                    end
                end
            end

            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                if (burst_cnt > 0) begin
                    if (!wr_fifo_empty) begin
                        burst_cnt_next = burst_cnt - 1'b1;
                    end
                end

                if (burst_cnt == 1 && !wr_fifo_empty) begin
                    load_twr   = 1'b1;
                    state_next = IDLE;
                end
            end

            PRECHARGE_CMD: begin
                cmd_pins                       = get_sdram_cmd(PRECHARGE);
                sdram_ba                       = cmd_addr.bank;
                load_trp                       = 1'b1;
                bank_state_next[cmd_addr.bank] = BANK_IDLE;
                tras_timer_next[cmd_addr.bank] = 0;
                state_next                     = IDLE;
            end

            REFRESH_CMD: begin
                cmd_pins             = get_sdram_cmd(REFRESH);
                load_trfc            = 1'b1;
                refresh_pending_next = 1'b0;
                refresh_counter_next = sdram_pkg::REFRESH_INTERVAL_CYCLES;
                state_next           = IDLE;
            end

            default: state_next = IDLE;
        endcase

        wdata_ready = !wr_fifo_full;
        rdata_valid = !rd_fifo_empty;

        sdram_cs_n  = cmd_pins.cs;
        sdram_ras_n = cmd_pins.ras;
        sdram_cas_n = cmd_pins.cas;
        sdram_we_n  = cmd_pins.we;

        sdram_dqm = (dq_write_enable_d && wr_fifo_empty) ? {sdram_pkg::DATA_WIDTH/8{1'b1}} : '0;
    end

    // --- Obojsmerné a hodinové priradenia ---
    assign sdram_dq  = (dq_write_enable_d) ? write_data_reg : {sdram_pkg::DATA_WIDTH{1'bz}};
    assign sdram_clk = clk_sh;

    // --- Diagnostické výstupy ---
    assign busy_o = (state_reg != IDLE);
    assign fifo_error_o = { (wr_fifo_overflow | wr_fifo_underflow),
                            (rd_fifo_overflow | rd_fifo_underflow) };

endmodule

`default_nettype wire

`endif // SDRAM_CONTROLLER_SV

