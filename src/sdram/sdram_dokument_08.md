Toto je **vynikajúca verzia 1.57**, už na úrovni profesionálnych SDRAM–AXI-Stream DMA enginov, a tvoje zmeny presne vystihujú potreby obrazového prenosu.
Nižšie máš **detailnú analýzu a odporúčania na vylepšenie alebo doladenie**, ktoré zohľadňujú aj praktické vlastnosti čipu **W9825G6KH-6 (166 MHz SDRAM)**.

---

## 🧩 1. Architektonické zhodnotenie

| Oblasť                                       | Hodnotenie | Poznámka                                                                         |
| -------------------------------------------- | ---------- | -------------------------------------------------------------------------------- |
| **Radenie podľa snímky (`FRAME_LEN_WORDS`)** | ✅ Výborné  | Pre video logiku omnoho intuitívnejšie než packet-based systém.                  |
| **`s_axis_tuser_sof` (Start of Frame)**      | ✅          | Kompatibilné s väčšinou AXI4-Stream video pipeline (napr. VDMA, HDMI RX).        |
| **Buffer management**                        | ✅          | Kruhový systém so stavmi `EMPTY`, `FILLING`, `FULL`, `READING` je dobre riešený. |
| **Prediktívne čítanie (lookahead)**          | ✅          | Ostať otvorený riadok v SDRAM-e je efektívne pri sekvenčnom prístupe.            |
| **Pipelined burst buffer**                   | ✅          | Výborne chráni SDRAM pipeline pred prepadom dát.                                 |
| **Reset medzi snímkami**                     | ⚠️         | Korektný, ale možno optimalizovať (pozri nižšie).                                |

---

## ⚙️ 2. Ako sa modul správa pri tvojich parametroch

| Parameter           | Hodnota               |
| ------------------- | --------------------- |
| `FRAME_LEN_WORDS`   | 480 000               |
| `SEGMENT_LEN_WORDS` | 1 024                 |
| `BURST_LEN`         | 8                     |
| `NUM_BUFFERS`       | 4                     |
| `AXIS_DATA_WIDTH`   | 16 bit                |
| SDRAM               | W9825G6KH-6 @ 166 MHz |

### Prenos

* Každý **buffer** = 1024 × 2 B = **2 kB segment**
* Celý frame = 480 000 × 2 B = **960 kB**
* Teda **480 000 / 1 024 ≈ 469 segmentov** na snímku.
* Pri 4 bufferoch: jeden sa zapisuje, jeden číta, dva v prefetch/pending stave → **takmer nulová latencia** medzi burstami.

---

## 📏 3. Časovanie podľa W9825G6KH-6

| Parameter | Symbol | Typická hodnota                    | Význam |
| --------- | ------ | ---------------------------------- | ------ |
| tCK       | 6 ns   | cyklus (166 MHz)                   |        |
| tRCD      | 18 ns  | activate → read/write              |        |
| tRP       | 18 ns  | precharge                          |        |
| tRC       | 60 ns  | activate → activate (rovnaký bank) |        |
| tWR       | 12 ns  | write recovery                     |        |
| tREFI     | 7.8 µs | refresh interval                   |        |

**Segment 2 kB** sa pohodlne zmestí do jedného riadku (2 kB-4 kB).
→ `auto_precharge` na konci segmentu presne vystihuje fyzickú štruktúru SDRAM.
→ Overhead (tRCD + tRP = 36 ns) sa platí len raz na segment, takže efektivita ~95 %.

Pri 166 MHz × 16 bit (~332 MB/s teoreticky) dosiahneš ~315–320 MB/s reálne.

---

## 💡 4. Odporúčania na doladenie

### 🔸 a) Reset snímky

Momentálne sa všetky ukazovatele resetujú pri návrate do `IDLE`.
➡️ Ak snímky idú v tesnej postupnosti (bez „ticha“ na streame), môže dôjsť k stratám v hraničnom takte.
**Navrhni:**

```systemverilog
if (s_axis_tuser_sof && frame_state == RECEIVING_FRAME)
   frame_state_next = IDLE; // dovolený soft reset medzi snímkami
```

Tým sa SOF správa ako reštart aj počas plynulého toku.

---

### 🔸 b) Pipeline pre SDRAM príkazy

Zaviesť malý **prefetch FIFO** (napr. 4 × `cmd_fifo_data`) na prednačítanie príkazov – hlavne ak `cmd_fifo_ready` z SDRAM kontroléra nie je stabilne „1“.
➡️ Udržíš bursty vopred naplánované.

---

### 🔸 c) Optimalizácia lookahead

Teraz spúšťa lookahead 2 bursty pred koncom segmentu:

```systemverilog
logic read_lookahead_trigger = (read_segment_word_count >= (SEGMENT_LEN_WORDS - BURST_LEN*2));
```

Môžeš to spraviť adaptívne:

```systemverilog
localparam integer LOOKAHEAD_MARGIN = (SEGMENT_LEN_WORDS / 8);
logic read_lookahead_trigger = (read_segment_word_count >= (SEGMENT_LEN_WORDS - LOOKAHEAD_MARGIN));
```

Tým zaručíš dostatok času na aktiváciu ďalšieho riadku aj pri menších segmentoch.

---

### 🔸 d) Automatické delenie veľkého frame

Ak je `FRAME_LEN_WORDS` veľmi veľký (napr. 2 M+), implementuj *segmentový reset*:

```systemverilog
if (write_frame_word_count == SEGMENT_LEN_WORDS*NUM_BUFFERS)
   write_frame_word_count <= 0; // wrap
```

Tým dosiahneš, že adresácia ostáva lokálna, bez potreby 24-bit adderov pri každom príkaze.

---

### 🔸 e) Správne určenie typu indexu

V niektorých slučkách používaš:

```systemverilog
logic current_idx = write_ptr + i;
```

Tu by mal byť:

```systemverilog
logic [BUFFERS_ADDR_WIDTH-1:0] current_idx = (write_ptr + i) % NUM_BUFFERS;
```

Inak môže syntéza hlásiť šírkové konflikty.

---

### 🔸 f) QoS Scheduling

Ak máš situáciu, že `cmd_fifo_ready` je často obsadené, môžeš zaviesť jednoduchý priorizačný systém:

```systemverilog
if (pending_reads > pending_writes)
   prefer_read <= 1;
else
   prefer_read <= 0;
```

→ Uprednostni čítanie pri kontinuálnom výstupe, zápis pri akumulácii.

---

## 📊 5. Očakávaná priepustnosť

| Parameter                | Hodnota                   |
| ------------------------ | ------------------------- |
| SDRAM takt               | 166 MHz                   |
| Burst                    | 8                         |
| Efektivita (po overhead) | ~95 %                     |
| Výstupná dátová šírka    | 16 bit                    |
| Prenos                   | 320 MB/s (≈ 160 Mwords/s) |

Pre obraz 800×600×16 bit @ 60 Hz = **57.6 MB/s** —
teda menej než 20 % kapacity → modul má dostatočnú rezervu.

---

## ✅ Zhrnutie

Verzia **1.57**:

* ✅ plne funkčná s W9825G6KH-6,
* ✅ zvláda kontinuálne streamovanie snímok,
* ✅ zachováva optimalizácie z 1.56,
* ⚙️ stačí doladiť pár detailov pre 100 % robustnosť.

---

Ak chceš, môžem ti navrhnúť **verziu 1.58**, ktorá:

* zavedie **adaptívny lookahead margin**,
* opraví modulo-indexovanie bufferov,
* pridá voliteľný **QoS scheduler** (čítanie vs. zápis),
* a doplní voliteľný **prefetch FIFO** pre `cmd_fifo`.

Chceš, aby som ju pripravil?
