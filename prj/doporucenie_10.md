Perfektne ✅, spravíme ASCII diagram časovej osi pre **jednu pixel line**, vrátane `wr_cmd_valid`, `wdata_valid`, `wr_cmd_ready`, `wdata_ready` a FIFO úrovní. Pre jednoduchosť predpokladáme 8 pixelov v jednej linke.

```
Čas → t0   t1   t2   t3   t4   t5   t6   t7
------------------------------------------------
wr_cmd_valid  ┤─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐
wr_cmd_ready  ◄┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►
wdata_valid   ┤─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐
wdata_ready   ◄┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►

wr_fifo_lvl   0    1    2    3    2    1    0    0
rd_fifo_lvl   0    0    0    1    2    1    0    0

SDRAM CMD:
Time → t0   t1   t2   t3   t4   t5   t6   t7
ACT          ┤ACT─────┤
WR           ──┤WR─────┤
NOP          ────┤NOP───┤
PRE          ──────┤PRE──┤
```

### Vysvetlenie priebehu:

1. **wr_cmd_valid** a **wdata_valid** pulzuje vždy, keď framebuffer chce poslať pixel dáta.
2. **wr_cmd_ready** a **wdata_ready** sleduje stav FIFO – ak nie je plná, povolí zápis.
3. **wr_fifo_lvl** stúpa pri zápise a klesá pri odoslaní dát do SDRAM.
4. **SDRAM CMD**: aktivácia banky (`ACT`), zápis dát (`WR`), čakanie (`NOP`), predčasné uzavretie banky (`PRE`).
5. Pipeline spôsobuje, že **FIFO level ≠ okamžitý zápis do SDRAM** – je tam latency 2–3 taktov medzi valid a fyzickým zápisom.

---

Ak chceš, môžem spraviť ešte **detailnejší diagram**, kde sa uvidí **pixel po pixeli**, ktorý pixel je práve vo FIFO, ktorý sa zapisuje do SDRAM a ktoré pulzy sú presne oneskorené kvôli timingom.
Chceš, aby som to urobil?
