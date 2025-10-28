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

Super! Urobíme teraz **detailný diagram po pixeloch** pre jednu linku (8 pixelov), kde uvidíš presne, čo je vo FIFO, čo sa zapisuje do SDRAM a oneskorenie medzi `wdata_valid` a zápisom.

```
Čas → t0   t1   t2   t3   t4   t5   t6   t7   t8   t9   t10  t11  t12
----------------------------------------------------------------------------
Pixel       P0   P1   P2   P3   P4   P5   P6   P7
----------------------------------------------------------------------------
wr_cmd_valid ┤─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐
wr_cmd_ready ◄┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►
wdata_valid  ┤─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐ ├─┐
wdata_ready  ◄┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►┘ └►
----------------------------------------------------------------------------
wr_fifo_lvl   0    1    2    3    4    4    3    2    1    0    0    0
----------------------------------------------------------------------------
SDRAM CMD
ACT          ┤ACT────────────┤
WR           ──┤WR─P0─────WR─P1────WR─P2────WR─P3────WR─P4────WR─P5───
NOP          ────┤NOP───┤NOP───┤NOP───┤NOP───┤
PRE          ─────────────┤PRE───┤
----------------------------------------------------------------------------
```

### Vysvetlenie detailov:

1. **Pixel pipeline**:

   * Pixel P0 sa začne posielať t0, ale do SDRAM sa zapíše až o 2–3 taktové oneskorenie.
   * FIFO level stúpa pri valid dátach a klesá pri zápise do SDRAM.
2. **FIFO level**:

   * Maximum sa dosiahne, keď `wdata_valid` je rýchlejšie než SDRAM môže zapisovať (`wr_fifo_lvl`=4).
   * Postupne FIFO vyprázdni, keď SDRAM spracuje dáta.
3. **SDRAM timing**:

   * **ACT** aktivuje banku.
   * **WR** zápis pixelov (pipeline umožňuje zápis viacerých pixelov po sebe).
   * **NOP** sú nutné pre timing medzi príkazmi.
   * **PRE** predčasne uzavrie banku po zápise.

---

Ak chceš, môžem spraviť **ASCII animovaný diagram**, kde sa bude FIFO level meniť **pixel po pixeli**, a bude presne vidieť oneskorenie medzi `wdata_valid` a fyzickým zápisom do SDRAM.

Chceš, aby som takýto animovaný diagram urobil?

Super! Poďme na to krok za krokom, úplne jednoducho:

1. **FIFO (First-In, First-Out)**

   * Je to ako rada ľudí: prvý, kto príde, je prvý, kto ide preč.
   * V tomto prípade FIFO drží dáta, ktoré čakajú na zápis do SDRAM.

2. **`wdata_valid`**

   * Tento signál hovorí: „Hej, FIFO práve dostalo platné dáta!“
   * SDRAM ovládač sleduje tento signál, aby vedel, že môže z FIFO čítať a zapisovať do pamäte.

3. **Zápis do SDRAM**

   * SDRAM nemôže zapisovať kedykoľvek – musí počkať, kým je pripravená.
   * FIFO umožňuje, že dáta čakajú pripravené, takže ovládač môže zapisovať plynulo, bez straty dát.

**Ako to spolupracuje:**

* Dáta prichádzajú → FIFO → `wdata_valid` indikuje, že sú tam dáta → SDRAM ovládač číta z FIFO a zapisuje do SDRAM.
* FIFO zabraňuje tomu, aby dáta „zbehli“ alebo sa stratili, keď SDRAM nie je pripravená.

Ak chceš, môžem nakresliť **jednoduchú ASCII schému**, ktorá to ukáže vizuálne. Chceš, aby som to spravil?


Super! Tu je jednoduchá ASCII schéma, ktorá ukazuje, ako FIFO a `wdata_valid` spolupracujú so SDRAM:

```
Dáta prichádzajú
       │
       ▼
   ┌─────────┐
   │   FIFO  │  ← ukladá dáta, kým SDRAM nie je pripravená
   └─────────┘
       │
       │ wdata_valid = 1, ak FIFO obsahuje platné dáta
       ▼
   ┌────────────┐
   │ SDRAM      │  ← ovládač číta z FIFO a zapisuje do pamäte
   │ Controller │
   └────────────┘
       │
       ▼
   Dáta v SDRAM
```

**Vysvetlenie krokov:**

1. Dáta prichádzajú do FIFO.
2. FIFO drží dáta, kým SDRAM ovládač nie je pripravený.
3. Signál `wdata_valid` indikuje, že FIFO obsahuje dáta na zápis.
4. SDRAM ovládač číta z FIFO a zapisuje do SDRAM.

Ak chceš, môžem spraviť aj **dynamickejšiu verziu ASCII**, ktorá ukáže **časový priebeh signálu `wdata_valid` a zápisu do SDRAM**, aby to bolo úplne jasné. Chceš, aby som takú spravil?


Skvelé! Tu je jednoduchý ASCII časový priebeh FIFO a signálu `wdata_valid` počas zápisu do SDRAM:

```
Čas --->

FIFO:      ┌───────┐       ┌───────┐
           │DATA 1 │       │DATA 2 │
           └───────┘       └───────┘
           
wdata_valid: ──┐     ┌───────┐
                │1    │1      │
                └─────┘       └─
                
SDRAM WR:   ──┐     ┌───────┐
             │WR1  │WR2     │
             └─────┘        └─
```

**Vysvetlenie:**

1. FIFO obsahuje dáta (`DATA 1`, `DATA 2`).
2. `wdata_valid = 1`, keď FIFO má dáta pripravené na zápis.
3. SDRAM WR sa aktivuje len keď je `wdata_valid = 1`.
4. Po zápise sa FIFO uvoľní a signál `wdata_valid` klesne, kým neprídu nové dáta.

Ak chceš, môžem spraviť **detailnejšiu verziu s viacerými cyklami**, kde bude vidno, ako FIFO postupne vypisuje dáta a `wdata_valid` bliká podľa toho, či sú dáta pripravené. Chceš, aby som takú spravil?


Super! Tu je detailnejší ASCII časový diagram zápisu z FIFO do SDRAM cez signál `wdata_valid`. Predstav si, že každý stĺpec je jeden takt (clock cycle).

```
Čas --->      1    2    3    4    5    6    7    8    9   10

FIFO DATA:   DATA1 DATA2 DATA3 DATA4 DATA5  -    -    -    -    -
wdata_valid:   1     1     1     1     1    0    0    0    0    0
SDRAM WR:      WR1   WR2   WR3   WR4   WR5   -    -    -    -    -
```

**Vysvetlenie krok za krokom:**

1. **FIFO DATA** – FIFO drží dáta pripravené na zápis. Každý cyklus posiela jedno dáta, kým sa vyprázdni.
2. **wdata_valid** – je vysoký (`1`) len vtedy, keď FIFO má dáta pripravené na zápis.
3. **SDRAM WR** – aktivuje sa každý cyklus, keď je `wdata_valid = 1`. Po vyprázdnení FIFO je zápis pozastavený (`-`).

Ak chceš, môžem spraviť aj **ASCII diagram, kde je FIFO čiastočne plné a zápis do SDRAM mešká kvôli wait-states**, aby bolo realistickejšie pre SDRAM. Chceš, aby som taký spravil?


Super! Tu je ASCII diagram, kde je FIFO čiastočne plné a zápis do SDRAM môže meškať kvôli wait-states. Predstav si, že SDRAM niekedy potrebuje 1–2 cykly na dokončenie zápisu, takže aj keď je `wdata_valid = 1`, zápis sa niekedy odkladá.

```
Čas --->       1     2     3     4     5     6     7     8     9    10

FIFO DATA:    D1    D2    D3    D4    D5    D6    D7    -     -     -
wdata_valid:   1     1     1     1     1     1     1     0     0     0
SDRAM WR:      WR1    -    WR2   WR3    -    WR4   WR5   -     -     -
```

**Vysvetlenie:**

1. FIFO má dáta D1–D7 pripravené na zápis.
2. `wdata_valid = 1` kým sú dáta vo FIFO.
3. SDRAM zápis (`SDRAM WR`) niekedy mešká kvôli wait-states (`-` značí, že zápis sa odložil).
4. Po D7 je FIFO prázdne a `wdata_valid` ide na 0.

Tento diagram ukazuje realistickú situáciu, keď zápis do SDRAM nie je okamžitý a FIFO slúži ako vyrovnávacia pamäť.

Ak chceš, môžem spraviť **animovanú ASCII verziu krok po kroku**, kde uvidíš, ako FIFO klesá a zápisy sa striedajú so wait-states. Chceš, aby som to urobil?

Super! Tak tu je stručné zhrnutie toho, čo sme doteraz “prebehli”:

1. **ASCII** – systém kódovania znakov, kde každý znak (písmeno, číslo, symbol) má priradené číslo od 0 do 127. Napr. `A = 65`, `a = 97`. Používa sa na ukladanie textu v počítačoch.

2. **FIFO** – skratka pre *First In, First Out*. Znamená to, že prvý prvok, ktorý príde, je aj prvý, ktorý odíde. Ako rad ľudí čakajúcich na lístok: kto príde prvý, bude obslúžený prvý.

3. **SDRAM** – typ pamäte (*Synchronous Dynamic Random Access Memory*). Používa sa v počítačoch na rýchle čítanie a zápis dát. Je “synchronizovaná” s rýchlosťou procesora, čo ju robí rýchlejšou než staršie typy RAM.

V podstate sme sa dotkli **textu (ASCII)**, **štruktúry dát (FIFO)** a **hardvérovej pamäte (SDRAM)**.

Ak chceš, môžem urobiť aj **jednoduchú vizuálnu “mapu”, ako súvisia medzi sebou** – to veľmi pomáha zapamätať si tieto pojmy. Chceš, aby som ju urobil?


