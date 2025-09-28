Skvelé! Tu je prehľadný **ASCII diagram pipeline čítania a zápisu SDRAM** pre tvoj radič so všetkými časovačmi a CAS_LATENCY. Zobrazuje, kedy sa aktivuje burst, kedy sa čítajú/zapisujú dáta, a ako sú posúvané cez pipeline.

---

### Symboly použité v diagrame

```
A   = ACTIVE príkaz (otvorenie riadku)
R   = READ príkaz
W   = WRITE príkaz
P   = PRECHARGE príkaz
F   = Auto-Precharge pending
|Dn | = Dáta na pipeline výstupe (resp_data), index = CAS_LATENCY-1
Tn  = Trcd/Trp/Twr/Trfc počítadlo cyklov (zjednodušené)
```

### Čítací burst (CAS_LATENCY = 3, BURST_LEN = 8)

```
Cykly:    0 1 2 3 4 5 6 7 8 9 10 11 12 13 14
------------------------------------------------
FSM:       A A A R R R R R R R R R
Trcd:      T3 T2 T1 0
Read Pipe:          |D0| |D1| |D2| |D3| |D4| |D5| |D6| |D7|
Resp_val:           0   0   0   1   1   1   1   1   1
Resp_last:                          0   0   0   0   0   0   1
```

* `A` = aktivácia riadku (`ACTIVE_CMD`)
* `R` = čítací príkaz (`RW_CMD`)
* Dáta sa objavia po CAS_LATENCY cykloch (`|Dn|` v pipeline).
* `Resp_valid` sa aktivuje pri výstupe pipeline.
* `Resp_last` sa aktivuje pri poslednom beate burstu.

---

### Zápisový burst (CAS_LATENCY = 3, BURST_LEN = 8)

```
Cykly:    0 1 2 3 4 5 6 7 8 9 10 11 12
----------------------------------------
FSM:       A A A W W W W W W W W W
Trcd:      T3 T2 T1 0
DQ_en:             1  1  1  1  1  1  1  1
Wdata_valid:       1  1  1  1  1  1  1  1
Burst_cnt:          7 6 5 4 3 2 1 0
Twr:                                      T2 T1 0
Auto_P:                                   F
```

* `W` = zápisový príkaz (`RW_CMD`)
* `DQ_en` = povolenie zápisu do SDRAM (`dq_write_enable`)
* `Burst_cnt` sa znižuje každý beat
* Po dokončení burstu sa spúšťa `tWR` a potom (ak bolo nastavené) auto-precharge (`F`)

---

### Precharge a Auto-Precharge

```
Cykly:    ...  t t+1 t+2
-------------------------
FSM:       PRECHARGE_CMD
sdram_ba:  <bank z auto_precharge_bank>
Trp:       T3 T2 T1 0
Auto_P:    0
```

* Po dokončení burstu s auto-precharge sa FSM presunie do stavu `PRECHARGE_CMD`.
* `auto_precharge_pending` sa vymaže po dokončení precharge.

---

Tento diagram ti umožňuje **simulovať a debugovať pipeline**, kontrolovať `resp_valid`, `resp_last`, `burst_cnt`, `trcd_timer`, `trp_timer`, `twr_timer` a správnosť auto-precharge.

Ak chceš, môžem urobiť **rozšírenú verziu diagramu**, kde bude vidieť **presný stav všetkých časovačov (`trcd`, `trp`, `twr`, `trfc`) a pipeline v každom cykle** – vhodné pre waveform porovnanie so simuláciou.

Chceš, aby som spravil aj túto podrobnú verziu?
