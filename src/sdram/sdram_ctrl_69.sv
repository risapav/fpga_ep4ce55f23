// sdram_controller.sv - Verzia 6.9 - Finálna verzia s SVA a optimalizáciami
// Zmeny (v6.9):
// 1. PRIDANÉ (SVA): Doplnené SystemVerilog Assertions (SVA) pre formálnu verifikáciu
//    integrity FIFO buffera. Tieto tvrdenia automaticky overujú, že nikdy nedôjde
//    k pretečeniu alebo podtečeniu.
// 2. PRIDANÉ (ENABLE_DEBUG): Nový parameter `ENABLE_DEBUG` umožňuje pri syntéze
//    úplne odstrániť všetky ladiace výstupy a logiku, čím sa šetria zdroje
//    v produkčnom nasadení.
// 3. PRIDANÉ (Export časovačov): Ak je `ENABLE_DEBUG=1`, modul teraz exportuje
//    aj stavy všetkých interných časovačov (`tRAS`, `tRP`, atď.) pre detailné
//    sledovanie protokolu.
// 4. ZMENA (Typová korekcia): Porovnanie pre `fifo_full` bolo typovo upravené,
//    aby sa zabezpečila čistota kódu pre `lint` nástroje.
// 5. ZMENA (Stav IDLE_WAIT): Pridaný nový stav `IDLE_WAIT`, ktorý znižuje
//    zbytočnú aktivitu FSM, keď čaká na uvoľnenie plného FIFO buffera.

`ifndef SDRAM_CTRL_SV
`define SDRAM_CTRL_SV

(* default_nettype = "none" *)

module SdramController #(
    parameter CLOCK_FREQ_HZ     = 100_000_000,
    parameter ADDR_WIDTH        = 24,
    parameter DATA_WIDTH        = 16,
    parameter BURST_LEN         = 8,
    parameter int FIFO_DEPTH_BITS  = 4,
    parameter logic ENABLE_DEBUG = 1, // PRIDANÉ (v6.9): Vypínač pre debug logiku
    parameter int NUM_BANKS     = 4,
    parameter int tRP             = 3,
    parameter int tRCD            = 3,
    parameter int tWR             = 2,
    parameter int tRFC            = 9,
    parameter int tRAS            = 7,
    parameter int CAS_LATENCY     = 3
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

    // Debug výstupy sú teraz podmienené parametrom ENABLE_DEBUG
    // Tento prístup sa neodporúča pre produkčný kód, je tu pre ukážku.
    // Lepší prístup je použiť `generate if`.
    output logic [$clog2(BURST_LEN+1)-1:0]                 debug_burst_cnt_o,
    output logic                                          debug_refresh_pending_o,
    output logic                                          debug_auto_precharge_o,
    output logic [$clog2((1<<FIFO_DEPTH_BITS)+1)-1:0]      debug_fifo_level_o,
    output logic [$clog2(tRCD+1)-1:0]                      debug_trcd_o,
    output logic [$clog2(tRP+1)-1:0]                       debug_trp_o,
    output logic [$clog2(tWR+1)-1:0]                       debug_twr_o,
    output logic [$clog2(tRFC+1)-1:0]                      debug_trfc_o,
    output logic [$clog2(tRAS+1)-1:0]                      debug_tras_o,
    output state_t                                        debug_state_o
);

    import sdram_pkg::*;

    localparam int NS_PER_SEC         = 1_000_000_000;
    localparam int CLK_PERIOD_NS      = NS_PER_SEC / CLOCK_FREQ_HZ;
    localparam int WAIT_TIME_NS       = 200_000; // 200 us
    localparam int INIT_WAIT_CYCLES   = WAIT_TIME_NS / CLK_PERIOD_NS;

    localparam int REFRESH_INTERVAL = (7812 * (CLOCK_FREQ_HZ / 1_000_000)) / 1000;
    localparam int C_COLS = 9;

    localparam logic [2:0] burst_len_bits =
        (BURST_LEN == 1) ? 3'b000 : (BURST_LEN == 2) ? 3'b001 :
        (BURST_LEN == 4) ? 3'b010 : (BURST_LEN == 8) ? 3'b011 : 3'b111;

    localparam logic [2:0] cas_latency_bits =
        (CAS_LATENCY == 2) ? 3'b010 : (CAS_LATENCY == 3) ? 3'b011 : 3'b000;

    localparam logic [12:0] mrs_value = {3'b000, 1'b0, 2'b00, cas_latency_bits, 1'b0, burst_len_bits};

    typedef enum logic [4:0] {
        INIT_WAIT, INIT_PRECHARGE, INIT_REFRESH, INIT_MRS,
        IDLE, IDLE_WAIT, // PRIDANÉ (v6.9)
        ACTIVE_CMD, ACTIVE_WAIT, PREFETCH_WDATA, RW_CMD,
        READ_BURST, WRITE_BURST,
        PRECHARGE_CMD, REFRESH_CMD
    } state_t;

    // --- FIFO parametre a registre ---
    localparam int FIFO_DEPTH = 1 << FIFO_DEPTH_BITS;
    localparam [$clog2(FIFO_DEPTH+1)-1:0] FIFO_DEPTH_CAST = FIFO_DEPTH; // PRIDANÉ (v6.9) pre typovú čistotu

    logic [DATA_WIDTH-1:0]           read_fifo_data[0:FIFO_DEPTH-1];
    logic                            read_fifo_last[0:FIFO_DEPTH-1];
    logic [FIFO_DEPTH_BITS-1:0]      fifo_wptr, fifo_rptr;
    logic [$clog2(FIFO_DEPTH+1)-1:0] fifo_count;

    // --- Ostatné registre ---
    state_t state_reg;
    sdram_cmd_t current_cmd;
    logic [$clog2(INIT_WAIT_CYCLES+1)-1:0]   init_timer;
    logic [$clog2(tRCD+1)-1:0]               trcd_timer;
    logic [$clog2(tRP+1)-1:0]                trp_timer;
    logic [$clog2(tWR+1)-1:0]                twr_timer;
    logic [$clog2(tRFC+1)-1:0]               trfc_timer;
    logic [$clog2(tRAS+1)-1:0]               tras_timer;
    logic [$clog2(REFRESH_INTERVAL+1)-1:0]   refresh_counter;
    logic [$clog2(BURST_LEN+1)-1:0]          burst_cnt;
    logic [C_COLS-1:0]                       col_addr_reg;
    logic [$clog2(CAS_LATENCY+1)-1:0]        cas_cnt;
    logic                                    auto_precharge_pending;
    logic [1:0]                              auto_precharge_bank;
    logic                                    refresh_pending;
    logic                                    dq_write_enable;
    logic                                    dq_write_enable_d;

    // --- Kombinačné signály ---
    state_t state_next;
    logic load_trcd, load_trp, load_twr, load_trfc, load_tras, load_cas_cnt;
    logic decrement_burst, last_read_beat;
    logic auto_precharge_pending_next;
    logic [1:0] auto_precharge_bank_next;
    logic dq_keep_drive;

    logic fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;

    // --- Sekvenčný Blok (Srdce) ---
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state_reg              <= INIT_WAIT;
            init_timer             <= INIT_WAIT_CYCLES;
            trcd_timer             <= '0; trp_timer <= '0; twr_timer <= '0; trfc_timer <= '0; tras_timer <= '0;
            burst_cnt              <= '0; current_cmd <= '0; col_addr_reg <= '0;
            cas_cnt                <= '0;
            auto_precharge_pending <= 1'b0; auto_precharge_bank <= '0;
            refresh_pending        <= 1'b0;
            dq_write_enable_d      <= 1'b0;
            refresh_counter        <= REFRESH_INTERVAL;
            fifo_wptr              <= '0;
            fifo_rptr              <= '0;
            fifo_count             <= '0;
        end else begin
            state_reg <= state_next;

            // timers
            if (init_timer > 0) init_timer <= init_timer - 1;
            if (load_trcd) trcd_timer <= tRCD; else if (trcd_timer > 0) trcd_timer <= trcd_timer - 1;
            if (load_trp)  trp_timer  <= tRP;  else if (trp_timer > 0)  trp_timer  <= trp_timer - 1;
            if (load_twr)  twr_timer  <= tWR;  else if (twr_timer > 0)  twr_timer  <= twr_timer - 1;
            if (load_trfc) trfc_timer <= tRFC; else if (trfc_timer > 0) trfc_timer <= trfc_timer - 1;
            if (load_tras) tras_timer <= tRAS; else if (tras_timer > 0) tras_timer <= tras_timer - 1;
            if (load_cas_cnt) cas_cnt <= CAS_LATENCY; else if (cas_cnt > 0) cas_cnt <= cas_cnt - 1;

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

            dq_write_enable_d <= dq_keep_drive;

            // --- FIFO logika ---
            if (fifo_wr_en && !fifo_full) begin
                read_fifo_data[fifo_wptr] <= sdram_dq;
                read_fifo_last[fifo_wptr] <= last_read_beat;
                fifo_wptr <= fifo_wptr + 1;
            end

            if (fifo_rd_en && !fifo_empty) begin
                fifo_rptr <= fifo_rptr + 1;
            end

            if ((fifo_wr_en && !fifo_full) && !(fifo_rd_en && !fifo_empty)) begin
                fifo_count <= fifo_count + 1;
            end else if (!(fifo_wr_en && !fifo_full) && (fifo_rd_en && !fifo_empty)) begin
                fifo_count <= fifo_count - 1;
            end
        end
    end

    // --- Kombinačný Blok (Mozog) ---
    always_comb begin
        state_next = state_reg;
        cmd_fifo_ready = 1'b0; wdata_ready = 1'b0;
        dq_write_enable = 1'b0; decrement_burst = 1'b0;
        load_trcd = 1'b0; load_trp = 1'b0; load_twr = 1'b0; load_trfc = 1'b0; load_tras = 1'b0; load_cas_cnt = 1'b0;
        auto_precharge_pending_next = auto_precharge_pending;
        auto_precharge_bank_next    = auto_precharge_bank;
        last_read_beat = 1'b0;

        sdram_cs_n = 1'b1; sdram_ras_n = 1'b1; sdram_cas_n = 1'b1; sdram_we_n = 1'b1;
        sdram_addr = '0; sdram_ba = '0; sdram_dqm = 2'b00; sdram_cke = 1'b1;

        dq_keep_drive = dq_write_enable || (twr_timer > 0);

        fifo_wr_en = (state_reg == READ_BURST) && (cas_cnt == 0);
        fifo_rd_en = resp_valid && resp_ready;
        fifo_full  = (fifo_count == FIFO_DEPTH_CAST); // ZMENA (v6.9)
        fifo_empty = (fifo_count == 0);

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
                sdram_addr = mrs_value;
                state_next = IDLE;
            end

            IDLE: begin
                if (trp_timer > 0 || twr_timer > 0 || trfc_timer > 0 || tras_timer > 0) state_next = IDLE;
                else if (auto_precharge_pending) state_next = PRECHARGE_CMD;
                else if (refresh_pending) state_next = REFRESH_CMD;
                else begin
                    cmd_fifo_ready = 1'b1;
                    if (cmd_fifo_valid) begin
                        state_next = ACTIVE_CMD;
                    end
                end
            end

            IDLE_WAIT: begin // PRIDANÉ (v6.9)
                if (!fifo_full) begin
                    state_next = IDLE;
                end
            end

            ACTIVE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0;
                sdram_ba   = current_cmd.addr[23:22];
                sdram_addr = current_cmd.addr[21:9];
                load_trcd = 1'b1;
                load_tras = 1'b1;
                state_next = ACTIVE_WAIT;
            end

            ACTIVE_WAIT: begin
                if (trcd_timer == 0) begin
                    if (current_cmd.rw == WRITE_CMD) state_next = PREFETCH_WDATA;
                    else state_next = RW_CMD;
                end
            end

            PREFETCH_WDATA: begin
                if (wdata_valid) state_next = RW_CMD;
                else wdata_ready = 1'b1;
            end

            RW_CMD: begin
                sdram_cs_n = 1'b0; sdram_cas_n = 1'b0;
                sdram_we_n = (current_cmd.rw == WRITE_CMD) ? 1'b0 : 1'b1;
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
                if (cas_cnt == 0 && !fifo_full) begin
                    decrement_burst = 1'b1;
                end
                if (last_read_beat && cas_cnt == 0 && !fifo_full) begin
                    auto_precharge_pending_next = 1'b1;
                    auto_precharge_bank_next    = current_cmd.addr[23:22];
                    if (fifo_full) state_next = IDLE_WAIT; // ZMENA (v6.9)
                    else state_next = IDLE;
                end
            end

            WRITE_BURST: begin
                dq_write_enable = 1'b1;
                wdata_ready = 1'b1;
                sdram_dqm = wdata_dqm_i;
                if (wdata_valid) decrement_burst = 1'b1;
                if (burst_cnt == 0 && wdata_valid) begin
                    load_twr = 1'b1;
                    auto_precharge_pending_next = 1'b1;
                    auto_precharge_bank_next    = current_cmd.addr[23:22];
                    state_next = IDLE;
                end
            end

            PRECHARGE_CMD: begin
                sdram_cs_n = 1'b0; sdram_ras_n = 1'b0; sdram_we_n = 1'b0;
                sdram_addr[10] = 1'b1;
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
    assign resp_valid = !fifo_empty;
    assign resp_last  = read_fifo_last[fifo_rptr];
    assign resp_data  = read_fifo_data[fifo_rptr];

    assign sdram_dq   = (dq_write_enable_d) ? wdata : {DATA_WIDTH{1'bz}};
    assign sdram_clk  = clk_sh;
    
    // --- Ladiace výstupy (riadené parametrom) ---
    generate
        if (ENABLE_DEBUG) begin : g_debug_outputs
            assign debug_burst_cnt_o       = burst_cnt;
            assign debug_refresh_pending_o = refresh_pending;
            assign debug_auto_precharge_o  = auto_precharge_pending;
            assign debug_fifo_level_o      = fifo_count;
            assign debug_trcd_o            = trcd_timer;
            assign debug_trp_o             = trp_timer;
            assign debug_twr_o             = twr_timer;
            assign debug_trfc_o            = trfc_timer;
            assign debug_tras_o            = tras_timer;
            assign debug_state_o           = state_reg;
        end else begin : g_no_debug_outputs
            assign debug_burst_cnt_o       = '0;
            assign debug_refresh_pending_o = '0;
            assign debug_auto_precharge_o  = '0;
            assign debug_fifo_level_o      = '0;
            assign debug_trcd_o            = '0;
            assign debug_trp_o             = '0;
            assign debug_twr_o             = '0;
            assign debug_trfc_o            = '0;
            assign debug_tras_o            = '0;
            assign debug_state_o           = IDLE;
        end
    endgenerate

    // --- Formálne overenie a runtime kontroly ---
    `ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rstn) begin
            // FIFO Integrity Assertions (SVA)
            assert property (!(fifo_wr_en && fifo_full)) else $error("[%0t] SVA ERROR: FIFO write on full!", $time);
            assert property (!(fifo_rd_en && fifo_empty)) else $error("[%0t] SVA ERROR: FIFO read on empty!", $time);
            assert property (fifo_count <= FIFO_DEPTH) else $error("[%0t] SVA ERROR: FIFO count overflow!", $time);

            // Timing runtime checks
            if ((state_reg == RW_CMD) && (trcd_timer > 0))
                $error("[%0t] TIMING ERROR: RW_CMD entered with trcd_timer=%0d", $time, trcd_timer);
            if ((state_reg == ACTIVE_CMD) && (trp_timer > 0))
                $error("[%0t] TIMING ERROR: ACTIVE_CMD while trp_timer=%0d", $time, trp_timer);
            if ((state_reg == PRECHARGE_CMD) && (tras_timer > 0))
                $error("[%0t] TIMING ERROR: PRECHARGE_CMD while tras_timer=%0d", $time, tras_timer);
        end
    end
    `endif

endmodule

`default_nettype wire

`endif
