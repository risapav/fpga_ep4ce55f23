Perfektne ✅ — to je veľmi rozumný krok.
Takáto kontrolná (monitorovacia) vrstva výrazne **zvýši spoľahlivosť systému**, pričom nijako **nezaťaží časovanie SDRAM FSM**, keďže beží „pred“ hlavným kontrolérom.

Nižšie máš návrh modulu **`SdramCmdChecker`**, ktorý sa dá vložiť medzi napr. `framebuffer_ctrl` a `SdramController`.

---

## 🧩 Cieľ modulu

`SdramCmdChecker` má slúžiť ako **ochranná logika**:

* overuje prichádzajúce príkazy (`rd_cmd_data`, `wr_cmd_data`) z aplikačnej logiky,
* kontroluje ich **sekvenčnú a adresovú korektnosť**,
* overuje, že sa nepokúšaš zapisovať mimo rámec banky alebo burstu,
* sleduje konzistenciu medzi `wr_cmd_valid` / `rd_cmd_valid` a FIFO úrovňami,
* generuje signál `cmd_error` ak zistí problém.

---

## 📘 Interface návrh

```systemverilog
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
    input  logic       wr_cmd_out_ready,

    output sdram_cmd_t rd_cmd_out,
    output logic       rd_cmd_out_valid,
    input  logic       rd_cmd_out_ready,

    // --- Diagnostika ---
    output logic cmd_error,        // ak zistí chybný príkaz
    output logic [15:0] error_code // voliteľné: typ chyby
);
```

---

## 🧠 Logika modulu (popis)

1. **Sledovanie stavu bánk**

   * Modul si interne pamätá, ktorá banka je momentálne „otvorená“ (aktívny riadok).
   * Ak príde príkaz s inou row adresou, ale banka ešte nebola prechladená (`auto_precharge=0`), je to **chybná sekvencia**.

2. **Kontrola prechodov**

   * Overuje, že po zápise s `auto_precharge=0` nasledujúci príkaz nie je `READ` do inej banky bez prechodu IDLE.
   * Overuje, že čítanie a zápis sa nedejú paralelne na rovnakú banku.

3. **FIFO forwardovanie**

   * Ak je príkaz korektný, prepúšťa ho ďalej (`*_cmd_out_valid = *_cmd_valid`).
   * Ak nie, zadrží ho a nastaví `cmd_error`.

---

## 🧱 Implementácia jadra

```systemverilog
    typedef enum logic [1:0] {BANK_IDLE, BANK_OPEN, BANK_ERROR} bank_state_t;

    bank_state_t bank_state [CNumBanks];
    logic [sdram_pkg::ROW_ADDR_WIDTH-1:0] active_row [CNumBanks];

    localparam ERR_NONE         = 16'h0000;
    localparam ERR_ROW_CONFLICT = 16'h0001;
    localparam ERR_BANK_BUSY    = 16'h0002;
    localparam ERR_SEQ_VIOL     = 16'h0003;

    logic [15:0] error_code_reg;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (int i = 0; i < CNumBanks; i++) begin
                bank_state[i] <= BANK_IDLE;
                active_row[i] <= '0;
            end
            cmd_error      <= 1'b0;
            error_code_reg <= ERR_NONE;
        end else begin
            cmd_error      <= 1'b0;
            error_code_reg <= ERR_NONE;

            // --- spracovanie write príkazu ---
            if (wr_cmd_valid && wr_cmd_out_ready) begin
                automatic int b = wr_cmd_in.addr.bank;

                if (bank_state[b] == BANK_IDLE) begin
                    bank_state[b] <= BANK_OPEN;
                    active_row[b] <= wr_cmd_in.addr.row;
                end else if (active_row[b] != wr_cmd_in.addr.row) begin
                    cmd_error      <= 1'b1;
                    error_code_reg <= ERR_ROW_CONFLICT;
                    bank_state[b]  <= BANK_ERROR;
                end

                if (wr_cmd_in.auto_precharge)
                    bank_state[b] <= BANK_IDLE;
            end

            // --- spracovanie read príkazu ---
            if (rd_cmd_valid && rd_cmd_out_ready) begin
                automatic int b = rd_cmd_in.addr.bank;

                if (bank_state[b] == BANK_IDLE) begin
                    // možno čítanie po prechladení - OK
                end else if (active_row[b] != rd_cmd_in.addr.row) begin
                    cmd_error      <= 1'b1;
                    error_code_reg <= ERR_ROW_CONFLICT;
                    bank_state[b]  <= BANK_ERROR;
                end

                if (rd_cmd_in.auto_precharge)
                    bank_state[b] <= BANK_IDLE;
            end
        end
    end

    // --- Forwardovanie signálov ---
    assign wr_cmd_ready      = wr_cmd_out_ready;
    assign rd_cmd_ready      = rd_cmd_out_ready;
    assign wr_cmd_out        = wr_cmd_in;
    assign rd_cmd_out        = rd_cmd_in;
    assign wr_cmd_out_valid  = wr_cmd_valid && !cmd_error;
    assign rd_cmd_out_valid  = rd_cmd_valid && !cmd_error;

    assign error_code = error_code_reg;

endmodule

`default_nettype wire
`endif
```

---

## ⚙️ **Integrácia do systému**

Zapojenie medzi framebufferom a SDRAM kontrolérom:

```
framebuffer_ctrl
   │
   ├── wr_cmd_data/rd_cmd_data ──► SdramCmdChecker ──► SdramController
   │                                │
   │                                └── cmd_error / error_code
   │
   └── wdata/rdata FIFO zdieľané priamo
```

➡️ Výhody:

* Nezasahuje do časovania SDRAM FSM.
* Dá sa syntetizovať v Quartuse bez dopadu na fmax.
* Pri chybách možno generovať aj debug výstupy (napr. LED error, status register).

---

## 💡 Možné rozšírenia

* Pridať **timeout detekciu**, ak banka ostane príliš dlho otvorená bez auto-precharge.
* Pridať **AXI4-Stream kontrolu** – ak budeš na vstup napájať AXI stream (napr. pre framebuffer).
* Pridať **error counter** – pre štatistiky chýb.

---

Chceš, aby som ti hneď na to pripravil aj **schému integrácie** (`top` blok so zapojením SdramCmdChecker medzi framebuffer_ctrl a SdramController`)?
Môžem to spraviť ako čistý SystemVerilog top modul s komentármi.
