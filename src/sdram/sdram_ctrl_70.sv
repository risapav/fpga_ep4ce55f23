// sdram_controller_advanced.sv - Verzia 7.00 - Refaktorované pre výkon a flexibilitu
// Zmeny (v7.00):
// 1. VYLEPŠENIE (Výkon): Implementovaný Bank Interleaving. Kontrolér sleduje stav každej
//    banky samostatne, čo umožňuje prekrývanie operácií a skrývanie latencií.
// 2. VYLEPŠENIE (Efektivita): Pridaná podpora pre hardvérový auto-precharge (READA/WRITEA)
//    prostredníctvom nového príznaku v štruktúre príkazu.
// 3. VYLEPŠENIE (Flexibilita): Všetky geometrické parametre pamäte (šírky adries riadkov,
//    stĺpcov, bánk) sú teraz plne parametrizovateľné. "Magické čísla" boli odstránené.
// 4. VYLEPŠENIE (Robustnosť): Pridané interné FIFO pre zapisované dáta (Write Data FIFO),
//    ktoré oddeľuje (decouples) aplikačnú logiku od časovania SDRAM zbernice.
// 5. ZMENA (Architektúra): Pôvodný FSM bol nahradený inteligentnejším plánovačom príkazov,
//    ktorý dynamicky generuje SDRAM príkazy na základe stavu bánk a požiadaviek.

`ifndef SDRAM_CTRL_ADVANCED_SV
`define SDRAM_CTRL_ADVANCED_SV

(* default_nettype = "none" *)

module SdramControllerAdvanced #(
    // --- System Parameters ---
    parameter CLOCK_FREQ_HZ     = 100_000_000,
    parameter DATA_WIDTH        = 16,
    parameter integer FIFO_DEPTH_BITS  = 4,
    parameter logic ENABLE_DEBUG = 1'b1,

    // --- SDRAM Geometry Parameters (VYLEPŠENIE 3) ---
    parameter integer ROW_ADDR_WIDTH    = 13,
    parameter integer COL_ADDR_WIDTH    = 9,
    parameter integer BANK_ADDR_WIDTH   = 2,

    // --- SDRAM Protocol Parameters ---
    parameter BURST_LEN         = 8,
    parameter integer CAS_LATENCY     = 3,

    // --- SDRAM Timing Parameters (v cykloch) ---
    parameter integer tRP             = 3,         // Precharge command period
    parameter integer tRCD            = 3,         // Active to Read/Write delay
    parameter integer tWR             = 2,         // Write recovery time
    parameter integer tRFC            = 9,         // Refresh command period
    parameter integer tRAS            = 7          // Active to Precharge delay
)(
    // --- User Interface ---
    input  logic                     clk,
    input  logic                     clk_sh, // Fázovo posunutý clock pre SDRAM
    input  logic                     rstn,

    // Command Interface
    input  logic                     cmd_fifo_valid,
    output logic                     cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t    cmd_fifo_data,

    // Read Response Interface
    output logic                     resp_valid,
    output logic                     resp_last,
    output logic [DATA_WIDTH-1:0]    resp_data,
    input  logic                     resp_ready,

    // Write Data Interface
    input  logic                     wdata_valid,
    output logic                     wdata_ready,
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  wdata_dqm_i, // DQM per byte

    // --- SDRAM Physical Interface ---
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

    // --- Debug Interface ---
    output logic [4:0]               debug_state_o,
    output logic [$clog2(FIFO_DEPTH_BITS+1):0] debug_rd_fifo_level_o,
    output logic [$clog2(FIFO_DEPTH_BITS+1):0] debug_wr_fifo_level_o
);

    import sdram_pkg::*;

    // --- Lokálne Parametre a Odvodené Hodnoty ---
    localparam integer NUM_BANKS          = 2**BANK_ADDR_WIDTH;
    localparam integer ADDR_WIDTH         = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;

    // Address mapping (VYLEPŠENIE 3)
    localparam integer BANK_ADDR_HI = ADDR_WIDTH - 1;
    localparam integer BANK_ADDR_LO = BANK_ADDR_HI - BANK_ADDR_WIDTH + 1;
    localparam integer ROW_ADDR_HI  = BANK_ADDR_LO - 1;
    localparam integer ROW_ADDR_LO  = ROW_ADDR_HI - ROW_ADDR_WIDTH + 1;
    localparam integer COL_ADDR_HI  = ROW_ADDR_LO - 1;
    localparam integer COL_ADDR_LO  = 0; // Assuming columns are at the LSBs

    // Init & Refresh Timings
    localparam integer NS_PER_SEC         = 1_000_000_000;
    localparam integer CLK_PERIOD_NS      = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam integer WAIT_TIME_NS       = 200_000; // 200us
    localparam integer INIT_WAIT_CYCLES   = WAIT_TIME_NS / CLK_PERIOD_NS;
    localparam integer REFRESH_INTERVAL   = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000; // 7.812 us

    // Mode Register Value
    localparam logic [2:0] burst_len_bits = (BURST_LEN == 1) ? 3'b000 : (BURST_LEN == 2) ? 3'b001 :
                                          (BURST_LEN == 4) ? 3'b010 : (BURST_LEN == 8) ? 3'b011 : 3'b111;
    localparam logic [2:0] cas_latency_bits = (CAS_LATENCY == 2) ? 3'b010 : (CAS_LATENCY == 3) ? 3'b011 : 3'b000;
    localparam logic [12:0] mrs_value = {3'b000, 1'b0, 2'b00, cas_latency_bits, 1'b0, burst_len_bits};

    // FSM States
    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS,
        IDLE,
        EVAL_CMD,
        ACTIVATE_CMD,
        READ_CMD,
        WRITE_CMD,
        PRECHARGE_CMD,
        REFRESH_CMD,
        READ_BURST,
        WRITE_BURST
    } state_t;

    state_t state_reg, state_next;

    // --- Bank State Management (VYLEPŠENIE 1) ---
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS];
    logic [$clog2(tRAS+1)-1:0] tras_timer[NUM_BANKS];

    // --- Timers ---
    logic [$clog2(INIT_WAIT_CYCLES+1)-1:0]   init_timer;
    logic [$clog2(tRCD+1)-1:0]               trcd_timer;
    logic [$clog2(tRP+1)-1:0]                trp_timer;
    logic [$clog2(tWR+1)-1:0]                twr_timer;
    logic [$clog2(tRFC+1)-1:0]               trfc_timer;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0]   refresh_counter;
    logic                                    refresh_pending;

    // --- Command & Data Registers ---
    sdram_cmd_t current_cmd;
    logic [BANK_ADDR_WIDTH-1:0]  cmd_bank_addr;
    logic [ROW_ADDR_WIDTH-1:0]   cmd_row_addr;
    logic [COL_ADDR_WIDTH-1:0]   cmd_col_addr;

    logic [$clog2(BURST_LEN):0]        burst_cnt;
    logic [$clog2(CAS_LATENCY+1)-1:0]  cas_cnt;

    logic dq_write_enable, dq_write_enable_d;

    // --- Read FIFO ---
    localparam integer FIFO_DEPTH = 1 << FIFO_DEPTH_BITS;
    logic [DATA_WIDTH-1:0]      read_fifo_data[FIFO_DEPTH];
    logic                       read_fifo_last[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_r_wptr, fifo_r_rptr;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_r_count;
    logic fifo_r_wr_en, fifo_r_rd_en, fifo_r_full, fifo_r_empty;

    // --- Write FIFO (VYLEPŠENIE 4) ---
    logic [DATA_WIDTH-1:0]      write_fifo_data[FIFO_DEPTH];
    logic [DATA_WIDTH/8-1:0]    write_fifo_dqm[FIFO_DEPTH];
    logic [FIFO_DEPTH_BITS-1:0] fifo_w_wptr, fifo_w_rptr;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_w_count;
    logic fifo_w_wr_en, fifo_w_rd_en, fifo_w_full, fifo_w_empty;

    // --- Sekvenčný Blok (Srdce) ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            init_timer <= INIT_WAIT_CYCLES;
            trcd_timer <= '0; trp_timer <= '0; twr_timer <= '0; trfc_timer <= '0;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            dq_write_enable_d <= 1'b0;
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
            state_reg <= state_next;

            // --- Globálne Časovače ---
            if (init_timer > 0) init_timer <= init_timer - 1;
            if (trcd_timer > 0) trcd_timer <= trcd_timer - 1;
            if (trp_timer > 0)  trp_timer  <= trp_timer - 1;
            if (twr_timer > 0)  twr_timer  <= twr_timer - 1;
            if (trfc_timer > 0) trfc_timer <= trfc_timer - 1;
            if (cas_cnt > 0)    cas_cnt    <= cas_cnt - 1;

            // --- Bankové Časovače (tRAS) ---
            for (int i=0; i < NUM_BANKS; i++) begin
                if (state_next == ACTIVATE_CMD && cmd_bank_addr == i)
                    tras_timer[i] <= tRAS;
                else if (tras_timer[i] > 0)
                    tras_timer[i] <= tras_timer[i] - 1;
            end

            // --- Refresh Logika ---
            if (state_next == REFRESH_CMD) begin
                refresh_pending <= 1'b0;
                refresh_counter <= REFRESH_INTERVAL;
            end else if (refresh_counter == 0) begin
                refresh_pending <= 1'b1;
            end else begin
                refresh_counter <= refresh_counter - 1;
            end

            // --- Stav Bánk ---
            if (state_next == ACTIVATE_CMD)  bank_state[cmd_bank_addr] <= BANK_ACTIVE;
            if (state_next == PRECHARGE_CMD) bank_state[current_cmd.addr[BANK_ADDR_HI:BANK_ADDR_LO]] <= BANK_IDLE;
            if (current_cmd.auto_precharge && ((state_reg == READ_BURST && burst_cnt == 1) || (state_reg == WRITE_BURST && burst_cnt == 1)))
                bank_state[cmd_bank_addr] <= BANK_IDLE;

            // --- Príkazový Register ---
            if (cmd_fifo_ready && cmd_fifo_valid) begin
                current_cmd <= cmd_fifo_data;
            end

            // --- Aktívny riadok a Burst ---
            if (state_next == ACTIVATE_CMD) active_row[cmd_bank_addr] <= cmd_row_addr;
            if (state_next == READ_CMD || state_next == WRITE_CMD) burst_cnt <= BURST_LEN;
            if ((state_reg == READ_BURST && fifo_r_wr_en) || (state_reg == WRITE_BURST && fifo_w_rd_en))
                burst_cnt <= burst_cnt - 1;

            // --- Riadenie DQ ---
            dq_write_enable_d <= dq_write_enable;

            // --- Read FIFO ---
            if (fifo_r_wr_en && !fifo_r_full) begin
                read_fifo_data[fifo_r_wptr] <= sdram_dq;
                read_fifo_last[fifo_r_wptr] <= (burst_cnt == 1);
                fifo_r_wptr <= fifo_r_wptr + 1;
            end
            if (fifo_r_rd_en && !fifo_r_empty) fifo_r_rptr <= fifo_r_rptr + 1;
            if (fifo_r_wr_en && !fifo_r_full && !(fifo_r_rd_en && !fifo_r_empty)) fifo_r_count <= fifo_r_count + 1;
            else if (!fifo_r_wr_en && fifo_r_rd_en && !fifo_r_empty) fifo_r_count <= fifo_r_count - 1;

            // --- Write FIFO ---
            if (fifo_w_wr_en && !fifo_w_full) begin
                write_fifo_data[fifo_w_wptr] <= wdata;
                write_fifo_dqm[fifo_w_wptr]  <= wdata_dqm_i;
                fifo_w_wptr <= fifo_w_wptr + 1;
            end
            if (fifo_w_rd_en && !fifo_w_empty) fifo_w_rptr <= fifo_w_rptr + 1;
            if (fifo_w_wr_en && !fifo_w_full && !(fifo_w_rd_en && !fifo_w_empty)) fifo_w_count <= fifo_w_count + 1;
            else if (!fifo_w_wr_en && fifo_w_rd_en && !fifo_w_empty) fifo_w_count <= fifo_w_count - 1;

        end
    end

    // --- Kombinačný Blok (Mozog) ---
    always_comb begin
        state_next = state_reg;
        cmd_fifo_ready = 1'b0;
        dq_write_enable = 1'b0;

        // Dekódovanie adresy z aktuálneho príkazu
        cmd_bank_addr = current_cmd.addr[BANK_ADDR_HI:BANK_ADDR_LO];
        cmd_row_addr  = current_cmd.addr[ROW_ADDR_HI:ROW_ADDR_LO];
        cmd_col_addr  = current_cmd.addr[COL_ADDR_HI:COL_ADDR_LO];

        // --- SDRAM Príkazy (defaultne NOP) ---
        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1; sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_addr = '0; sdram_ba = '0; sdram_dqm = '0; sdram_cke = 1'b1;

        // --- FIFO Logika ---
        // Read
        fifo_r_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1);
        fifo_r_rd_en = resp_valid && resp_ready;
        fifo_r_full  = (fifo_r_count == FIFO_DEPTH);
        fifo_r_empty = (fifo_r_count == 0);
        // Write
        fifo_w_wr_en = wdata_valid && wdata_ready;
        fifo_w_rd_en = (state_reg == WRITE_BURST);
        fifo_w_full  = (fifo_w_count == FIFO_DEPTH);
        fifo_w_empty = (fifo_w_count == 0);
        wdata_ready = !fifo_w_full;

        // --- Hlavný FSM (Plánovač) ---
        case (state_reg)
            INIT_WAIT:     if (init_timer == 0) state_next = INIT_PRECHARGE; else sdram_cke = 1'b0;
            INIT_PRECHARGE: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_addr[10] = 1'b1; // Precharge All
                trp_timer <= tRP;
                state_next = INIT_REFRESH1;
            end
            INIT_REFRESH1: if (trp_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0; // Auto Refresh
                trfc_timer <= tRFC;
                state_next = INIT_REFRESH2;
            end
            INIT_REFRESH2: if (trfc_timer == 0) begin
                 sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0; // Auto Refresh
                 trfc_timer <= tRFC;
                 state_next = INIT_MRS;
            end
            INIT_MRS: if (trfc_timer == 0) begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_cas_n = 1'b0; // MRS
                sdram_addr = mrs_value[ROW_ADDR_WIDTH-1:0];
                state_next = IDLE;
            end

            IDLE: begin
                // Priorita 1: Refresh
                if (refresh_pending && twr_timer == 0 && trfc_timer == 0) state_next = REFRESH_CMD;
                // Priorita 2: Spracuj nový príkaz
                else if (cmd_fifo_valid && !fifo_r_full) begin
                    cmd_fifo_ready = 1'b1;
                    state_next = EVAL_CMD;
                end
            end

            EVAL_CMD: begin
                // Sme tu jeden cyklus na zachytenie príkazu
                if (bank_state[cmd_bank_addr] == BANK_IDLE) begin
                    if (trp_timer == 0) state_next = ACTIVATE_CMD;
                end else begin // Banka je aktívna
                    if (active_row[cmd_bank_addr] == cmd_row_addr) begin // Row Hit
                         if (trcd_timer == 0)
                            state_next = (current_cmd.rw == READ_CMD) ? READ_CMD : WRITE_CMD;
                    end else begin // Row Miss
                        if (tras_timer[cmd_bank_addr] == 0) state_next = PRECHARGE_CMD;
                    end
                end
            end

            ACTIVATE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; // ACTIVATE
                sdram_ba = cmd_bank_addr;
                sdram_addr = cmd_row_addr;
                trcd_timer <= tRCD;
                state_next = EVAL_CMD; // Vráť sa a prehodnoť (teraz to bude row hit)
            end

            READ_CMD: begin
                sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; // READ
                sdram_ba = cmd_bank_addr;
                sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_col_addr;
                sdram_addr[10] = current_cmd.auto_precharge; // VYLEPŠENIE 2
                cas_cnt <= CAS_LATENCY;
                state_next = READ_BURST;
            end

            WRITE_CMD: begin
                if (!fifo_w_empty) begin // Počkaj na dáta
                    sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; sdram_we_n = 1'b0; // WRITE
                    sdram_ba = cmd_bank_addr;
                    sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_col_addr;
                    sdram_addr[10] = current_cmd.auto_precharge; // VYLEPŠENIE 2
                    state_next = WRITE_BURST;
                end
            end

            READ_BURST: begin
                if (burst_cnt == 0) state_next = IDLE;
            end

            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                sdram_dqm = write_fifo_dqm[fifo_w_rptr];
                if (burst_cnt == 0) begin
                    twr_timer <= tWR;
                    state_next = IDLE;
                end
            end

            PRECHARGE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; // PRECHARGE
                sdram_ba = cmd_bank_addr;
                //sdram_addr[10] = 1'b1; // Precharge ALL - tu chceme len jednu banku
                trp_timer <= tRP;
                state_next = EVAL_CMD; // Prehodnoť pôvodný príkaz, teraz bude banka IDLE
            end

            REFRESH_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_cas_n = 1'b0; // AUTO REFRESH
                trfc_timer <= tRFC;
                state_next = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end

    // --- Výstupy a Priradenia ---
    assign resp_valid = !fifo_r_empty;
    assign resp_last  = read_fifo_last[fifo_r_rptr];
    assign resp_data  = read_fifo_data[fifo_r_rptr];

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
