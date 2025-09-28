Perfektne! Tu je **rozšírený diagram SDRAM pipeline a časovačov** pre simuláciu, ktorý zobrazuje presne, ako sa menia všetky časovače, pipeline a signály pri čítacom a zápisovom burste. Predpokladám **CAS_LATENCY = 3**, **BURST_LEN = 8**, a že všetko je pre jednu banku.

---

### Symboly

```
FSM:        Stav FSM (ACTIVE, READ, WRITE, PRECHARGE...)
Trcd/Twr/Trp/TRFC: časovače
Burst:      Počet zostávajúcich beatov
Pipe:       read_pipe_valid a read_pipe_data
Resp:       resp_valid resp_last
DQ_en:      dq_write_enable (pri zápise)
AutoP:      auto_precharge_pending
```

---

### Čítací burst (READ, auto_precharge = 0)

```
Cykly:   0 1 2 3 4 5 6 7 8 9 10 11 12
---------------------------------------
FSM:      ACTIVE_CMD ACTIVE_WAIT RW_CMD READ_BURST READ_BURST READ_BURST READ_BURST READ_BURST READ_BURST READ_BURST READ_BURST
Trcd:     T3 T2 T1 0
Burst:                    7 6 5 4 3 2 1 0
Pipe:                     |D0| |D1| |D2| |D3| |D4| |D5| |D6| |D7|
Resp_val:                  0   0   0   1   1   1   1   1
Resp_last:                                  0   0   0   0   0   0   1
AutoP:                    0
```

* Dáta sa posúvajú pipeline (`read_pipe_valid`), resp. výstup `resp_data` sa objaví po CAS_LATENCY.
* `Resp_last` sa aktivuje na poslednom beate burstu.

---

### Zápisový burst (WRITE, auto_precharge = 1)

```
Cykly:   0 1 2 3 4 5 6 7 8 9 10 11 12 13 14
--------------------------------------------
FSM:      ACTIVE_CMD ACTIVE_WAIT PREFETCH_WDATA RW_CMD WRITE_BURST WRITE_BURST WRITE_BURST WRITE_BURST WRITE_BURST WRITE_BURST WRITE_BURST WRITE_BURST
Trcd:     T3 T2 T1 0
DQ_en:                                1   1   1   1   1   1   1   1
Burst:                               7 6 5 4 3 2 1 0
Wdata_valid:                          1  1  1  1  1  1  1  1
Twr:                                                        T2 T1 0
AutoP:                                                      1
```

* Po dokončení zápisu burstu sa spúšťa `tWR` a potom FSM vykoná precharge, pretože `auto_precharge_pending = 1`.
* `DQ_en` je povolené počas zápisu.

---

### Precharge (Auto-Precharge po WRITE alebo READ)

```
Cykly:      t t+1 t+2 t+3
--------------------------
FSM:       PRECHARGE_CMD
Trp:       T3 T2 T1 0
sdram_ba:  <bank z auto_precharge_bank>
AutoP:     0 po dokončení precharge
```

* Počas precharge sa uvoľní bank (`auto_precharge_pending` sa resetuje).
* Trp časovač sa odpočítava na zablokovanie ďalších prístupov do tejto banky.

---

Tento diagram môžeš použiť priamo **na porovnanie so simuláciou**: waveform pre `resp_valid`, `resp_last`, `burst_cnt`, `trcd_timer`, `trp_timer`, `twr_timer`, `dq_write_enable`, `auto_precharge_pending`.

---

Ak chceš, môžem vytvoriť ešte **ASCII “cyklický timeline” so všetkými časovačmi, pipeline a auto-precharge pre FULL INIT → READ → WRITE → AUTO-PRECHARGE → REFRESH sekvenciu**, kde bude vidieť kompletný chod radiča od resetu po bežnú prevádzku.

Chceš, aby som spravil aj túto kompletnú sekvenciu?
