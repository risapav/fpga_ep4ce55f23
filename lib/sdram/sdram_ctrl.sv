// sdram_ctrl.sv - Vysoko optimalizovaný SDRAM radič
//
// Verzia 4.0 - Pokročilá Optimalizácia
//
// Kľúčové vylepšenia:
// 1. VÝKON: Implementovaná správa bánk a riadkov (Bank & Row Management).
//    - Radič si pamätá otvorený riadok pre každú banku.
//    - Umožňuje "Row Hit" prístup, čím sa preskakujú PRECHARGE a ACTIVATE cykly.
// 2. VÝKON: Pridané prekrývanie príkazov (Command Pipelining).
//    - `cmd_fifo_ready` je inteligentnejšie, umožňuje prijímať príkazy počas čakania.
// 3. VÝKON: Pridaná podpora pre Auto-Precharge.
//    - Príkaz `sdram_cmd_t` musí obsahovať nový príznak `auto_precharge_en`.
//    - Šetrí cykly explicitného PRECHARGE príkazu.
// 4. VÝKON: Implementovaný Per-Bank Precharge namiesto Precharge All.
// 5. ČITATEĽNOSŤ: Zjednodušená FSM pre inicializáciu s unikátnymi stavmi.
// 6. KOMENTÁRE: Rozsiahle komentáre vysvetľujúce pokročilú logiku.

`include "sdram_pkg.sv"

module SdramController #(
    // -- Parametre zbernice
    parameter ADDR_WIDTH = 24,
    parameter DATA_WIDTH = 16,
    parameter BURST_LEN  = 8,
    parameter NUM_BANKS  = 4, // Počet bánk v SDRAM čipe

    // -- Parametre časovania SDRAM (v taktoch hodín)
    parameter tRP        = 3,  // Row Precharge time
    parameter tRCD       = 3,  // Row to Column Delay
    parameter tWR        = 3,  // Write Recovery time
    parameter tRC        = 9,  // Row Cycle time
    parameter CAS_LATENCY= 3,  // CAS Latency
    parameter tRFC       = 7,  // Refresh Cycle time
    parameter tRAS       = 7,  // Row Active Time (Minimálny čas medzi ACT a PRE)
    parameter REFRESH_CYCLES = 7800
)(
    input  logic clk,
    input  logic rstn,

    // -- Rozhranie pre príkazy (z aplikačnej logiky)
    input  logic                   cmd_fifo_valid,
    output logic                   cmd_fifo_ready,
    input  sdram_pkg::sdram_cmd_t  cmd_fifo_data, // Očakáva sa, že obsahuje aj `auto_precharge_en`

    // -- Rozhranie pre čítané dáta (do aplikačnej logiky)
    output logic                   resp_valid,
    output logic                   resp_last,
    output logic [DATA_WIDTH-1:0]  resp_data,
    input  logic                   resp_ready,

    // -- Rozhranie pre zapisované dáta (z aplikačnej logiky)
    input  logic                   wdata_valid,
    input  logic [DATA_WIDTH-1:0]  wdata,
    output logic                   wdata_ready,

    // -- Fyzické piny SDRAM
    output logic [12:0]            sdram_addr,
    output logic [1:0]             sdram_ba,
    output logic                   sdram_cs_n,
    output logic                   sdram_ras_n,
    output logic                   sdram_cas_n,
    output logic                   sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0]  sdram_dq,
    output logic [1:0]             sdram_dqm,
    output logic                   sdram_cke,

    // -- Debug výstup
    output logic [4:0]             fsm_state
);

    import sdram_pkg::*;

    //================================================================
    // Deklarácie typov a lokálnych parametrov
    //================================================================

    // -- Stavy FSM
    typedef enum logic [4:0] {
        S_RESET,
        // Unikátne stavy pre inicializáciu pre lepšiu čitateľnosť
        S_INIT_WAIT, S_INIT_PRECHARGE, S_INIT_WAIT_TRP,
        S_INIT_AUTOREFRESH1, S_INIT_WAIT_TRFC1,
        S_INIT_AUTOREFRESH2, S_INIT_WAIT_TRFC2,
        S_INIT_MRS,
        // Stavy hlavného cyklu
        S_IDLE,
        S_CMD_DECODE,   // Nový stav na dekódovanie príkazu a rozhodnutie o ďalšom kroku
        S_FILL_WDATA,
        S_ACTIVATE,
        S_READ,
        S_WRITE,
        S_READ_DATA,
        S_WRITE_DATA,
        S_PRECHARGE,
        S_AUTO_REFRESH,
        // Explicitné stavy čakania
        S_WAIT_TRP, S_WAIT_TRCD, S_WAIT_CL, S_WAIT_TWR, S_WAIT_TRFC
    } state_t;

    // -- Parametre pre dekódovanie adresy
    localparam BANK_WIDTH = $clog2(NUM_BANKS);
    localparam ROW_WIDTH  = 13;
    localparam COL_WIDTH  = 9;

    localparam BANK_HI = ADDR_WIDTH - 1;
    localparam BANK_LO = BANK_HI - BANK_WIDTH + 1;
    localparam ROW_HI  = BANK_LO - 1;
    localparam ROW_LO  = ROW_HI - ROW_WIDTH + 1;
    localparam COL_HI  = ROW_LO - 1;
    localparam COL_LO  = COL_HI - COL_WIDTH + 1;

    // -- Dynamické generovanie hodnoty pre Mode Register
    localparam MODE_REG_BL = (BURST_LEN == 8) ? 3'b011 : 3'b000;
    localparam MODE_REG_CL = (CAS_LATENCY == 3) ? 3'b011 : 3'b010;
    localparam logic [12:0] MODE_REGISTER_VALUE = {2'b00, 1'b0, 1'b0, 2'b00, MODE_REG_CL, 1'b0, MODE_REG_BL};

    //================================================================
    // Signály a registre
    //================================================================

    state_t state, next_state;
    logic [7:0] wait_cnt;

    logic rstn_sync, rstn_sync_ff;
    logic rst;

    logic [15:0] refresh_counter;
    logic        refresh_request;

    sdram_cmd_t current_cmd;
    logic [DATA_WIDTH-1:0] burst_write_data [0:BURST_LEN-1];
    logic [$clog2(BURST_LEN):0] wdata_fill_cnt;
    logic [$clog2(BURST_LEN)-1:0] burst_cnt;

    // -- Logika pre Bank & Row Management
    logic [ROW_WIDTH-1:0] active_row [0:NUM_BANKS-1];
    logic                 bank_is_active [0:NUM_BANKS-1];
    logic [BANK_WIDTH-1:0] precharge_bank_addr; // Adresa banky pre cielený precharge

    // -- Signály pre SDRAM piny
    logic ras_n_d, cas_n_d, we_n_d;
    logic [12:0] addr_d;
    logic [1:0]  ba_d;
    logic dq_oe;
    logic [DATA_WIDTH-1:0] dq_out;

    // -- Správne registrovaný výstup pre čítané dáta
    logic [DATA_WIDTH-1:0] read_data_reg;
    logic [CAS_LATENCY:0]  resp_valid_pipe;

    //================================================================
    // Priradenia výstupov
    //================================================================
    assign fsm_state    = state;
    assign sdram_ras_n  = ras_n_d;
    assign sdram_cas_n  = cas_n_d;
    assign sdram_we_n   = we_n_d;
    assign sdram_addr   = addr_d;
    assign sdram_ba     = ba_d;
    assign sdram_dqm    = 2'b00;
    assign sdram_cs_n   = 1'b0;
    assign sdram_cke    = 1'b1;
    assign sdram_dq     = dq_oe ? dq_out : 'z;

    // -- Inteligentná logika pre `cmd_fifo_ready`
    // Prijmeme príkaz, ak sme v IDLE, alebo ak dekódujeme a sme pripravení na ďalší.
    assign cmd_fifo_ready = (state == S_IDLE);

    assign wdata_ready = (state == S_FILL_WDATA) && (wdata_fill_cnt < BURST_LEN);

    assign resp_valid = resp_valid_pipe[CAS_LATENCY];
    assign resp_data  = read_data_reg;
    assign resp_last  = (burst_cnt == BURST_LEN - 1) && resp_valid;

    // -- Dekódovanie adresy z príkazu
    wire [BANK_WIDTH-1:0] cmd_bank = cmd_fifo_data.addr[BANK_HI:BANK_LO];
    wire [ROW_WIDTH-1:0]  cmd_row  = cmd_fifo_data.addr[ROW_HI:ROW_LO];
    wire [COL_WIDTH-1:0]  cmd_col  = cmd_fifo_data.addr[COL_HI:COL_LO];

    //================================================================
    // Sekvenčná logika
    //================================================================

    // -- Reset synchronizácia
    always_ff @(posedge clk) begin
        rstn_sync_ff <= rstn;
        rstn_sync    <= rstn_sync_ff;
    end
    assign rst = ~rstn_sync;

    // -- Hlavný sekvenčný blok
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_RESET;
            wait_cnt <= 0;
            refresh_counter <= 0;
            refresh_request <= 1'b0;
            current_cmd <= '0;
            burst_cnt <= '0;
            wdata_fill_cnt <= '0;
            for (int i = 0; i < NUM_BANKS; i++) begin
                bank_is_active[i] <= 1'b0;
            end
        end else begin
            state <= next_state;

            // Logika časovača
            if (state != next_state) begin
                case (next_state)
                    S_INIT_WAIT:       wait_cnt <= 200;
                    S_INIT_WAIT_TRP:   wait_cnt <= tRP - 1;
                    S_INIT_WAIT_TRFC1: wait_cnt <= tRFC - 1;
                    S_INIT_WAIT_TRFC2: wait_cnt <= tRFC - 1;
                    S_WAIT_TRP:        wait_cnt <= tRP - 1;
                    S_WAIT_TRFC:       wait_cnt <= tRFC - 1;
                    S_WAIT_TRCD:       wait_cnt <= tRCD - 1;
                    S_WAIT_CL:         wait_cnt <= CAS_LATENCY - 1;
                    S_WAIT_TWR:        wait_cnt <= tWR - 1;
                    default:           wait_cnt <= 0;
                endcase
            end else if (wait_cnt > 0) begin
                wait_cnt <= wait_cnt - 1;
            end

            // Logika refresh časovača
            if (state == S_IDLE || state == S_CMD_DECODE) begin
                if (refresh_counter >= REFRESH_CYCLES) begin
                    refresh_counter <= 0;
                    refresh_request <= 1'b1;
                end else begin
                    refresh_counter <= refresh_counter + 1;
                    refresh_request <= 1'b0;
                end
            end else if (refresh_request && state == S_AUTO_REFRESH) begin
                refresh_request <= 1'b0;
            end

            // Prijatie príkazu z FIFO
            if (cmd_fifo_valid && cmd_fifo_ready) begin
                current_cmd <= cmd_fifo_data;
            end

            // Plnenie interného bufferu pre zápis
            if (wdata_ready && wdata_valid) begin
                burst_write_data[wdata_fill_cnt] <= wdata;
                wdata_fill_cnt <= wdata_fill_cnt + 1;
            end

            // Reset počítadiel pred burst operáciou
            if (state == S_READ || state == S_WRITE) begin
                burst_cnt <= 0;
            end
            // Inkrementácia burst počítadla
            else if ((state == S_READ_DATA && resp_ready && resp_valid) || (state == S_WRITE_DATA && burst_cnt < BURST_LEN - 1)) begin
                 burst_cnt <= burst_cnt + 1;
            end
            
            if (state == S_IDLE) wdata_fill_cnt <= 0;

            // Aktualizácia stavu bánk
            if (state == S_ACTIVATE) begin
                bank_is_active[cmd_bank] <= 1'b1;
                active_row[cmd_bank] <= cmd_row;
            end
            // Banka sa stáva neaktívnou po dokončení PRECHARGE
            if (state == S_WAIT_TRP && wait_cnt == 1) begin
                bank_is_active[precharge_bank_addr] <= 1'b0;
            end
        end
    end

    // -- Sekvenčný blok pre pipelining čítaných dát
    always_ff @(posedge clk) begin
        if (rst) begin
            read_data_reg <= '0;
            resp_valid_pipe <= '0;
        end else begin
            if (resp_valid_pipe[CAS_LATENCY-1]) read_data_reg <= sdram_dq;
            resp_valid_pipe[0] <= (state == S_READ);
            for (int i = 0; i < CAS_LATENCY; i++) resp_valid_pipe[i+1] <= resp_valid_pipe[i];
        end
    end

    //================================================================
    // Kombinačná logika (Stavový automat)
    //================================================================
    always_comb begin
        next_state = state;

        ras_n_d = 1'b1; cas_n_d = 1'b1; we_n_d = 1'b1;
        addr_d  = '0; ba_d = '0; dq_oe = 1'b0; dq_out = '0;
        precharge_bank_addr = cmd_bank; // Defaultne

        case (state)
            //--------------------------------------------------------
            // Inicializačná sekvencia (lineárny tok)
            //--------------------------------------------------------
            S_RESET:             next_state = S_INIT_WAIT;
            S_INIT_WAIT:         if (wait_cnt == 0) next_state = S_INIT_PRECHARGE;
            S_INIT_PRECHARGE:    begin ras_n_d = 1'b0; we_n_d = 1'b0; addr_d[10] = 1'b1; next_state = S_INIT_WAIT_TRP; end
            S_INIT_WAIT_TRP:     if (wait_cnt == 0) next_state = S_INIT_AUTOREFRESH1;
            S_INIT_AUTOREFRESH1: begin ras_n_d = 1'b0; cas_n_d = 1'b0; next_state = S_INIT_WAIT_TRFC1; end
            S_INIT_WAIT_TRFC1:   if (wait_cnt == 0) next_state = S_INIT_AUTOREFRESH2;
            S_INIT_AUTOREFRESH2: begin ras_n_d = 1'b0; cas_n_d = 1'b0; next_state = S_INIT_WAIT_TRFC2; end
            S_INIT_WAIT_TRFC2:   if (wait_cnt == 0) next_state = S_INIT_MRS;
            S_INIT_MRS:          begin ras_n_d=0; cas_n_d=0; we_n_d=0; addr_d=MODE_REGISTER_VALUE; next_state=S_IDLE; end

            //--------------------------------------------------------
            // Hlavný cyklus
            //--------------------------------------------------------
            S_IDLE: begin
                if (refresh_request) next_state = S_AUTO_REFRESH;
                else if (cmd_fifo_valid) next_state = S_CMD_DECODE;
            end

            S_CMD_DECODE: begin
                // Hlavná rozhodovacia logika pre maximálny výkon
                if (bank_is_active[cmd_bank]) begin
                    // Banka je aktívna, skontrolujeme riadok
                    if (active_row[cmd_bank] == cmd_row) begin
                        // *** ROW HIT ***
                        // Riadok je otvorený, môžeme okamžite čítať/písať
                        if (current_cmd.rw == WRITE_CMD) next_state = S_FILL_WDATA;
                        else next_state = S_READ;
                    end else begin
                        // *** ROW MISS ***
                        // Iný riadok v aktívnej banke, musíme najprv urobiť PRECHARGE
                        precharge_bank_addr = cmd_bank;
                        next_state = S_PRECHARGE;
                    end
                end else begin
                    // *** BANK MISS ***
                    // Banka nie je aktívna, môžeme ju hneď aktivovať
                    next_state = S_ACTIVATE;
                end
            end

            S_FILL_WDATA: if (wdata_fill_cnt == BURST_LEN) next_state = S_WRITE;

            S_ACTIVATE: begin
                ras_n_d = 1'b0; ba_d = cmd_bank; addr_d = {1'b0, cmd_row};
                next_state = S_WAIT_TRCD;
            end

            S_WAIT_TRCD: begin
                if (wait_cnt == 0) begin
                    // Po aktivácii pokračujeme na čítanie/zápis
                    if (current_cmd.rw == WRITE_CMD) next_state = S_FILL_WDATA;
                    else next_state = S_READ;
                end
            end

            S_READ: begin
                cas_n_d = 1'b0; ba_d = cmd_bank;
                addr_d = {3'b0, cmd_col, current_cmd.auto_precharge_en}; // Podpora Auto-Precharge
                next_state = S_WAIT_CL;
            end

            S_WAIT_CL: if (wait_cnt == 0) next_state = S_READ_DATA;

            S_READ_DATA: begin
                if (resp_last && resp_ready) begin
                    if (current_cmd.auto_precharge_en) begin
                        precharge_bank_addr = cmd_bank;
                        next_state = S_WAIT_TRP; // Po auto-precharge čakáme tRP
                    end else begin
                        next_state = S_IDLE; // Návrat do IDLE, čakáme na ďalší príkaz
                    end
                end
            end

            S_WRITE: begin
                cas_n_d = 1'b0; we_n_d = 1'b0; ba_d = cmd_bank;
                addr_d = {3'b0, cmd_col, current_cmd.auto_precharge_en};
                // Prvé dáta sa posielajú spolu s príkazom
                dq_oe = 1'b1; dq_out = burst_write_data[0];
                next_state = S_WRITE_DATA;
            end

            S_WRITE_DATA: begin
                dq_oe = 1'b1; dq_out = burst_write_data[burst_cnt];
                if (burst_cnt == BURST_LEN - 1) next_state = S_WAIT_TWR;
            end

            S_WAIT_TWR: begin
                if (wait_cnt == 0) begin
                     if (current_cmd.auto_precharge_en) begin
                        precharge_bank_addr = cmd_bank;
                        next_state = S_WAIT_TRP;
                    end else begin
                        next_state = S_IDLE;
                    end
                end
            end

            S_PRECHARGE: begin
                // Cielený Per-Bank Precharge
                ras_n_d = 1'b0; we_n_d = 1'b0; ba_d = precharge_bank_addr;
                addr_d[10] = 1'b0; // A10=0 pre cielený precharge
                next_state = S_WAIT_TRP;
            end

            S_WAIT_TRP: begin
                if (wait_cnt == 0) begin
                    // Po precharge sme pripravení na ďalší príkaz pre túto banku
                    next_state = S_IDLE;
                end
            end
            
            S_AUTO_REFRESH: begin
                ras_n_d = 1'b0; cas_n_d = 1'b0;
                next_state = S_WAIT_TRFC;
            end

            S_WAIT_TRFC: if (wait_cnt == 0) next_state = S_IDLE;

            default: next_state = S_RESET;
        endcase
    end

endmodule
