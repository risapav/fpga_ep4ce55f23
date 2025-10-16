// sdram_controller_final.sv - Verzia 8.1 - Integrovaná produkčná verzia
//
// Zmeny (v8.1) - Integrácia s externým balíčkom:
// 1. INTEGRÁCIA BALÍČKA: Modul teraz importuje a používa dátový typ `sdram_cmd_t`
//    z `sdram_pkg.sv`, čím sa zabezpečuje systémová konzistencia.
// 2. ZAPUZDRENIE TYPOV: Definícia `sdram_addr_t` je presunutá mimo modul pre lepšiu
//    modularitu a potenciálnu znovupoužiteľnosť.
//
// Zmeny (v8.0) - Refaktoring pre robustnosť a čitateľnosť:
// 1. ADRESOVÁ ŠTRUKTÚRA: Zaviedla sa `sdram_addr_t` pre typovo bezpečný a
//    čitateľnejší prístup k častiam adresy (bank, row, col).
// 2. POMENOVANÉ KONŠTANTY: "Magické číslo" pre adresový bit A10 (Auto-Precharge)
//    bolo nahradené konštantou `AP_BIT_INDEX`.
// 3. PRIORITNÝ REFRESH: Implementovaný mechanizmus "urgentného" refreshu,
//    ktorý zabraňuje "vyhladovaniu" (starvation) refresh cyklov pri vysokej záťaži.
// 4. VALIDÁCIA PARAMETROV: Pridané asercie (`initial` blok), ktoré overujú
//    konzistentnosť zadaných parametrov pri elaborácii.

`ifndef SDRAM_CTRL_FINAL_SV
`define SDRAM_CTRL_FINAL_SV

(* default_nettype = "none" *)


module SdramControllerFinal #(
    // --- Parametre ---
    parameter CLOCK_FREQ_HZ     = 100_000_000,
    parameter DATA_WIDTH        = 16,
    parameter integer FIFO_DEPTH_BITS  = 4,
    parameter logic ENABLE_DEBUG = 1'b1,
    // Tieto parametre definujú rozloženie systémovej adresy.
    // Ich súčet musí zodpovedať šírke adresy v sdram_pkg::sdram_cmd_t (24).
    parameter integer ROW_ADDR_WIDTH    = 13,
    parameter integer COL_ADDR_WIDTH    = 9,
    parameter integer BANK_ADDR_WIDTH   = 2,
    // Parametre časovania SDRAM
    parameter BURST_LEN         = 8,
    parameter integer CAS_LATENCY     = 3,
    parameter integer tRP             = 3,
    parameter integer tRCD            = 3,
    parameter integer tWR             = 2,
    parameter integer tRFC            = 9,
    parameter integer tRAS            = 7
)(
    // --- Rozhrania ---
    input  logic                     clk,
    input  logic                     clk_sh,
    input  logic                     rstn,
    // Rozhranie pre príkazy
    input  logic                     cmd_fifo_valid,
    output logic                     cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t    cmd_fifo_data, // REFAKTORING (v8.1)
    // Rozhranie pre čítané dáta (odpoveď)
    output logic                     resp_valid,
    output logic                     resp_last,
    output logic [DATA_WIDTH-1:0]    resp_data,
    input  logic                     resp_ready,
    // Rozhranie pre zapisované dáta
    input  logic                     wdata_valid,
    output logic                     wdata_ready,
    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  wdata_dqm_i,
    // Fyzické rozhranie SDRAM
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
    // Ladiace výstupy
    output logic [4:0]               debug_state_o,
    output logic [$clog2(FIFO_DEPTH_BITS+1):0] debug_rd_fifo_level_o,
    output logic [$clog2(FIFO_DEPTH_BITS+1):0] debug_wr_fifo_level_o
);

    // REFAKTORING (v8.1): Import definícií z externého balíčka
    import sdram_pkg::*;

    // --- Lokálne Parametre ---
    localparam integer NUM_BANKS          = 2**BANK_ADDR_WIDTH;
    localparam integer SYSTEM_ADDR_WIDTH  = ROW_ADDR_WIDTH + COL_ADDR_WIDTH + BANK_ADDR_WIDTH;
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
    localparam integer AP_BIT_INDEX = 10;
    localparam integer URGENT_REFRESH_MULTIPLIER = 2;
    localparam integer URGENT_REFRESH_CYCLES = REFRESH_INTERVAL * URGENT_REFRESH_MULTIPLIER;
    // Predpoklad pre porovnanie - konvencia, že READ je 1, WRITE je 0
    localparam logic READ_OP = 1'b1;

    // --- Validácia Parametrov (Assertions) ---
    initial begin
        // Overenie konzistencie adresy s balíčkom
        assert (SYSTEM_ADDR_WIDTH == sdram_pkg::ADDR_WIDTH)
            else $fatal(1, "SdramController: Total address width (%0d) does not match sdram_pkg::ADDR_WIDTH (%0d).", SYSTEM_ADDR_WIDTH, sdram_pkg::ADDR_WIDTH);
        // Overenie časovania
        if (tRAS < tRCD) $fatal(1, "SdramController: tRAS (%0d) must be >= tRCD (%0d).", tRAS, tRCD);
        if (tRP < 2) $warning("SdramController: tRP (%0d) is very short. Ensure it meets datasheet spec.", tRP);
        // Overenie konfigurácie
        if (CAS_LATENCY != 2 && CAS_LATENCY != 3) $fatal(1, "SdramController: Unsupported CAS_LATENCY (%0d). Must be 2 or 3.", CAS_LATENCY);
        if (BURST_LEN != 1 && BURST_LEN != 2 && BURST_LEN != 4 && BURST_LEN != 8) $fatal(1, "SdramController: Unsupported BURST_LEN (%0d).", BURST_LEN);
        if (CLK_PERIOD_NS == 0) $fatal(1, "SdramController: CLOCK_FREQ_HZ is too high, resulting in 0 ns period.");
    end

    // --- FSM States ---
    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH1, INIT_REFRESH2, INIT_MRS,
        IDLE, EVAL_CMD, ACTIVATE_CMD, READ_CMD, WRITE_CMD,
        PRECHARGE_CMD, REFRESH_CMD, READ_BURST, WRITE_BURST
    } state_t;

    // --- Signály a Registre ---
    state_t state_reg, state_next;
    typedef enum logic { BANK_IDLE, BANK_ACTIVE } bank_state_t;
    bank_state_t bank_state[NUM_BANKS], bank_state_next[NUM_BANKS];
    logic [ROW_ADDR_WIDTH-1:0] active_row[NUM_BANKS], active_row_next[NUM_BANKS];
    logic [$clog2(tRAS+1)-1:0]               tras_timer[NUM_BANKS], tras_timer_next[NUM_BANKS];
    logic [$clog2(INIT_WAIT_CYCLES+1)-1:0]   init_timer, init_timer_next;
    logic [$clog2(tRCD+1)-1:0]               trcd_timer, trcd_timer_next;
    logic [$clog2(tRP+1)-1:0]                trp_timer, trp_timer_next;
    logic [$clog2(tWR+1)-1:0]                twr_timer, twr_timer_next;
    logic [$clog2(tRFC+1)-1:0]               trfc_timer, trfc_timer_next;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0]   refresh_counter, refresh_counter_next;
    logic                                    refresh_pending, refresh_pending_next;
    logic [$clog2(URGENT_REFRESH_CYCLES+1)-1:0] urgent_refresh_counter, urgent_refresh_counter_next;
    logic urgent_refresh_req, urgent_refresh_req_next;
    logic [$clog2(BURST_LEN):0]              burst_cnt, burst_cnt_next;
    logic [$clog2(CAS_LATENCY+1)-1:0]        cas_cnt, cas_cnt_next;
    sdram_cmd_t                 current_cmd, current_cmd_next; // REFAKTORING (v8.1)
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
    always_ff @(posedge clk) begin
        if (!rstn) begin
            state_reg <= INIT_WAIT;
            init_timer <= INIT_WAIT_CYCLES;
            trcd_timer <= '0; trp_timer <= '0; twr_timer <= '0; trfc_timer <= '0;
            refresh_counter <= REFRESH_INTERVAL;
            refresh_pending <= 1'b0;
            urgent_refresh_counter <= URGENT_REFRESH_CYCLES;
            urgent_refresh_req <= 1'b0;
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
            urgent_refresh_counter <= urgent_refresh_counter_next;
            urgent_refresh_req <= urgent_refresh_req_next;
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
    end

    // --- Kombinačný Blok (Mozog) ---
    always_comb begin
        // --- Defaultné priradenia ---
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

        // --- Dekódovanie adresy ---
        sdram_addr_t cmd_addr;
        cmd_addr = sdram_addr_t'(current_cmd.addr);

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
            if (urgent_refresh_counter > 0) urgent_refresh_counter_next = urgent_refresh_counter - 1;
            else urgent_refresh_req_next = 1'b1;
        end

        // --- FIFO logika ---
        fifo_r_full  = (fifo_r_count == FIFO_DEPTH);
        fifo_r_empty = (fifo_r_count == 0);
        fifo_r_wr_en = (state_reg == READ_BURST) && (cas_cnt == 1);
        fifo_r_rd_en = !fifo_r_empty && resp_ready;
        logic do_read_fifo_write = fifo_r_wr_en && !fifo_r_full;
        logic do_read_fifo_read  = fifo_r_rd_en;
        if (do_read_fifo_write) begin
            read_fifo_data[fifo_r_wptr] = sdram_dq;
            read_fifo_last[fifo_r_wptr] = (burst_cnt == 1);
            fifo_r_wptr_next = fifo_r_wptr + 1;
        end
        if (do_read_fifo_read) fifo_r_rptr_next = fifo_r_rptr + 1;
        fifo_r_count_next = fifo_r_count + do_read_fifo_write - do_read_fifo_read;

        fifo_w_full  = (fifo_w_count == FIFO_DEPTH);
        fifo_w_empty = (fifo_w_count == 0);
        fifo_w_wr_en = wdata_valid && !fifo_w_full;
        fifo_w_rd_en = (state_reg == WRITE_BURST) && !fifo_w_empty;
        logic do_write_fifo_write = fifo_w_wr_en;
        logic do_write_fifo_read  = fifo_w_rd_en;
        if (do_write_fifo_write) begin
            write_fifo_data[fifo_w_wptr] = wdata;
            write_fifo_dqm[fifo_w_wptr]  = wdata_dqm_i;
            fifo_w_wptr_next = fifo_w_wptr + 1;
        end
        if (do_write_fifo_read) fifo_w_rptr_next = fifo_w_rptr + 1;
        fifo_w_count_next = fifo_w_count + do_write_fifo_write - do_write_fifo_read;

        // --- Hlavný FSM ---
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
                sdram_addr = mrs_value[ROW_ADDR_WIDTH-1:0]; state_next = IDLE;
            end
            IDLE: begin
                if ((refresh_pending || urgent_refresh_req) && twr_timer == 0 && trfc_timer == 0) begin
                    state_next = REFRESH_CMD;
                end else if (cmd_fifo_valid && !fifo_r_full) begin
                    cmd_fifo_ready = 1'b1;
                    current_cmd_next = cmd_fifo_data;
                    state_next = EVAL_CMD;
                end
            end
            EVAL_CMD: begin
                if (bank_state[cmd_addr.bank] == BANK_IDLE) begin
                    if (trp_timer == 0) state_next = ACTIVATE_CMD; else state_next = IDLE;
                end else begin // BANK_ACTIVE
                    if (active_row[cmd_addr.bank] == cmd_addr.row) begin
                         if (trcd_timer == 0) state_next = (current_cmd.rw == READ_OP) ? READ_CMD : WRITE_CMD; else state_next = IDLE;
                    end else begin // Nesprávny riadok je aktívny
                        if (tras_timer[cmd_addr.bank] == 0) state_next = PRECHARGE_CMD; else state_next = IDLE;
                    end
                end
            end
            ACTIVATE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_ba = cmd_addr.bank; sdram_addr = cmd_addr.row;
                trcd_timer_next = tRCD;
                tras_timer_next[cmd_addr.bank] = tRAS;
                bank_state_next[cmd_addr.bank] = BANK_ACTIVE;
                active_row_next[cmd_addr.bank] = cmd_addr.row;
                state_next = IDLE;
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
                if (!fifo_w_empty) begin
                    sdram_cs_n = 1'b0; sdram_cas_n = 1'b0; sdram_we_n = 1'b0; sdram_ba = cmd_addr.bank;
                    sdram_addr[COL_ADDR_WIDTH-1:0] = cmd_addr.col;
                    sdram_addr[AP_BIT_INDEX] = current_cmd.auto_precharge;
                    burst_cnt_next = BURST_LEN;
                    if (current_cmd.auto_precharge) bank_state_next[cmd_addr.bank] = BANK_IDLE;
                    state_next = WRITE_BURST;
                end else state_next = IDLE;
            end
            READ_BURST: begin
                if(do_read_fifo_write) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && do_read_fifo_write) state_next = IDLE;
            end
            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                sdram_dqm = write_fifo_dqm[fifo_w_rptr];
                if(do_write_fifo_read) burst_cnt_next = burst_cnt - 1;
                if (burst_cnt == 1 && do_write_fifo_read) begin
                    twr_timer_next = tWR;
                    state_next = IDLE;
                end
            end
            PRECHARGE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0; sdram_ba = cmd_addr.bank;
                trp_timer_next = tRP;
                bank_state_next[cmd_addr.bank] = BANK_IDLE;
                state_next = IDLE;
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
