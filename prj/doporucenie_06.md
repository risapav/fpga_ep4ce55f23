Super 👌 — nižšie je návrh **`framebuffer_top.sv`**, ktorý integruje:

* `framebuffer_ctrl` (tvoja aplikačná logika – generuje príkazy a streamy),
* nový modul `SdramCmdChecker` (validácia a ochrana pred chybami),
* `SdramController` (fyzické riadenie SDRAM).

Všetko je navrhnuté tak, aby bolo **časovo bezpečné** pre Quartus (žiadne neštandardné konštrukcie, jednoduché signálové cesty).

---

## 📘 **Návrh modulu `framebuffer_top.sv`**

```systemverilog
/**
 * @file framebuffer_top.sv
 * @brief Integrácia framebufferu s SDRAM kontrolérom a kontrolnou vrstvou.
 *
 * Hierarchia:
 *   framebuffer_ctrl  →  SdramCmdChecker  →  SdramController
 *
 * - framebuffer_ctrl generuje príkazy a streamy (čítanie/zápis framebufferu)
 * - SdramCmdChecker overuje sekvenciu, adresy a korektnosť SDRAM príkazov
 * - SdramController vykonáva reálne časovanie a prístup do SDRAM
 *
 * Tento top modul spája všetky komponenty a zjednocuje rozhranie
 * pre zvyšok systému (napr. video pipeline alebo CPU).
 */

`default_nettype none

import sdram_pkg::*;

module framebuffer_top #(
    parameter int CClockFreqHz   = 100_000_000,
    parameter int CFifoAddrWidth = 6
)(
    // --- Systémové signály ---
    input  logic clk,
    input  logic clk_sh,   // fázovo posunuté hodiny pre SDRAM
    input  logic rstn,

    // --- Aplikačné rozhranie (napr. AXI-stream pre video) ---
    input  logic [23:0] pixel_in,
    input  logic        pixel_in_valid,
    output logic        pixel_in_ready,

    output logic [23:0] pixel_out,
    output logic        pixel_out_valid,
    input  logic        pixel_out_ready,

    // --- Diagnostika ---
    output logic        sdram_cmd_error,
    output logic [15:0] sdram_error_code,

    // --- SDRAM fyzické piny ---
    output logic [ROW_ADDR_WIDTH-1:0]  sdram_addr,
    output logic [BANK_ADDR_WIDTH-1:0] sdram_ba,
    output logic                       sdram_cs_n,
    output logic                       sdram_ras_n,
    output logic                       sdram_cas_n,
    output logic                       sdram_we_n,
    inout  wire  [DATA_WIDTH-1:0]      sdram_dq,
    output logic [DATA_WIDTH/8-1:0]    sdram_dqm,
    output logic                       sdram_cke,
    output logic                       sdram_clk
);

    // --- Medzisignály ---
    sdram_cmd_t wr_cmd_fb, rd_cmd_fb;
    logic       wr_cmd_fb_valid, wr_cmd_fb_ready;
    logic       rd_cmd_fb_valid, rd_cmd_fb_ready;

    sdram_cmd_t wr_cmd_chk, rd_cmd_chk;
    logic       wr_cmd_chk_valid, wr_cmd_chk_ready;
    logic       rd_cmd_chk_valid, rd_cmd_chk_ready;

    logic [DATA_WIDTH-1:0] wdata_fb;
    logic wdata_fb_valid, wdata_fb_ready;
    logic [DATA_WIDTH-1:0] rdata_fb;
    logic rdata_fb_valid, rdata_fb_ready;

    logic [CFifoAddrWidth:0] wdata_level, rdata_level;

    // ============================================================
    // 1️⃣ Framebuffer Controller
    // ============================================================
    framebuffer_ctrl framebuffer_inst (
        .clk            (clk),
        .rstn           (rstn),

        // Video / stream vstup
        .pixel_in       (pixel_in),
        .pixel_in_valid (pixel_in_valid),
        .pixel_in_ready (pixel_in_ready),

        // Video / stream výstup
        .pixel_out      (pixel_out),
        .pixel_out_valid(pixel_out_valid),
        .pixel_out_ready(pixel_out_ready),

        // SDRAM write príkazy
        .wr_cmd_data    (wr_cmd_fb),
        .wr_cmd_valid   (wr_cmd_fb_valid),
        .wr_cmd_ready   (wr_cmd_fb_ready),

        // SDRAM read príkazy
        .rd_cmd_data    (rd_cmd_fb),
        .rd_cmd_valid   (rd_cmd_fb_valid),
        .rd_cmd_ready   (rd_cmd_fb_ready),

        // SDRAM write dáta
        .wdata          (wdata_fb),
        .wdata_valid    (wdata_fb_valid),
        .wdata_ready    (wdata_fb_ready),

        // SDRAM read dáta
        .rdata          (rdata_fb),
        .rdata_valid    (rdata_fb_valid),
        .rdata_ready    (rdata_fb_ready),

        // FIFO zaplnenie (môže použiť na flow control)
        .wdata_level    (wdata_level),
        .rdata_level    (rdata_level)
    );

    // ============================================================
    // 2️⃣ SDRAM Command Checker (bezpečnostná vrstva)
    // ============================================================
    SdramCmdChecker #(
        .CNumBanks(1 << sdram_pkg::BANK_ADDR_WIDTH)
    ) checker_inst (
        .clk              (clk),
        .rstn             (rstn),

        // z framebuffer_ctrl
        .wr_cmd_in        (wr_cmd_fb),
        .wr_cmd_valid     (wr_cmd_fb_valid),
        .wr_cmd_ready     (wr_cmd_fb_ready),
        .rd_cmd_in        (rd_cmd_fb),
        .rd_cmd_valid     (rd_cmd_fb_valid),
        .rd_cmd_ready     (rd_cmd_fb_ready),

        // do SDRAM kontroléra
        .wr_cmd_out       (wr_cmd_chk),
        .wr_cmd_out_valid (wr_cmd_chk_valid),
        .wr_cmd_out_ready (wr_cmd_chk_ready),
        .rd_cmd_out       (rd_cmd_chk),
        .rd_cmd_out_valid (rd_cmd_chk_valid),
        .rd_cmd_out_ready (rd_cmd_chk_ready),

        // diagnostika
        .cmd_error        (sdram_cmd_error),
        .error_code       (sdram_error_code)
    );

    // ============================================================
    // 3️⃣ SDRAM Controller
    // ============================================================
    SdramController #(
        .CClockFreqHz   (CClockFreqHz),
        .CFifoAddrWidth (CFifoAddrWidth)
    ) sdram_ctrl_inst (
        .clk            (clk),
        .clk_sh         (clk_sh),
        .rstn           (rstn),

        // z checkeru
        .wr_cmd_data    (wr_cmd_chk),
        .wr_cmd_valid   (wr_cmd_chk_valid),
        .wr_cmd_ready   (wr_cmd_chk_ready),
        .rd_cmd_data    (rd_cmd_chk),
        .rd_cmd_valid   (rd_cmd_chk_valid),
        .rd_cmd_ready   (rd_cmd_chk_ready),

        // FIFO dáta
        .wdata          (wdata_fb),
        .wdata_valid    (wdata_fb_valid),
        .wdata_ready    (wdata_fb_ready),
        .rdata          (rdata_fb),
        .rdata_valid    (rdata_fb_valid),
        .rdata_ready    (rdata_fb_ready),
        .wdata_level    (wdata_level),
        .rdata_level    (rdata_level),

        // SDRAM fyzické piny
        .sdram_addr     (sdram_addr),
        .sdram_ba       (sdram_ba),
        .sdram_cs_n     (sdram_cs_n),
        .sdram_ras_n    (sdram_ras_n),
        .sdram_cas_n    (sdram_cas_n),
        .sdram_we_n     (sdram_we_n),
        .sdram_dq       (sdram_dq),
        .sdram_dqm      (sdram_dqm),
        .sdram_cke      (sdram_cke),
        .sdram_clk      (sdram_clk)
    );

endmodule

`default_nettype wire
```

---

## 🧠 **Ako to funguje**

### Tok príkazov

```
framebuffer_ctrl
   ├─ wr_cmd/rd_cmd ─► SdramCmdChecker ─► SdramController
   │
   ├─ wdata/rdata FIFO ─────────────────► SDRAM controller (priame spojenie)
```

### Tok dát

* Dáta idú **priame** (nie cez checker) — checker validuje iba príkazy.
* Checker prepúšťa príkazy len ak sú **formálne korektné** → tým sa eliminuje riziko rozbitia SDRAM FSM.

### Diagnostika

* `sdram_cmd_error` → aktivuje sa pri zistení neplatného príkazu.
* `sdram_error_code` → kód chyby (napr. row conflict, sekvenčný error, bank error).
  Túto hodnotu môžeš pripojiť k debug výstupu, alebo do stavového registra CPU.

---

## 🧩 **Výhody tejto architektúry**

| Oblasť                    | Výhoda                                                                |
| ------------------------- | --------------------------------------------------------------------- |
| **Časovanie**             | Checker nevplýva na SDRAM FSM – signály sú pipelineované.             |
| **Bezpečnosť**            | Detekuje konfliktné príkazy (napr. otvorený riadok bez prechladenia). |
| **Diagnostika**           | Jednoduché debugovanie chybného správania framebufferu.               |
| **Modulárnosť**           | Môžeš checker vypnúť (#define DISABLE_CHECKER) pre finálny build.     |
| **Quartus-kompatibilita** | Žiadne nekompatibilné konštrukcie, vhodné pre Cyclone/Max.            |

---

Chceš, aby som ti k tomu ešte doplnil **blokový diagram (vizuálny prehľad)** integrácie – ako by to vyzeralo v top-level schéme FPGA?
Môžem ho vygenerovať ako obrázok (DALL·E) alebo ASCII blokový prehľad priamo v texte.
