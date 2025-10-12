`ifndef SDRAM_CTRL_SV
`define SDRAM_CTRL_SV

`default_nettype none

module SdramController #(
    parameter CLOCK_FREQ_HZ  = 100_000_000,
    parameter ADDR_WIDTH     = 24,
    parameter DATA_WIDTH     = 16,
    parameter BURST_LEN      = 8,
    parameter NUM_BANKS      = 4,
    parameter CMD_BUF_DEPTH  = 8,
    parameter tRP            = 3,
    parameter tRCD           = 3,
    parameter tWR            = 2,
    parameter tRFC           = 9,
    parameter tRAS           = 7,
    parameter CAS_LATENCY    = 3
)(
    input  wire                   clk,
    input  wire                   clk_sh,
    input  wire                   rstn,
    input  wire                   cmd_fifo_valid,
    output reg                    cmd_fifo_ready,
    input  wire [ADDR_WIDTH-1:0]  cmd_fifo_data_addr,
    input  wire [1:0]             cmd_fifo_data_rw,
    input  wire                   resp_ready,
    output reg                    resp_valid,
    output reg                    resp_last,
    output reg  [DATA_WIDTH-1:0]  resp_data,
    input  wire                   wdata_valid,
    input  wire [DATA_WIDTH-1:0]  wdata,
    input  wire [1:0]             wdata_dqm_i,
    output reg                    wdata_ready,
    output reg  [12:0]            sdram_addr,
    output reg  [1:0]             sdram_ba,
    output reg                    sdram_cs_n,
    output reg                    sdram_ras_n,
    output reg                    sdram_cas_n,
    output reg                    sdram_we_n,
    inout  wire [DATA_WIDTH-1:0]  sdram_dq,
    output reg  [1:0]             sdram_dqm,
    output reg                    sdram_cke,
    output wire                   sdram_clk
);
// Quartus-safe local alias of sdram_cmd_t with module parameters
typedef struct packed {
    rw_cmd_e               rw;
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] wdata;
    logic                  auto_precharge_en;
} sdram_cmd_t;

    // --- PARAMETRE ---
    localparam integer C_COLS = 9;
    localparam integer MAX_CAS_LATENCY = 8;
    localparam integer REFRESH_INTERVAL = 781;

    // --- ENUMY ---
    localparam [4:0]
        INIT_WAIT       = 5'd0,
        INIT_PRECHARGE  = 5'd1,
        INIT_REFRESH    = 5'd2,
        INIT_MRS        = 5'd3,
        IDLE            = 5'd4,
        ACTIVE_CMD      = 5'd5,
        ACTIVE_WAIT     = 5'd6,
        PREFETCH_WDATA  = 5'd7,
        RW_CMD          = 5'd8,
        READ_BURST      = 5'd9,
        WRITE_BURST     = 5'd10,
        PRECHARGE_CMD   = 5'd11,
        REFRESH_CMD     = 5'd12;

    localparam [1:0]
        BANK_IDLE        = 2'd0,
        BANK_ACTIVE      = 2'd1,
        BANK_PRECHARGING = 2'd2;

    // --- REGISTRE ---
    reg [4:0] state_reg, state_next;

    reg [1:0]  bank_state   [0:NUM_BANKS-1];
    reg [C_COLS-1:0] bank_open_row [0:NUM_BANKS-1];
    reg        bank_open_valid [0:NUM_BANKS-1];

    reg [7:0]  trcd_timer, trp_timer, twr_timer, trfc_timer, cas_cnt;
    reg [7:0]  burst_cnt;
    reg [8:0]  col_addr_reg;

    reg [ADDR_WIDTH-1:0] cmd_buf_addr [0:CMD_BUF_DEPTH-1];
    reg [1:0]  cmd_buf_rw     [0:CMD_BUF_DEPTH-1];
    reg        cmd_buf_valid  [0:CMD_BUF_DEPTH-1];
    reg [3:0]  cmd_buf_count;

    reg [DATA_WIDTH-1:0] read_pipe_data [0:MAX_CAS_LATENCY-1];
    reg [MAX_CAS_LATENCY-1:0] read_pipe_valid, read_pipe_last;

    // Scheduler
    reg [$clog2(CMD_BUF_DEPTH)-1:0] selected_idx, selected_idx_next;
    reg selected_valid, selected_valid_next;

    // Control signals
    reg load_trcd, load_trp, load_twr, load_trfc, load_cas_cnt;
    reg dq_write_enable, dq_write_enable_d;
    reg decrement_burst;
    reg refresh_pending;

    integer i;
    integer best, best_score, sc, b;

    // --- SEKVENČNÁ LOGIKA ---
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            trcd_timer <= 0; trp_timer <= 0; twr_timer <= 0; trfc_timer <= 0;
            cas_cnt <= 0; burst_cnt <= 0;
            dq_write_enable_d <= 0;
            refresh_pending <= 0;
            selected_idx <= 0;
            selected_valid <= 0;
            for (i = 0; i < NUM_BANKS; i = i + 1) begin
                bank_state[i] <= BANK_IDLE;
                bank_open_row[i] <= 0;
                bank_open_valid[i] <= 0;
            end
            for (i = 0; i < CMD_BUF_DEPTH; i = i + 1) begin
                cmd_buf_valid[i] <= 0;
            end
        end else begin
            state_reg <= state_next;
            dq_write_enable_d <= dq_write_enable;
            selected_idx <= selected_idx_next;
            selected_valid <= selected_valid_next;

            if (load_trcd) trcd_timer <= tRCD;
            else if (trcd_timer > 0) trcd_timer <= trcd_timer - 1;

            if (load_trp) trp_timer <= tRP;
            else if (trp_timer > 0) trp_timer <= trp_timer - 1;

            if (load_twr) twr_timer <= tWR;
            else if (twr_timer > 0) twr_timer <= twr_timer - 1;

            if (load_trfc) trfc_timer <= tRFC;
            else if (trfc_timer > 0) trfc_timer <= trfc_timer - 1;

            if (load_cas_cnt) cas_cnt <= CAS_LATENCY;
            else if (cas_cnt > 0) cas_cnt <= cas_cnt - 1;

            if (state_next == RW_CMD)
                burst_cnt <= BURST_LEN - 1;
            else if (decrement_burst)
                burst_cnt <= burst_cnt - 1;

            // ACTIVATE update
            if (load_trcd) begin
                b = cmd_buf_addr[selected_idx][23:22];
                bank_state[b] <= BANK_ACTIVE;
                bank_open_valid[b] <= 1'b1;
                bank_open_row[b] <= cmd_buf_addr[selected_idx][21:9];
            end

            // PRECHARGE clear
            if (load_trp) begin
                for (i = 0; i < NUM_BANKS; i = i + 1) begin
                    bank_state[i] <= BANK_PRECHARGING;
                    bank_open_valid[i] <= 1'b0;
                end
            end
            if (trp_timer == 1) begin
                for (i = 0; i < NUM_BANKS; i = i + 1)
                    if (bank_state[i] == BANK_PRECHARGING) bank_state[i] <= BANK_IDLE;
            end
        end
    end

    // --- KOMBINÁČNÁ LOGIKA ---
    always @(*) begin
        // defaulty
        state_next = state_reg;
        cmd_fifo_ready = 1'b1;
        dq_write_enable = 1'b0;
        wdata_ready = 1'b0;
        decrement_burst = 1'b0;
        load_trcd = 1'b0; load_trp = 1'b0; load_twr = 1'b0;
        load_trfc = 1'b0; load_cas_cnt = 1'b0;

        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1;
        sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_cke = 1'b1; sdram_dqm = 2'b00;
        sdram_addr = 13'd0; sdram_ba = 2'b00;

        selected_valid_next = 0;
        selected_idx_next = 0;

        // --- scheduler ---
        best = -1;
        best_score = -1;
        for (i = 0; i < CMD_BUF_DEPTH; i = i + 1) begin
            if (cmd_buf_valid[i]) begin
                b = cmd_buf_addr[i][23:22];
                if (bank_state[b] == BANK_ACTIVE && bank_open_valid[b] && bank_open_row[b] == cmd_buf_addr[i][21:9])
                    sc = 3;
                else if (bank_state[b] == BANK_IDLE)
                    sc = 2;
                else
                    sc = 1;
                if (sc > best_score) begin
                    best_score = sc;
                    best = i;
                end
            end
        end
        if (best != -1) begin
            selected_valid_next = 1;
            selected_idx_next = best;
        end

        // --- FSM ---
        case (state_reg)
            INIT_WAIT: state_next = INIT_PRECHARGE;
            INIT_PRECHARGE: begin
                sdram_cs_n = 0; sdram_ras_n = 0; sdram_we_n = 0;
                sdram_addr[10] = 1'b1;
                load_trp = 1'b1;
                state_next = INIT_REFRESH;
            end
            INIT_REFRESH: begin
                sdram_cs_n = 0; sdram_ras_n = 0; sdram_cas_n = 0;
                load_trfc = 1'b1;
                state_next = INIT_MRS;
            end
            INIT_MRS: begin
                sdram_cs_n = 0; sdram_ras_n = 0; sdram_cas_n = 0; sdram_we_n = 0;
                sdram_ba = 0;
                sdram_addr = {3'b000, 1'b0, 2'b00, 1'b0, 3'b011};
                state_next = IDLE;
            end
            IDLE: begin
                if (selected_valid_next) state_next = ACTIVE_CMD;
            end
            ACTIVE_CMD: begin
                sdram_cs_n = 0; sdram_ras_n = 0;
                load_trcd = 1'b1;
                state_next = ACTIVE_WAIT;
            end
            ACTIVE_WAIT: if (trcd_timer == 0) state_next = RW_CMD;
            RW_CMD: begin
                sdram_cs_n = 0; sdram_cas_n = 0;
                sdram_ba = cmd_buf_addr[selected_idx][23:22];
                sdram_addr = {cmd_buf_addr[selected_idx][12:0]};
                state_next = READ_BURST;
            end
            READ_BURST: begin
                dq_write_enable = 0;
                if (burst_cnt == 0) state_next = IDLE;
            end
            WRITE_BURST: begin
                dq_write_enable = 1;
                if (burst_cnt == 0) state_next = IDLE;
            end
            PRECHARGE_CMD: begin
                sdram_cs_n = 0; sdram_ras_n = 0; sdram_we_n = 0;
                sdram_addr[10] = 1'b1;
                load_trp = 1'b1;
                state_next = IDLE;
            end
            REFRESH_CMD: begin
                sdram_cs_n = 0; sdram_ras_n = 0; sdram_cas_n = 0;
                load_trfc = 1'b1;
                state_next = IDLE;
            end
            default: state_next = IDLE;
        endcase
    end

    assign sdram_dq = dq_write_enable_d ? wdata : {DATA_WIDTH{1'bz}};
    assign sdram_clk = clk_sh;

endmodule

`default_nettype wire
`endif
