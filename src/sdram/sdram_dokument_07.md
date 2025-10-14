Toto je **verzia 1.56** a musím povedať — veľmi dobre smeruješ. Implementácia v tejto revízii už ide do úrovne **profesionálneho DMA plánovania** s efektívnym využitím SDRAM-u (W9825G6KH-6) a kontinuálnym AXI-Stream tokom.
Nižšie som pripravil **analýzu a návrhy na ďalšie vylepšenie**, spolu s vysvetlením, **ako presne tento návrh pracuje pre tvoj prípad 800×600×16-bit frame**.

---

## 🧩 1. Prehľad logiky v1.56

### ✅ Nové schopnosti:

1. **Strategické Auto-Precharge:**

   * SDRAM riadok zostáva otvorený počas celej sekvencie burstov.
   * `auto_precharge` sa aktivuje len na poslednom burste segmentu.
   * Výsledok: minimalizuje sa *row activate latency* (tRCD + tRP), dosiahneš „row hit ratio“ až 90 %+ pri sekvenčnom prenose.

2. **Predictive Lookahead Reads:**

   * Čítací modul predvída nasledujúci segment ešte počas prenosu aktuálneho.
   * Využíva `read_lookahead_issued[]` — keď sa blíži koniec čítania segmentu, spustí sa *READ CMD* pre ďalší buffer.
   * Výsledok: latencia medzi segmentmi prakticky mizne.

3. **Subframe Streaming:**

   * `tlast` sa generuje podľa dĺžky subframe (`SUBFRAME_LEN_SEGMENTS`), nie iba na konci celého frame.
   * To je ideálne pre *video pipeline* (napr. 8 segmentov = 1 riadok alebo časť obrazu).

---

## 📈 2. Ako to beží pre frame 800×600×16 bit

| Parameter                | Hodnota                                   |
| ------------------------ | ----------------------------------------- |
| Frame veľkosť            | 800 × 600 × 2 B = **960 000 B**           |
| Počet slov (16 bit)      | **480 000 words**                         |
| `PACKET_LEN_WORDS`       | 8192 (napr. 16 segmentov po 512 burstoch) |
| `SEGMENT_LEN_WORDS`      | 1024                                      |
| `BURST_LEN`              | 8 (t. j. 8 × 2 B = 16 B na burst)         |
| Počet burstov na segment | 1024 / 8 = 128                            |
| Počet segmentov na frame | 480 000 / 1024 ≈ 469 segmentov            |

V tomto nastavení prebieha prenos **plynule**:

* Počas zápisu do SDRAM sa súčasne číta iný segment.
* Pri `NUM_BUFFERS = 4` systém dokáže rotovať v štýle **quad bufferingu**.
* SDRAM linka (166 MHz pre W9825G6KH-6) zvládne teoreticky až **332 MB/s**, čo pri 16 bit šírke a burstoch po 8 znamená ~**10 ns na burst**.

---

## ⚙️ 3. Časovania podľa W9825G6KH-6

| Parameter | Symbol | Typická hodnota (pri 166 MHz) |
| --------- | ------ | ----------------------------- |
| tCK       | 6 ns   | základný cyklus               |
| tRCD      | 18 ns  | delay medzi ACT a READ/WRITE  |
| tRP       | 18 ns  | precharge time                |
| tRC       | 60 ns  | refresh cycle                 |
| tWR       | 12 ns  | write recovery                |
| tREFI     | 7.8 µs | refresh interval              |

Implementácia využívajúca „open row per segment“ využije fakt, že **burst sekvencia 128×16 B = 2 kB** zostane v jednom riadku (typicky 2 kB – 4 kB per row).
Preto sa **tRP + tRCD overhead (36 ns)** zaplatí len raz na celý segment.

Výsledná efektívna priepustnosť pri 166 MHz:

[
\eta = \frac{t_{useful}}{t_{useful}+t_{overhead}} = \frac{128}{128+6} ≈ 95.5%
]

čo zodpovedá ~317 MB/s (zo 332 MB/s max).

---

## 🚀 4. Návrhy na vylepšenie

### 💡 a) Adaptive Segment Size

* Pridať parameter `AUTO_SEGMENT_OPTIMIZE`:

  * Pri detekcii menších paketov (napr. posledný frame alebo čiastkový blok) automaticky zmenší `SEGMENT_LEN_WORDS` tak, aby posledný segment presne pasoval.
* Výhoda: eliminuje prázdny prenos posledného segmentu.

---

### 💡 b) Command Queue Prefetch Depth

* Zaviesť malý FIFO pre príkazy (`cmd_prefetch_fifo`) s hĺbkou napr. 4.
* `issue_read_cmd` a `issue_write_cmd` by tak mohli plánovať príkazy dopredu aj v prípade, že SDRAM ešte spracúva predchádzajúci.

---

### 💡 c) Burst Interleaving

* Umožniť paralelné „interleaving“ burstov z rôznych bufferov (vhodné pre 2 banky SDRAM).
* Každý buffer by mal priradený bank index:

  ```systemverilog
  logic [1:0] bank_id = buffer_index[1:0];
  ```
* Tým sa aktivujú iné riadky v odlišných bankách → vyššia efektivita.

---

### 💡 d) Dynamický Burst Length

* Implementovať automatické prispôsobenie `BURST_LEN` podľa pipeline úrovne:

  * Pri nízkej obsadenosti použije kratšie bursty (nižšia latencia),
  * pri vysokej – dlhšie (vyššia efektivita).

---

### 💡 e) QoS Scheduler

* Pridať jednoduchý „priority arbiter“ medzi zápisom a čítaním:

  * Ak je výstupný stream `m_axis_tready` stále aktívny, uprednostni čítanie.
  * Ak pipeline pre zápis hrozí pretečením, okamžite povol zápisové bursty.

---

### 💡 f) Scatter-Gather DMA Layer (voliteľné)

* Vyššia úroveň by mohla generovať **descriptor list**:

  * `start_addr`, `len_words`, `next_desc_ptr`
  * Tým by wrapper fungoval ako plnohodnotný DMA engine pre viac typov dát (nielen frame).

---

## 📊 5. Zhrnutie

| Funkcia            | Verzia 1.56        | Možné vylepšenie                         |
| ------------------ | ------------------ | ---------------------------------------- |
| Overlapping I/O    | ✅                  | rozšíriť o bank interleaving             |
| Predictive Read    | ✅                  | rozšíriť na multi-depth prefetch         |
| Auto-Precharge     | ✅ inteligentné     | pridať adaptive burst closing            |
| Subframe Streaming | ✅                  | doplniť subframe sync trigger            |
| Pipeline Buffer    | ✅                  | pridať dynamic threshold                 |
| NUM_BUFFERS až 4   | ✅ plne podporované | možno zvýšiť do 8 s rozšírením adresácie |

---

Ak chceš, môžem ti pripraviť **verziu 1.57** so zapracovanými vylepšeniami (napr. adaptívny segment, QoS scheduler a interleaved read/write plánovač).
Chceš, aby som ju napísal?
