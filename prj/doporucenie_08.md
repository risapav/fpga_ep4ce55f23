Super 💪 — tu je rozšírená **ASCII schéma** s **FIFO väzbami** medzi `framebuffer_ctrl`, `SdramCmdChecker` a `SdramController`, vrátane všetkých dôležitých tokov: **príkazy**, **dáta**, **úrovne FIFO** a **riadiace signály** (`ready/valid`).

---

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           framebuffer_top                                   │
│─────────────────────────────────────────────────────────────────────────────│
│                                                                             │
│  AXI/stream in/out                                                          │
│  ┌───────────────┐                                                          │
│  │ framebuffer_  │                                                          │
│  │     ctrl      │                                                          │
│  │───────────────│                                                          │
│  │  pixel_in/out │                                                          │
│  │               │                                                          │
│  │  wr_cmd_data ─┐                                                         │
│  │  wr_cmd_valid ├────────────┐                                             │
│  │  wr_cmd_ready ◄──────────┐ │                                             │
│  │  rd_cmd_data ─┐          │ │                                             │
│  │  rd_cmd_valid ├────────┐ │ │                                             │
│  │  rd_cmd_ready ◄──────┐ │ │ │                                             │
│  │                      │ │ │ │                                             │
│  │  wdata ─────────┐    │ │ │ │                                             │
│  │  wdata_valid ───┴──┐ │ │ │ │                                             │
│  │  wdata_ready ◄─────┘ │ │ │ │                                             │
│  │                      │ │ │ │                                             │
│  │  rdata ◄─────────────┘ │ │ │                                             │
│  │  rdata_valid ◄─────────┘ │ │                                             │
│  │  rdata_ready ────────────┘ │                                             │
│  │                            │                                             │
│  └───────────────┬────────────┘                                             │
│                  │                                                          │
│                  ▼                                                          │
│       ┌──────────────────────────┐                                          │
│       │    SdramCmdChecker       │                                          │
│       │──────────────────────────│                                          │
│       │ - kontrola sekvencie CMD │                                          │
│       │ - kontrola prechodov bank│                                          │
│       │ - validácia adries       │                                          │
│       │ - generovanie chýb       │                                          │
│       │                          │                                          │
│       │ wr_cmd_in/rd_cmd_in ◄─── z framebuffer_ctrl                         │
│       │ wr_cmd_out/rd_cmd_out ───▶ do SdramController                       │
│       │ cmd_error / error_code ──▶ debug/status                             │
│       └───────────────┬──────────┘                                          │
│                       │                                                     │
│                       ▼                                                     │
│        ┌──────────────────────────┐                                         │
│        │     SdramController      │                                         │
│        │──────────────────────────│                                         │
│        │  - FSM pre SDRAM         │                                         │
│        │  - Refresh, timing, CAS  │                                         │
│        │  - FIFO pre dáta         │                                         │
│        │                          │                                         │
│        │   ┌──────────────┐        ┌──────────────┐                         │
│        │   │ Write FIFO   │◄───────┤ wdata stream │                         │
│        │   │──────────────│        └──────────────┘                         │
│        │   │ wdata_level  │──▶ framebuffer_ctrl                              │
│        │   │ wr_full/empty│                                               │
│        │   └──────────────┘                                               │
│        │   ┌──────────────┐        ┌──────────────┐                         │
│        │   │ Read FIFO    │───────▶│ rdata stream │                         │
│        │   │──────────────│        └──────────────┘                         │
│        │   │ rdata_level  │──▶ framebuffer_ctrl                              │
│        │   │ rd_full/empty│                                               │
│        │   └──────────────┘                                               │
│        │                                                                  │
│        │ SDRAM fyz. signály:                                              │
│        │ sdram_addr, sdram_ba, dq, cs_n, ras_n, cas_n, we_n, dqm, clk...  │
│        └──────────────────────────┘                                         │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 🔁 FIFO väzby – signály

| FIFO typ       | Z `framebuffer_ctrl`                  | Do `SdramController`                                              | Riadenie              |
| -------------- | ------------------------------------- | ----------------------------------------------------------------- | --------------------- |
| **Write FIFO** | `wdata`, `wdata_valid`, `wdata_ready` | `wr_fifo_wr_en`, `wr_fifo_rd_en`, `wr_fifo_full`, `wr_fifo_empty` | Úroveň: `wdata_level` |
| **Read FIFO**  | `rdata`, `rdata_valid`, `rdata_ready` | `rd_fifo_wr_en`, `rd_fifo_rd_en`, `rd_fifo_full`, `rd_fifo_empty` | Úroveň: `rdata_level` |

---

### ⚙️ Diagnostika a robustnosť

| Signál                             | Zdroj             | Popis                                                                             |
| ---------------------------------- | ----------------- | --------------------------------------------------------------------------------- |
| `cmd_error`                        | `SdramCmdChecker` | indikuje porušenie sekvencie (napr. aktívna banka bez precharge)                  |
| `error_code[7:0]`                  | `SdramCmdChecker` | kód chyby (napr. 01h – Row conflict, 02h – Refresh miss, 04h – Invalid timing, …) |
| `fifo_overflow` / `fifo_underflow` | `SdramController` | indikátory pre debugging FIFO problémov                                           |

---

### 🧩 Zhrnutie

* **FIFO** oddeľuje časovanie SDRAM od logiky aplikácie → eliminuje „timing bottlenecks“ v Quartuse.
* **CmdChecker** sa vkladá medzi moduly len v debug alebo verifikačnom režime (parameter `CEnableChecker`).
* **Controller** ostáva nezmenený — len dostáva filtrované príkazy.

---

Chceš, aby som ti k tomu doplnil aj **ASCII sekvenciu prenosu (časový priebeh)** napr. pre typický zápis „frame line“ do SDRAM (t. j. ako sa aktivuje banka, píšu dáta, generuje `tlast` atď.)?
To by pekne ukázalo, ako sa `tuser` / `tlast` prenášajú cez tento reťazec.
