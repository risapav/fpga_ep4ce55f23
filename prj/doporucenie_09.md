Perfektne ✅, spravíme **ASCII časovú sekvenciu zápisu jednej linky frame** cez `framebuffer_ctrl → SdramCmdChecker → SdramController → SDRAM`. Bude to zjednodušené, ale zachytí všetky hlavné signály: príkazy, dáta, valid/ready a úrovne FIFO.

---

```
Časová os (jedna pixel line) → t0 ... tN

framebuffer_ctrl                    SdramCmdChecker                   SdramController              SDRAM
-----------------                    -----------------                   -----------------            -----
 wr_cmd_data ──┐
 wr_cmd_valid ─┼─►   wr_cmd_in ──────►  wr_cmd_out ───────► wr_cmd_fifo_wr_en ──► CMD FIFO
 wr_cmd_ready ◄┘                         wr_cmd_ready ◄─────┘
 
 wdata ──────────────► wdata_in ──────► wdata_fifo_wr_en ──► Write FIFO ──► SDRAM DQ
 wdata_valid ────────► wdata_valid ───► fifo_wr_en (ready) 
 wdata_ready ◄────────► fifo_full/empty ◄───────────────┘
 
 rdata ◄───────────── rdata_out ◄───── fifo_rd_en ◄───── Read FIFO ◄──── SDRAM DQ
 rdata_valid ◄──────── rdata_valid_out
 rdata_ready ─────────► fifo_not_empty

FIFO úrovne (symbolické):
Time → t0   t1   t2   t3   t4   t5   t6   t7
wr_fifo_lvl   0    1    2    3    2    1    0
rd_fifo_lvl   0    0    0    1    2    1    0

CMD tok (príkazy SDRAM, symbolicky):
ACT  ─►
WR   ─►
NOP  ─►
PRE  ─►
```

---

### 🔹 Vysvetlenie priebehu

1. **framebuffer_ctrl** generuje **write command + data** pre pixel line.
2. **SdramCmdChecker** overí príkaz: je banka voľná? timing OK?
3. **SdramController** vloží dáta do **write FIFO** a vydá príkazy na SDRAM (`ACT`, `WR`, `PRE`, `NOP`).
4. FIFO signalizuje **ready/valid** späť do `framebuffer_ctrl` → plynulé posielanie dát.
5. Po naplnení FIFO sa **údaje postupne zapisujú do SDRAM** po príkazoch.
6. **Rdata** (ak čítame) sa podobne presúva z read FIFO späť cez checker do framebuffer_ctrl.

---

Ak chceš, môžem spraviť **ASCII diagram s časovou osou pixel po pixeli** vrátane **tuser/tlast** a presného momentu, kedy sa `wr_cmd_valid` a `wdata_valid` pulzuje.
To je super na pochopenie latency a pipeline delay medzi modulmi. Chceš, aby som to spravil?
