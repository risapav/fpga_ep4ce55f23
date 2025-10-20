`ifndef SDRAM_CONTROLLER_REF
`define SDRAM_CONTROLLER_REF

(* default_nettype = "none" *)

module SdramController #(
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
        if (ASYNC_RESET) begin
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
        end else begin
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

`endif
