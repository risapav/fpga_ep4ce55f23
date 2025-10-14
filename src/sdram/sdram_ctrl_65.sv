// sdram_controller.sv - Verzia 6.5 - Opravená na základe expertnej analýzy
// Zmeny (v6.5):
// 1. OPRAVA (wdata_ready): Správne nastavenie `wdata_ready` v stave WRITE_BURST.
// 2. OPRAVA (Read Pipe): Zavedený backpressure pre read pipeline pomocou `resp_ready`.
// 3. OPRAVA (DQ Drive): Zabezpečené držanie DQ zbernice počas celého `tWR` timingu.
// 4. REFAKTOR (Refresh): Logika pre refresh prepracovaná na spoľahlivejší down-counter.
// 5. REFAKTOR (MRS): Hodnota pre Mode Register Set je teraz plne parametrizovaná.

`ifndef SDRAM_CTRL_SV
`define SDRAM_CTRL_SV

(* default_nettype = "none" *)

module SdramController #(
    parameter CLOCK_FREQ_HZ  = 100_000_000,
    parameter ADDR_WIDTH     = 24,
    parameter DATA_WIDTH     = 16,
    parameter BURST_LEN      = 8,
    parameter int NUM_BANKS  = 4,
    parameter int tRP          = 3,
    parameter int tRCD         = 3,
    parameter int tWR          = 2,
    parameter int tRFC         = 9,
    parameter int tRAS         = 7,
    parameter int CAS_LATENCY  = 3
)(
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
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [1:0]               wdata_dqm_i,
    output logic                     wdata_ready,
    output logic [12:0]              sdram_addr,
    output logic [1:0]               sdram_ba,
    output logic                     sdram_cs_n,
    output logic                     sdram_ras_n,
    output logic                     sdram_cas_n,
    output logic                     sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0]    sdram_dq,
    output logic [1:0]               sdram_dqm,
    output logic                     sdram_cke,
    output logic                     sdram_clk,

    output logic [$clog2(BURST_LEN+1)-1:0] debug_burst_cnt_o,
    output logic                          debug_refresh_pending_o,
    output logic                          debug_auto_precharge_o,
    output state_t                        debug_state_o
);

    import sdram_pkg::*;

    localparam int NS_PER_SEC         = 1_000_000_000;
    localparam int CLK_PERIOD_NS      = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam int WAIT_TIME_NS       = 200_000; // 200 us
    localparam int INIT_WAIT_CYCLES   = WAIT_TIME_NS / CLK_PERIOD_NS;

    localparam int REFRESH_INTERVAL = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam int C_COLS = 9;
    localparam int MAX_CAS_LATENCY = 8;

    // OPRAVA (v6.5): MRS hodnota je teraz parametrizovaná podľa BURST_LEN a CAS_LATENCY.
    // Pôvodná hodnota bola hard-coded a mala chybu v kódovaní CAS latencie.
    localparam logic [2:0] burst_len_bits =
        (BURST_LEN == 1) ? 3'b000 :
        (BURST_LEN == 2) ? 3'b001 :
        (BURST_LEN == 4) ? 3'b010 :
        (BURST_LEN == 8) ? 3'b011 : 3'b111; // Chyba/Nepodporované

    localparam logic [2:0] cas_latency_bits =
        (CAS_LATENCY == 2) ? 3'b010 :
        (CAS_LATENCY == 3) ? 3'b011 : 3'b000; // Chyba/Nepodporované

    localparam logic [12:0] mrs_value = {
        3'b000,              // A12:A10 - Reserved
        1'b0,                // A9      - Write Burst Mode: Programmed Length
        2'b00,               // A8:A7   - Standard Operation
        cas_latency_bits,    // A6:A4   - CAS Latency
        1'b0,                // A3      - Burst Type: Sequential
        burst_len_bits       // A2:A0   - Burst Length
    };

    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH, INIT_MRS,
        IDLE, ACTIVE_CMD, ACTIVE_WAIT, PREFETCH_WDATA, RW_CMD,
        READ_BURST, WRITE_BURST,
        PRECHARGE_CMD, REFRESH_CMD
    } state_t;

    // --- Registre (sekvenčné) ---
    state_t state_reg;
    sdram_cmd_t current_cmd;
    logic [$clog2(INIT_WAIT_CYCLES+1)-1:0]   init_timer;
    logic [$clog2(tRCD+1)-1:0]               trcd_timer;
    logic [$clog2(tRP+1)-1:0]                trp_timer;
    logic [$clog2(tWR+1)-1:0]                twr_timer;
    logic [$clog2(tRFC+1)-1:0]               trfc_timer;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0]   refresh_counter;
    logic [$clog2(BURST_LEN+1)-1:0]          burst_cnt;
    logic [C_COLS-1:0]                       col_addr_reg;
    logic [$clog2(MAX_CAS_LATENCY):0]        cas_cnt;
    logic [MAX_CAS_LATENCY-1:0]              read_pipe_valid, read_pipe_last;
    logic [DATA_WIDTH-1:0]                   read_pipe_data [0:MAX_CAS_LATENCY-1];
    logic                                    auto_precharge_pending;
    logic [1:0]                              auto_precharge_bank;
    logic                                    refresh_pending;
    logic                                    dq_write_enable;
    logic                                    dq_write_enable_d;

    // --- Kombinačné signály ---
    state_t state_next;
    logic load_trcd, load_trp, load_twr, load_trfc, load_cas_cnt;
    logic decrement_burst;
    logic auto_precharge_pending_next;
    logic [1:0] auto_precharge_bank_next;
    logic last_read_beat;
    logic refresh_pending_next;

    // --- Signály pre opravy a vylepšenia (v6.5) ---
    logic dq_keep_drive;  // Pre správne držanie DQ počas tWR
    logic pipe_can_shift; // Pre backpressure na read pipeline

    // --- Sekvenčný Blok (Srdce) ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state_reg              <= INIT_WAIT;
            init_timer             <= INIT_WAIT_CYCLES;
            trcd_timer             <= '0; trp_timer <= '0; twr_timer <= '0; trfc_timer <= '0;
            burst_cnt              <= '0; current_cmd <= '0; col_addr_reg <= '0;
            cas_cnt                <= '0;
            read_pipe_valid        <= '0; read_pipe_last  <= '0;
            auto_precharge_pending <= 1'b0; auto_precharge_bank <= '0;
            refresh_pending        <= 1'b0;
            dq_write_enable_d      <= 1'b0;
            refresh_counter        <= REFRESH_INTERVAL; // REFAKTOR (v6.5): Init pre down-counter
        end else begin
            state_reg <= state_next;

            // timers
            if (init_timer > 0) init_timer <= init_timer - 1;
            if (load_trcd) trcd_timer <= tRCD; else if (trcd_timer > 0) trcd_timer <= trcd_timer - 1;
            if (load_trp)  trp_timer  <= tRP;  else if (trp_timer > 0)  trp_timer  <= trp_timer - 1;
            if (load_twr)  twr_timer  <= tWR;  else if (twr_timer > 0)  twr_timer  <= twr_timer - 1;
            if (load_trfc) trfc_timer <= tRFC; else if (trfc_timer > 0) trfc_timer <= trfc_timer - 1;
            if (load_cas_cnt) cas_cnt <= CAS_LATENCY; else if (cas_cnt > 0) cas_cnt <= cas_cnt - 1;

            // REFAKTOR (v6.5): Refresh logika nahradená spoľahlivejším down-counterom.
            if (state_next == REFRESH_CMD) begin
                refresh_pending <= 1'b0;
                refresh_counter <= REFRESH_INTERVAL;
            end else if (refresh_counter == 0) begin
                refresh_pending <= 1'b1;
            end else begin
                refresh_counter <= refresh_counter - 1;
            end

            if (cmd_fifo_ready && cmd_fifo_valid) current_cmd <= cmd_fifo_data;

            if (state_next == RW_CMD) begin
                burst_cnt    <= BURST_LEN - 1;
                col_addr_reg <= current_cmd.addr[8:0];
            end else if (decrement_burst) begin
                burst_cnt    <= burst_cnt - 1;
                col_addr_reg <= col_addr_reg + 1;
            end

            auto_precharge_pending <= auto_precharge_pending_next;
            auto_precharge_bank    <= auto_precharge_bank_next;

            // OPRAVA (v6.5): Shiftovanie pipeline je teraz podmienené signálom `pipe_can_shift`,
            // ktorý implementuje backpressure, ak odberateľ nie je pripravený (`resp_ready`==0).
            // UPOZORNENIE: Toto jednoduché riešenie nezabraňuje strate dát na VSTUPE do pipeline,
            // ak je `resp_ready` držané na nízkej úrovni dlhšie, ako je hĺbka pipeline.
            // Robustné riešenie by vyžadovalo implementáciu FIFO buffera.
            if (pipe_can_shift) begin
                // pipeline shift
                read_pipe_valid <= {read_pipe_valid[MAX_CAS_LATENCY-2:0], 1'b0};
                read_pipe_last  <= {read_pipe_last[MAX_CAS_LATENCY-2:0], 1'b0};
                for (integer i = MAX_CAS_LATENCY-1; i > 0; i = i - 1) read_pipe_data[i] <= read_pipe_data[i-1];

                // vloženie dát do pipe pri read
                if ((state_reg == READ_BURST) && (cas_cnt == 0)) begin
                    read_pipe_valid[0] <= 1'b1;
                    read_pipe_data[0]  <= sdram_dq;
                    read_pipe_last[0]  <= last_read_beat;
                end else begin
                    read_pipe_valid[0] <= 1'b0;
                    read_pipe_last[0]  <= 1'b0;
                end
            end

            // OPRAVA (v6.5): DQ sa drží aktívne aj počas `tWR` timingu po zápise.
            dq_write_enable_d <= dq_keep_drive;
        end
    end

    // --- Kombinačný Blok (Mozog) ---
    always_comb begin
        state_next = state_reg;
        cmd_fifo_ready = 1'b0; wdata_ready = 1'b0;
        dq_write_enable = 1'b0; decrement_burst = 1'b0;
        load_trcd = 1'b0; load_trp = 1'b0; load_twr = 1'b0; load_trfc = 1'b0; load_cas_cnt = 1'b0;
        auto_precharge_pending_next = auto_precharge_pending;
        auto_precharge_bank_next    = auto_precharge_bank;
        last_read_beat = 1'b0;
        refresh_pending_next = refresh_pending;

        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1; sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_addr = '0; sdram_ba = '0; sdram_dqm = 2'b00; sdram_cke = 1'b1;

        // Priradenia pre opravy (v6.5)
        pipe_can_shift = resp_ready || !read_pipe_valid[CAS_LATENCY-1];
        dq_keep_drive = dq_write_enable || (twr_timer > 0);

        // --- FSM ---
        case (state_reg)
            INIT_WAIT: if (init_timer == 0) state_next = INIT_PRECHARGE; else sdram_cke = 1'b0;
            INIT_PRECHARGE: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_addr[10] = 1'b1;
                load_trp = 1'b1; state_next = INIT_REFRESH;
            end
            INIT_REFRESH: if (trp_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                load_trfc = 1'b1; state_next = INIT_MRS;
            end
            INIT_MRS: if (trfc_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0; sdram_we_n = 1'b0;
                sdram_ba = '0;
                sdram_addr = mrs_value; // OPRAVA (v6.5): Použitie parametrizovanej hodnoty
                state_next = IDLE;
            end

            IDLE: begin
                if (trp_timer > 0 || twr_timer > 0 || trfc_timer > 0) state_next = IDLE;
                else if (auto_precharge_pending) state_next = PRECHARGE_CMD;
                else if (refresh_pending) state_next = REFRESH_CMD;
                else begin
                    cmd_fifo_ready = 1'b1;
                    if (cmd_fifo_valid) begin
                        state_next = ACTIVE_CMD;
                    end
                end
            end

            ACTIVE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0;
                sdram_ba   = current_cmd.addr[23:22];
                sdram_addr = current_cmd.addr[21:9];
                load_trcd = 1'b1;
                state_next = ACTIVE_WAIT;
            end

            ACTIVE_WAIT: begin
                if (trcd_timer == 0) begin
                    if (current_cmd.rw == WRITE_CMD) begin
                        state_next = PREFETCH_WDATA;
                    end else begin // READ_CMD
                        state_next = RW_CMD;
                    end
                end
            end

            PREFETCH_WDATA: begin
                if (wdata_valid) state_next = RW_CMD;
                else wdata_ready = 1'b1;
            end

            RW_CMD: begin
                sdram_cs_n = 1'b0; sdram_cas_n = 1'b0;
                if (current_cmd.rw == WRITE_CMD) sdram_we_n = 1'b0; else sdram_we_n = 1'b1;

                sdram_ba   = current_cmd.addr[23:22];
                sdram_addr = {1'b1, 1'b0, 2'b00, current_cmd.addr[8:0]};

                if (current_cmd.rw == WRITE_CMD) begin
                    dq_write_enable = 1'b1; sdram_dqm = wdata_dqm_i;
                    state_next      = WRITE_BURST;
                end else begin
                    load_cas_cnt = 1'b1; state_next = READ_BURST;
                end
            end

            READ_BURST: begin
                last_read_beat = (burst_cnt == 0);
                if (cas_cnt == 0) begin
                    // `decrement_burst` je podmienené `resp_ready`, aby sa počkalo na odberateľa
                    if (resp_ready) begin
                        decrement_burst = 1'b1;
                    end
                end
                if (last_read_beat && resp_ready && (cas_cnt == 0)) begin
                    auto_precharge_pending_next = 1'b1;
                    auto_precharge_bank_next    = current_cmd.addr[23:22];
                    state_next = IDLE;
                end
            end

            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                // OPRAVA (v6.5): Controller musí byť vždy pripravený prijať dáta v tomto stave.
                // Pôvodná logika `wdata_ready = (wdata_valid)` bola chyba.
                wdata_ready = 1'b1;
                sdram_dqm = wdata_dqm_i;
                if (wdata_valid) begin
                    decrement_burst = 1'b1;
                end
                if ((burst_cnt == 0) && wdata_valid) begin
                    load_twr = 1'b1;
                    auto_precharge_pending_next = 1'b1;
                    auto_precharge_bank_next    = current_cmd.addr[23:22];
                    state_next = IDLE;
                end
            end

            PRECHARGE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0;
                sdram_addr[10] = 1'b1; // Precharge ALL banks
                load_trp = 1'b1;
                auto_precharge_pending_next = 1'b0;
                state_next = IDLE;
            end

            REFRESH_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0;
                load_trfc = 1'b1;
                state_next = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end

    // --- výstupy a priradenia ---
    assign resp_valid = read_pipe_valid[CAS_LATENCY-1];
    assign resp_last  = read_pipe_last[CAS_LATENCY-1];
    assign resp_data  = read_pipe_data[CAS_LATENCY-1];

    assign sdram_dq   = (dq_write_enable_d) ? wdata : {DATA_WIDTH{1'bz}};
    assign sdram_clk  = clk_sh;

    assign debug_burst_cnt_o = burst_cnt;
    assign debug_refresh_pending_o = refresh_pending;
    assign debug_auto_precharge_o = auto_precharge_pending;
    assign debug_state_o = state_reg;

    // --- jednoduché runtime checks ---
    always_ff @(posedge clk) begin
        if (!rstn) begin end
        else begin
            if ((state_reg == RW_CMD) && (trcd_timer > 0)) begin
                $error("[%0t] TIMING ERROR: RW_CMD entered with trcd_timer=%0d", $time, trcd_timer);
            end
            if ((state_reg == ACTIVE_CMD) && (trp_timer > 0)) begin
                $error("[%0t] TIMING ERROR: ACTIVE_CMD while trp_timer=%0d", $time, trp_timer);
            end
        end
    end

endmodule

`default_nettype wire

`endif
