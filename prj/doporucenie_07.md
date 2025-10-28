Perfektne 👍 — tu je **prehľadná ASCII schéma** celej integrácie framebufferu, checkeru a SDRAM kontroléra.
Schéma znázorňuje dátový aj príkazový tok, FIFO väzby a signály pre diagnostiku.

---

```
 ┌──────────────────────────────────────────────────────────────┐
 │                        framebuffer_top                       │
 │──────────────────────────────────────────────────────────────│
 │                                                              │
 │   ┌──────────────────────────┐                               │
 │   │     framebuffer_ctrl     │                               │
 │   │──────────────────────────│                               │
 │   │  - generuje SDRAM príkazy (wr/rd)                        │
 │   │  - obsluhuje AXI/stream vstup a výstup                   │
 │   │                                                          │
 │   │  pixel_in/pixel_out  ───────────────────────▶ video I/F   │
 │   │                                                          │
 │   │  wr_cmd_data ─┐                                          │
 │   │  rd_cmd_data ─┴──┐                                       │
 │   │  wdata, rdata     │                                       │
 │   └───────────────────┘                                       │
 │           │                                                   │
 │           │ SDRAM command path                                │
 │           ▼                                                   │
 │   ┌──────────────────────────┐                                │
 │   │     SdramCmdChecker      │                                │
 │   │──────────────────────────│                                │
 │   │  - sleduje stav bánk, riadkov                            │
 │   │  - kontroluje sekvenciu príkazov                         │
 │   │  - deteguje konflikty (ROW_CONFLICT, SEQ_ERROR, ...)     │
 │   │                                                          │
 │   │  wr_cmd_in / rd_cmd_in   ◄─────── z framebuffer_ctrl     │
 │   │  wr_cmd_out / rd_cmd_out ───────▶ do SdramController      │
 │   │                                                          │
 │   │  cmd_error ──────────────▶ LED / debug / status reg       │
 │   │  error_code──────────────▶ CPU / log / monitor            │
 │   └──────────────────────────┘                                │
 │           │                                                   │
 │           │ validované príkazy                               │
 │           ▼                                                   │
 │   ┌──────────────────────────┐                                │
 │   │     SdramController      │                                │
 │   │──────────────────────────│                                │
 │   │  - vykonáva reálne SDRAM časovanie                        │
 │   │  - spravuje FIFO s dátami                                 │
 │   │  - generuje fyzické signály pre SDRAM                     │
 │   │                                                          │
 │   │  sdram_addr, sdram_ba, dq, cs_n, ras_n, cas_n, we_n ...  │
 │   └──────────────────────────┘                                │
 │                                                              │
 └──────────────────────────────────────────────────────────────┘
```

---

### 🔄 Tok signálov

| Typ toku               | Smer                         | Popis                                                         |
| ---------------------- | ---------------------------- | ------------------------------------------------------------- |
| **Video / AXI stream** | `pixel_in/out`               | Dátový tok z/do kamery, VGA, atď.                             |
| **SDRAM príkazy**      | `wr_cmd_data`, `rd_cmd_data` | Ide cez `SdramCmdChecker`, ktorý validuje adresy a sekvenciu. |
| **SDRAM dáta**         | `wdata`, `rdata`             | Ide priamo medzi framebufferom a SDRAM kontrolérom cez FIFO.  |
| **Diagnostika**        | `cmd_error`, `error_code`    | Indikácia chýb pre debug a stavové registre.                  |

---

### 🧠 Kľúčové myšlienky

* **Checker** = „bezpečnostný ventil“ → ak `framebuffer_ctrl` pošle chybný príkaz, neprenikne ďalej.
* **SDRAM controller** dostáva len *overené príkazy* → FSM je chránené pred nekonzistentnými stavmi.
* **Modulárna štruktúra** → všetko je zreteľne oddelené, Quartus vie optimalizovať a časovať bloky nezávisle.

---

Chceš, aby som ti k tejto schéme doplnil aj ASCII zobrazenie **signálových väzieb FIFO** (ako plynú `wdata`, `rdata`, `level` medzi modulmi)?
Môžem to pridať ako pokračovanie tejto vizualizácie.
