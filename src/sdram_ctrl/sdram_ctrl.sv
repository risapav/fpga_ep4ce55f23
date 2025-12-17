/**
 * @file        sdram_ctrl.sv
 * @brief       SDRAM Core Controller.
 * @details     Hlavný radič SDRAM pamäte. Obsahuje stavový automat pre inicializáciu,
 * refresh a read/write operácie. Využíva interné Skid Buffery a FIFO pre
 * oddelenie časovania a burst prenosy.
 *
 * @param CFifoAddrWidth Šírka adresy interných FIFO.
 * @param T_*_CYCLES     Časovanie SDRAM (definované v sdram_pkg).
 */

`default_nettype none

`ifndef SDRAM_CTRL_SV
`define SDRAM_CTRL_SV

import sdram_pkg::*;

module sdram_ctrl #(
    parameter int CFifoAddrWidth = 6,
    // Timing parameters (defaults from package)
    parameter int T_RAS_CYCLES   = sdram_pkg::T_RAS_CYCLES,
    parameter int T_RCD_CYCLES   = sdram_pkg::T_RCD_CYCLES,
    parameter int T_RP_CYCLES    = sdram_pkg::T_RP_CYCLES,
    parameter int T_WR_CYCLES    = sdram_pkg::T_WR_CYCLES,
    parameter int T_RFC_CYCLES   = sdram_pkg::T_RFC_CYCLES,
    parameter int T_MRD_CYCLES   = sdram_pkg::T_MRD_CYCLES,
    parameter int CAS_LATENCY    = sdram_pkg::CAS_LATENCY,
    parameter int BURST_LEN      = sdram_pkg::BURST_LEN
)(
    // System
    input  wire logic                               clk_i,
    input  wire logic                               clk_sh_i, // Phase shifted clock for SDRAM
    input  wire logic                               rst_ni,
    input  wire logic                               error_clear_i,

    // Command Interface
    input  sdram_cmd_t                              wr_cmd_data_i,
    input  wire logic                               wr_cmd_valid_i,
    output      logic                               wr_cmd_ready_o,
    input  sdram_cmd_t                              rd_cmd_data_i,
    input  wire logic                               rd_cmd_valid_i,
    output      logic                               rd_cmd_ready_o,

    // Data Interface (Write)
    input  wire logic [sdram_pkg::DATA_WIDTH-1:0]   wdata_i,
    input  wire logic [sdram_pkg::DATA_WIDTH/8-1:0] wdata_be_i,
    input  wire logic                               wdata_valid_i,
    output      logic                               wdata_ready_o,
    output      logic [CFifoAddrWidth:0]            wdata_level_o,

    // Data Interface (Read)
    output      logic [sdram_pkg::DATA_WIDTH-1:0]   rdata_o,
    output      logic                               rdata_valid_o,
    input  wire logic                               rdata_ready_i,
    output      logic [CFifoAddrWidth:0]            rdata_level_o,

    // Physical SDRAM Interface
    output      logic [sdram_pkg::ROW_ADDR_WIDTH-1:0]  sdram_addr_o,
    output      logic [sdram_pkg::BANK_ADDR_WIDTH-1:0] sdram_ba_o,
    output      logic                                  sdram_cs_n_o,
    output      logic                                  sdram_ras_n_o,
    output      logic                                  sdram_cas_n_o,
    output      logic                                  sdram_we_n_o,
    inout  wire logic [sdram_pkg::DATA_WIDTH-1:0]      sdram_dq_io,
    output      logic [sdram_pkg::DATA_WIDTH/8-1:0]    sdram_dqm_o,
    output      logic                                  sdram_cke_o,
    output      logic                                  sdram_clk_o,

    // Diagnostics
    output      logic                                  busy_o,
    output      logic [1:0]                            fifo_error_o
);

    // -------------------------------------------------------------------------
    // 1. Konštanty a Typy
    // -------------------------------------------------------------------------
    localparam int C_AP_BIT_INDEX = 10; // Auto-Precharge bit index (A10)
    localparam int C_NUM_BANKS    = 1 << sdram_pkg::BANK_ADDR_WIDTH;
    localparam int C_BE_WIDTH     = sdram_pkg::DATA_WIDTH / 8;

    // -------------------------------------------------------------------------
    // 2. Interné signály
    // -------------------------------------------------------------------------
    // Skid Buffer Interconnect
    logic [sdram_pkg::DATA_WIDTH-1:0] skid_wdata;
    logic [C_BE_WIDTH-1:0]            skid_wdata_be;
    logic                             skid_wdata_valid, skid_wdata_ready;
    logic [sdram_pkg::DATA_WIDTH-1:0] fifo_rdata;
    logic                             fifo_rdata_valid, fifo_rdata_ready;

    // FSM States
    typedef enum logic [5:0] {
        INIT_START, INIT_WAIT, INIT_PRECHARGE_CMD, INIT_PRECHARGE_WAIT,
        INIT_REFRESH1_CMD, INIT_REFRESH1_WAIT, INIT_REFRESH2_CMD, INIT_REFRESH2_WAIT,
        INIT_MRS_CMD, INIT_MRS_WAIT, IDLE, EVAL_BANK, EVAL_PRECHARGE,
        ACTIVATE_CMD, WAIT_TRCD, READ_CMD, WRITE_CMD, READ_BURST, WRITE_BURST,
        PRECHARGE_CMD, REFRESH_CMD
    } state_t;

    state_t state_reg, state_next;

    // Timers & Counters
    logic load_trp, load_trcd, load_twr, load_trfc, load_init, load_trmrd;
    logic trp_done, trcd_done, twr_done, trfc_done, init_done, trmrd_done;
    
    logic [$clog2(T_RAS_CYCLES+1)-1:0] tras_timer [C_NUM_BANKS];
    logic load_tras [C_NUM_BANKS];
    
    logic [$clog2(sdram_pkg::REFRESH_INTERVAL_CYCLES+1)-1:0] refresh_counter, refresh_counter_next;
    logic refresh_pending, refresh_pending_next;
    
    logic [$clog2(BURST_LEN):0] burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0] cas_cnt, cas_cnt_next;

    // Control Logic
    sdram_cmd_t current_cmd, selected_cmd;
    logic selected_cmd_valid, fsm_ready_for_cmd;
    logic dq_oe, dq_oe_d;
    logic [sdram_pkg::DATA_WIDTH-1:0] dq_out_reg;
    logic [C_BE_WIDTH-1:0] dq_be_reg;

    // FIFO Control
    logic wr_fifo_full, wr_fifo_empty, wr_fifo_wr_en, wr_fifo_rd_en;
    logic wr_fifo_overflow, wr_fifo_underflow;
    logic [sdram_pkg::DATA_WIDTH-1:0] wr_fifo_rd_data;
    logic [C_BE_WIDTH-1:0] wr_fifo_rd_be;
    
    logic rd_fifo_full, rd_fifo_empty, rd_fifo_wr_en, rd_fifo_rd_en;
    logic rd_fifo_overflow, rd_fifo_underflow;

    // Bank Management
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state [C_NUM_BANKS], bank_state_next [C_NUM_BANKS];
    logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] active_row [C_NUM_BANKS], active_row_next [C_NUM_BANKS];
    logic all_banks_idle;
    
    // Error Handling
    logic [1:0] error_sticky;

    // Helper Structs
    typedef enum logic [2:0] { NOP, ACTIVE, READ, WRITE, PRECHARGE, REFRESH, MRS } cmd_type_e;
    typedef struct packed { logic cs, ras, cas, we; } sdram_cmd_pins_t;

    function automatic sdram_cmd_pins_t get_sdram_cmd(cmd_type_e cmd_type);
        case(cmd_type)
            ACTIVE:    return '{0,0,1,1};
            READ:      return '{0,1,0,1};
            WRITE:     return '{0,1,0,0};
            PRECHARGE: return '{0,0,1,0};
            REFRESH:   return '{0,0,0,1};
            MRS:       return '{0,0,0,0};
            default:   return '{1,1,1,1}; // NOP / Deselect
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // 3. Inštanciácia Submodulov
    // -------------------------------------------------------------------------

    // Write Path: Skid Buffer -> Async FIFO -> SDRAM
    skid_buffer #(.WIDTH(sdram_pkg::DATA_WIDTH + C_BE_WIDTH)) sb_write (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .s_valid_i (wdata_valid_i),
        .s_ready_o (wdata_ready_o),
        .s_data_i  ({wdata_be_i, wdata_i}),
        .m_valid_o (skid_wdata_valid),
        .m_ready_i (skid_wdata_ready),
        .m_data_o  ({skid_wdata_be, skid_wdata})
    );
    // FIFO je ready, ak nie je full
    assign skid_wdata_ready = !wr_fifo_full;

    // Read Path: SDRAM -> Async FIFO -> Skid Buffer
    skid_buffer #(.WIDTH(sdram_pkg::DATA_WIDTH)) sb_read (
        .clk_i     (clk_i),
        .rst_ni    (rst_ni),
        .s_valid_i (fifo_rdata_valid),
        .s_ready_o (fifo_rdata_ready),
        .s_data_i  (fifo_rdata),
        .m_valid_o (rdata_valid_o),
        .m_ready_i (rdata_ready_i),
        .m_data_o  (rdata_o)
    );

    sync_fifo #(
        .DATA_WIDTH(sdram_pkg::DATA_WIDTH), 
        .BE_WIDTH(C_BE_WIDTH), 
        .ADDR_WIDTH(CFifoAddrWidth)
    ) write_fifo (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .wr_en_i        (skid_wdata_valid),
        .wr_data_i      (skid_wdata),
        .wr_be_i        (skid_wdata_be),
        .wr_full_o      (wr_fifo_full),
        .wr_overflow_o  (wr_fifo_overflow),
        .rd_en_i        (wr_fifo_rd_en),
        .rd_data_o      (wr_fifo_rd_data),
        .rd_be_o        (wr_fifo_rd_be),
        .rd_empty_o     (wr_fifo_empty),
        .rd_underflow_o (wr_fifo_underflow),
        .level_o        (wdata_level_o)
    );

    sync_fifo #(
        .DATA_WIDTH(sdram_pkg::DATA_WIDTH), 
        .BE_WIDTH(C_BE_WIDTH), 
        .ADDR_WIDTH(CFifoAddrWidth)
    ) read_fifo (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .wr_en_i        (rd_fifo_wr_en),
        .wr_data_i      (sdram_dq_io),
        .wr_be_i        ('0), // Read path doesn't use BE
        .wr_full_o      (rd_fifo_full),
        .wr_overflow_o  (rd_fifo_overflow),
        .rd_en_i        (rd_fifo_rd_en),
        .rd_data_o      (fifo_rdata),
        .rd_be_o        (),
        .rd_empty_o     (rd_fifo_empty),
        .rd_underflow_o (rd_fifo_underflow),
        .level_o        (rdata_level_o)
    );

    assign fifo_rdata_valid = !rd_fifo_empty;
    assign rd_fifo_rd_en    = fifo_rdata_valid && fifo_rdata_ready;

    // -------------------------------------------------------------------------
    // 4. Timers (Count Down Timers)
    // -------------------------------------------------------------------------
    count_down_timer #(.COUNT_WIDTH($clog2(T_RP_CYCLES+1)), .DONE_REGISTERED(1))
    trp_timer (.clk_i(clk_i), .rst_ni(rst_ni), .load_i(load_trp), .load_val_i(T_RP_CYCLES), .done_o(trp_done));

    count_down_timer #(.COUNT_WIDTH($clog2(T_RCD_CYCLES+1)), .DONE_REGISTERED(1))
    trcd_timer (.clk_i(clk_i), .rst_ni(rst_ni), .load_i(load_trcd), .load_val_i(T_RCD_CYCLES), .done_o(trcd_done));

    count_down_timer #(.COUNT_WIDTH($clog2(T_WR_CYCLES+1)), .DONE_REGISTERED(1))
    twr_timer (.clk_i(clk_i), .rst_ni(rst_ni), .load_i(load_twr), .load_val_i(T_WR_CYCLES), .done_o(twr_done));

    count_down_timer #(.COUNT_WIDTH($clog2(T_RFC_CYCLES+1)), .DONE_REGISTERED(1))
    trfc_timer (.clk_i(clk_i), .rst_ni(rst_ni), .load_i(load_trfc), .load_val_i(T_RFC_CYCLES), .done_o(trfc_done));

    count_down_timer #(.COUNT_WIDTH($clog2(T_MRD_CYCLES+1)), .DONE_REGISTERED(1))
    trmrd_timer (.clk_i(clk_i), .rst_ni(rst_ni), .load_i(load_trmrd), .load_val_i(T_MRD_CYCLES), .done_o(trmrd_done));

    count_down_timer #(.COUNT_WIDTH($clog2(sdram_pkg::CInitWaitCycles+1)), .DONE_REGISTERED(1))
    init_timer (.clk_i(clk_i), .rst_ni(rst_ni), .load_i(load_init), .load_val_i(sdram_pkg::CInitWaitCycles), .done_o(init_done));

    // Bank Specific RAS timers (Active to Precharge limit)
    generate
        for (genvar i = 0; i < C_NUM_BANKS; i++) begin : g_bank_timers
            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) tras_timer[i] <= '0;
                else if (load_tras[i]) tras_timer[i] <= T_RAS_CYCLES;
                else if (tras_timer[i] > 0) tras_timer[i] <= tras_timer[i] - 1'b1;
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 5. Error Logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) error_sticky <= '0;
        else begin
            if (error_clear_i) error_sticky <= '0;
            if (wr_fifo_overflow | wr_fifo_underflow) error_sticky[1] <= 1;
            if (rd_fifo_overflow | rd_fifo_underflow) error_sticky[0] <= 1;
        end
    end

    // -------------------------------------------------------------------------
    // 6. Arbitration & Command Selection
    // -------------------------------------------------------------------------
    always_comb begin
        // FSM is ready if IDLE and no refresh is immediately pending (strict)
        fsm_ready_for_cmd = (state_reg == IDLE) && !refresh_pending && twr_done && trp_done;

        selected_cmd_valid = 0;
        selected_cmd       = '0;
        rd_cmd_ready_o     = 0;
        wr_cmd_ready_o     = 0;

        // Priorita: Read > Write (nastaviteľné)
        if (rd_cmd_valid_i) begin
            selected_cmd_valid = 1;
            selected_cmd       = rd_cmd_data_i;
            if (fsm_ready_for_cmd) rd_cmd_ready_o = 1;
        end else if (wr_cmd_valid_i) begin
            selected_cmd_valid = 1;
            selected_cmd       = wr_cmd_data_i;
            if (fsm_ready_for_cmd) wr_cmd_ready_o = 1;
        end
    end

    // -------------------------------------------------------------------------
    // 7. Main FSM (Sequential)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_reg        <= INIT_START;
            refresh_counter  <= sdram_pkg::REFRESH_INTERVAL_CYCLES;
            refresh_pending  <= 0;
            cas_cnt          <= '0;
            burst_cnt        <= '0;
            current_cmd      <= '0;
            dq_oe_d          <= 0;
            dq_out_reg       <= '0;
            dq_be_reg        <= '0;
            for (int i=0; i<C_NUM_BANKS; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
            end
        end else begin
            state_reg        <= state_next;
            burst_cnt        <= burst_cnt_next;
            cas_cnt          <= cas_cnt_next;
            refresh_counter  <= refresh_counter_next;
            refresh_pending  <= refresh_pending_next;

            if (fsm_ready_for_cmd && selected_cmd_valid) 
                current_cmd <= selected_cmd;

            for (int i=0; i<C_NUM_BANKS; i++) begin
                bank_state[i] <= bank_state_next[i];
                active_row[i] <= active_row_next[i];
            end

            dq_oe_d <= dq_oe;

            // Latch write data from FIFO
            if (wr_fifo_rd_en) begin
                dq_out_reg <= wr_fifo_rd_data;
                dq_be_reg  <= wr_fifo_rd_be;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 8. Main FSM (Combinatorial)
    // -------------------------------------------------------------------------
    always_comb begin
        sdram_cmd_pins_t cmd_pins;
        sdram_pkg::sdram_addr_t cmd_addr;

        // Defaults
        state_next           = state_reg;
        refresh_counter_next = refresh_counter;
        refresh_pending_next = refresh_pending;
        cas_cnt_next         = cas_cnt;
        burst_cnt_next       = burst_cnt;

        for (int i=0; i<C_NUM_BANKS; i++) begin
            bank_state_next[i] = bank_state[i];
            active_row_next[i] = active_row[i];
            load_tras[i]       = 0;
        end

        cmd_addr = current_cmd.addr;
        cmd_pins = get_sdram_cmd(NOP);

        sdram_addr_o = 0;
        sdram_ba_o   = 0;
        sdram_cke_o  = 1;

        load_trp  = 0; load_trcd  = 0; load_twr   = 0;
        load_trfc = 0; load_init  = 0; load_trmrd = 0;
        dq_oe     = 0;

        // --- Timers Logic ---
        if (cas_cnt > 0) cas_cnt_next = cas_cnt - 1;

        if (state_reg != REFRESH_CMD) begin
            if (refresh_counter > 0) refresh_counter_next = refresh_counter - 1;
            else refresh_pending_next = 1;
        end

        // FIFO Enables
        wr_fifo_rd_en = (state_reg == WRITE_BURST) && (burst_cnt > 0) && !wr_fifo_empty;
        rd_fifo_wr_en = (state_reg == READ_BURST) && (cas_cnt == 0) && (burst_cnt > 0) && !rd_fifo_full;

        all_banks_idle = 1;
        for (int i=0; i<C_NUM_BANKS; i++)
            if (bank_state[i] != BANK_IDLE) all_banks_idle = 0;

        // --- FSM States ---
        case (state_reg)
            INIT_START: begin
                load_init    = 1;
                sdram_cke_o  = 0; // Clock enable low during start
                state_next   = INIT_WAIT;
            end
            INIT_WAIT: begin
                sdram_cke_o = 0;
                if (init_done) state_next = INIT_PRECHARGE_CMD;
            end
            INIT_PRECHARGE_CMD: begin
                cmd_pins     = get_sdram_cmd(PRECHARGE);
                sdram_addr_o[C_AP_BIT_INDEX] = 1; // All banks
                load_trp     = 1;
                state_next   = INIT_PRECHARGE_WAIT;
            end
            INIT_PRECHARGE_WAIT: if (trp_done) state_next = INIT_REFRESH1_CMD;
            
            INIT_REFRESH1_CMD: begin
                cmd_pins     = get_sdram_cmd(REFRESH);
                load_trfc    = 1;
                state_next   = INIT_REFRESH1_WAIT;
            end
            INIT_REFRESH1_WAIT: if (trfc_done) state_next = INIT_REFRESH2_CMD;
            
            INIT_REFRESH2_CMD: begin
                cmd_pins     = get_sdram_cmd(REFRESH);
                load_trfc    = 1;
                state_next   = INIT_REFRESH2_WAIT;
            end
            INIT_REFRESH2_WAIT: if (trfc_done) state_next = INIT_MRS_CMD;
            
            INIT_MRS_CMD: begin
                cmd_pins     = get_sdram_cmd(MRS);
                sdram_addr_o = sdram_pkg::CMrsValueAddr;
                load_trmrd   = 1;
                state_next   = INIT_MRS_WAIT;
            end
            INIT_MRS_WAIT: if (trmrd_done) state_next = IDLE;

            IDLE: if (twr_done && trp_done) begin
                // Refresh has priority
                if (refresh_pending && all_banks_idle) state_next = REFRESH_CMD;
                else if (fsm_ready_for_cmd && selected_cmd_valid) state_next = EVAL_BANK;
            end

            EVAL_BANK: begin
                if (bank_state[cmd_addr.bank] == BANK_IDLE) begin
                    if (trp_done) state_next = ACTIVATE_CMD;
                end else begin
                    // Bank is active
                    if (active_row[cmd_addr.bank] == cmd_addr.row)
                        state_next = trcd_done ? (current_cmd.rw ? WRITE_CMD : READ_CMD) : WAIT_TRCD;
                    else
                        state_next = EVAL_PRECHARGE; // Row miss -> Precharge
                end
            end

            EVAL_PRECHARGE: if (tras_timer[cmd_addr.bank] == 0) state_next = PRECHARGE_CMD;

            ACTIVATE_CMD: begin
                cmd_pins                       = get_sdram_cmd(ACTIVE);
                sdram_ba_o                     = cmd_addr.bank;
                sdram_addr_o                   = cmd_addr.row;
                load_trcd                      = 1;
                load_tras[cmd_addr.bank]       = 1;
                bank_state_next[cmd_addr.bank] = BANK_ACTIVE;
                active_row_next[cmd_addr.bank] = cmd_addr.row;
                state_next                     = WAIT_TRCD;
            end

            WAIT_TRCD: if (trcd_done) begin
                if (bank_state[cmd_addr.bank] == BANK_IDLE || active_row[cmd_addr.bank] != cmd_addr.row)
                    state_next = EVAL_BANK; // Should not happen logically if controlled correctly
                else
                    state_next = current_cmd.rw ? WRITE_CMD : READ_CMD;
            end

            READ_CMD: begin
                cmd_pins                                    = get_sdram_cmd(READ);
                sdram_ba_o                                  = cmd_addr.bank;
                sdram_addr_o[sdram_pkg::COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr_o[C_AP_BIT_INDEX]                = current_cmd.auto_precharge;
                
                cas_cnt_next                                = CAS_LATENCY;
                burst_cnt_next                              = BURST_LEN;
                
                if (current_cmd.auto_precharge) begin
                    bank_state_next[cmd_addr.bank] = BANK_IDLE;
                    load_trp                       = 1; // Precharge happens automatically
                end
                state_next = READ_BURST;
            end

            WRITE_CMD: begin
                cmd_pins                                    = get_sdram_cmd(WRITE);
                sdram_ba_o                                  = cmd_addr.bank;
                sdram_addr_o[sdram_pkg::COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                sdram_addr_o[C_AP_BIT_INDEX]                = current_cmd.auto_precharge;
                
                burst_cnt_next                              = BURST_LEN;
                
                if (current_cmd.auto_precharge) begin
                    bank_state_next[cmd_addr.bank] = BANK_IDLE;
                    load_twr                       = 1; // Recovery time after write
                    load_trp                       = 1;
                end
                state_next = WRITE_BURST;
            end

            READ_BURST: if (cas_cnt == 0) begin
                // Reading data from SDRAM to FIFO happens via rd_fifo_wr_en logic above
                if (burst_cnt > 0 && !rd_fifo_full) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && !rd_fifo_full) state_next = IDLE;
            end

            WRITE_BURST: begin
                dq_oe = 1;
                if (burst_cnt > 0 && !wr_fifo_empty) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && !wr_fifo_empty) begin
                    load_twr   = 1;
                    state_next = IDLE;
                end
            end

            PRECHARGE_CMD: begin
                cmd_pins                       = get_sdram_cmd(PRECHARGE);
                sdram_ba_o                     = cmd_addr.bank;
                load_trp                       = 1;
                bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next                     = IDLE; // Wait for TRP in IDLE
            end

            REFRESH_CMD: begin
                cmd_pins             = get_sdram_cmd(REFRESH);
                load_trfc            = 1;
                refresh_pending_next = 0;
                refresh_counter_next = sdram_pkg::REFRESH_INTERVAL_CYCLES;
                state_next           = IDLE; // Wait for TRFC in IDLE
            end

            default: state_next = IDLE;
        endcase

        // Output Mapping
        sdram_cs_n_o  = cmd_pins.cs;
        sdram_ras_n_o = cmd_pins.ras;
        sdram_cas_n_o = cmd_pins.cas;
        sdram_we_n_o  = cmd_pins.we;
        
        // DQM Logic: Active High mask. If OE is active, use BE from FIFO (inverted).
        // If OE is inactive (Read), DQM should be Low to enable output.
        sdram_dqm_o   = dq_oe_d ? (wr_fifo_empty ? {C_BE_WIDTH{1'b1}} : ~dq_be_reg) : '0;
    end

    // Tri-state Buffer
    assign sdram_dq_io = dq_oe_d ? dq_out_reg : {sdram_pkg::DATA_WIDTH{1'bz}};
    assign sdram_clk_o = clk_sh_i;
    assign busy_o      = (state_reg != IDLE);
    assign fifo_error_o = error_sticky;

endmodule

`endif // SDRAM_CTRL_SV

`default_nettype wire

