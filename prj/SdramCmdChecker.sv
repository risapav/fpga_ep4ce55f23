/**
 * @file SdramCmdChecker.sv
 * @brief Overovanie korektnosti SDRAM príkazov pred zápisom/čítaním.
 *
 * Tento modul prijíma príkazy určené pre SDRAM kontrolér,
 * overuje ich adresovú a sekvenčnú konzistenciu a generuje
 * signály "safe" príkazov ďalej do SdramController-u.
 *
 * Ak sa zistí neplatná kombinácia (napr. zápis do iného riadku
 * bez prechádzajúceho prechodu banky do IDLE), nastaví sa 'cmd_error'.
 *
 * Zmeny (v1.2 - Refaktoring podľa expertízy):
 * - Pridaný vstup 'clear_errors_i' pre soft reset chybových stavov.
 * - Implementovaná symetrická logika pre R/W príkazy
 * (R/W do IDLE banky ju nastaví na OPEN).
 * - Odstránený TODO komentár.
 *
 * (Návrh experta pre projekt)
 */

`ifndef SDRAM_CMD_CHECKER_SV
`define SDRAM_CMD_CHECKER_SV

`default_nettype none

import sdram_pkg::*;

module SdramCmdChecker #(
    parameter int CNumBanks = 1 << sdram_pkg::BANK_ADDR_WIDTH
)(
    input  logic clk,
    input  logic rstn,
    // VYLEPŠENIE (Bod 2): Vstup pre soft reset
    input  logic clear_errors_i,

    // --- Vstupné príkazy z aplikačnej vrstvy (napr. framebuffer) ---
    input  sdram_cmd_t wr_cmd_in,
    input  logic       wr_cmd_valid,
    output logic       wr_cmd_ready,

    input  sdram_cmd_t rd_cmd_in,
    input  logic       rd_cmd_valid,
    output logic       rd_cmd_ready,

    // --- Výstupné príkazy do SDRAM kontroléra ---
    output sdram_cmd_t wr_cmd_out,
    output logic       wr_cmd_out_valid,
    input  logic       wr_cmd_out_ready, // Pripravenosť z SdramController

    output sdram_cmd_t rd_cmd_out,
    output logic       rd_cmd_out_valid,
    input  logic       rd_cmd_out_ready, // Pripravenosť z SdramController

    // --- Diagnostika ---
    output logic cmd_error,        // ak zistí chybný príkaz
    output logic [15:0] error_code // voliteľné: typ chyby
);

    typedef enum logic [1:0] {BANK_IDLE, BANK_OPEN, BANK_ERROR} bank_state_t;

    bank_state_t bank_state [CNumBanks];
    logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] active_row [CNumBanks];

    localparam ERR_NONE         = 16'h0000;
    localparam ERR_ROW_CONFLICT = 16'h0001; // Pokus o prístup k inému riadku v otvorenej banke
    localparam ERR_BANK_BUSY    = 16'h0002; // Rezervované
    localparam ERR_SEQ_VIOL     = 16'h0003; // Rezervované

    logic [15:0] error_code_reg;
    logic cmd_error_next;

    // Synchrónny reset
    always_ff @(posedge clk) begin
        // VYLEPŠENIE (Bod 2): Pridaný 'clear_errors_i'
        if (!rstn || clear_errors_i) begin
            for (int i = 0; i < CNumBanks; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
            end
            cmd_error      <= 1'b0;
            error_code_reg <= ERR_NONE;
        end else begin
            // Chyba sa resetuje každým taktom, ak nie je detekovaná znova
            cmd_error      <= cmd_error_next;
            // Kód chyby sa drží, kým nie je chyba vynulovaná
            error_code_reg <= (cmd_error_next && !cmd_error) ? error_code_reg :
                              (!cmd_error_next) ? ERR_NONE : error_code_reg;

            // --- spracovanie write príkazu ---
            if (wr_cmd_valid && wr_cmd_out_ready) begin
                automatic int b = wr_cmd_in.addr.bank;

                if (bank_state[b] == BANK_IDLE) begin
                    bank_state[b] <= BANK_OPEN;
                    active_row[b] <= wr_cmd_in.addr.row;
                end else if (bank_state[b] == BANK_OPEN) begin
                     if (active_row[b] != wr_cmd_in.addr.row) begin
                        cmd_error      <= 1'b1;
                        error_code_reg <= ERR_ROW_CONFLICT;
                        bank_state[b]  <= BANK_ERROR;
                    end
                end
                // Ak je banka v stave ERROR, zostáva tam

                if (wr_cmd_in.auto_precharge)
                    bank_state[b] <= BANK_IDLE;
            end

            // --- spracovanie read príkazu ---
            if (rd_cmd_valid && rd_cmd_out_ready) begin
                automatic int b = rd_cmd_in.addr.bank;

                // VYLEPŠENIE (Bod 1): Implementovaná symetrická logika ako pri zápise
                if (bank_state[b] == BANK_IDLE) begin
                    // Prvý príkaz (READ) do IDLE banky ju otvára
                    bank_state[b] <= BANK_OPEN;
                    active_row[b] <= rd_cmd_in.addr.row;
                end else if (bank_state[b] == BANK_OPEN) begin
                    // Kontrola konfliktu riadkov
                    if (active_row[b] != rd_cmd_in.addr.row) begin
                        cmd_error      <= 1'b1;
                        error_code_reg <= ERR_ROW_CONFLICT;
                        bank_state[b]  <= BANK_ERROR;
                    end
                end

                if (rd_cmd_in.auto_precharge)
                    bank_state[b] <= BANK_IDLE;
            end
        end
    end

    // Kombinačná kontrola chýb (pre okamžité zastavenie)
    always_comb begin
        cmd_error_next = 1'b0;
        // Kontrola, či vstupný príkaz nespôsobí chybu
        if (wr_cmd_valid) begin
            automatic int b = wr_cmd_in.addr.bank;
            if (bank_state[b] == BANK_OPEN && active_row[b] != wr_cmd_in.addr.row)
                cmd_error_next = 1'b1;
            if (bank_state[b] == BANK_ERROR)
                cmd_error_next = 1'b1;
        end
        if (rd_cmd_valid) begin
            automatic int b = rd_cmd_in.addr.bank;
            if (bank_state[b] == BANK_OPEN && active_row[b] != rd_cmd_in.addr.row)
                cmd_error_next = 1'b1;
            if (bank_state[b] == BANK_ERROR)
                cmd_error_next = 1'b1;
        end

        // VYLEPŠENIE (Bod 2): clear_errors_i má okamžitý vplyv
        if (clear_errors_i) begin
            cmd_error_next = 1'b0;
        end
    end


    // --- Forwardovanie signálov ---
    assign wr_cmd_ready      = wr_cmd_out_ready;
    assign rd_cmd_ready      = rd_cmd_out_ready;

    assign wr_cmd_out        = wr_cmd_in;
    assign rd_cmd_out        = rd_cmd_in;

    // Príkaz prepustíme, len ak je platný A ZÁROVEŇ nespôsobí chybu
    assign wr_cmd_out_valid  = wr_cmd_valid && !cmd_error_next;
    assign rd_cmd_out_valid  = rd_cmd_valid && !cmd_error_next;

    assign error_code = error_code_reg;

endmodule

`default_nettype wire
`endif

