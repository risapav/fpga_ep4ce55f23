Tu je detailná analýza refaktorovaného kódu verzie **1.60**:

---

### **1. Architektúra a modulárnosť**

* Modul `AxiStreamSdramWrapper` funguje ako most medzi **AXI-Stream** a **SDRAM**.
* Parametre umožňujú flexibilné nastavenie:

  * Počet slov vo frame (`FRAME_LEN_WORDS`), segmentov (`SEGMENT_LEN_WORDS`), počet bufferov (`NUM_BUFFERS`), pipeline hĺbku (`PIPELINE_DEPTH_BURSTS`), prah pre zápisy (`PIPELINE_WRITE_THRESHOLD_BURSTS`), burst pre lookahead (`READ_LOOKAHEAD_TRIGGER_BURSTS`).
  * AXI a SDRAM špecifické parametre: šírka dát, BURST_LEN, základná adresa SDRAM, hĺbka FIFO.

---

### **2. Predpočítané adresy bufferov**

* Starý spôsob: `BUFFER_BASE_ADDR = SDRAM_BASE_ADDR + write_ptr * SEGMENT_LEN_WORDS`.
* Nový spôsob: **statické pole predpočítaných adries**:

```systemverilog
localparam logic [SDRAM_ADDR_WIDTH-1:0] BUFFER_BASE_ADDRS [NUM_BUFFERS-1:0] =
    gen_buffer_addrs(SDRAM_BASE_ADDR, SEGMENT_LEN_WORDS, NUM_BUFFERS);

function automatic logic [SDRAM_ADDR_WIDTH-1:0] [NUM_BUFFERS-1:0] gen_buffer_addrs(...);
```

* Výhoda: odstránené násobenie pri syntéze → lepšie **timing closure**, menej LUT a jednoduchšie routovanie.

---

### **3. Stavový stroj pre kruhové buffery**

* `buffer_state` pre každý buffer: `EMPTY`, `FILLING`, `FULL`, `READING`.

* Ukazovatele: `write_ptr`, `read_ptr`.

* Riadenie zápisu:

  * Keď buffer prázdny a prichádza AXI dáta → `FILLING`.
  * Po odoslaní všetkých burstov → `FULL` a posun write_ptr.

* Riadenie čítania:

  * Keď buffer plný a vydaný read príkaz → `READING`.
  * Po prečítaní segmentu → `EMPTY` a posun read_ptr.

* **Agresívny lookahead**:

  * Hľadá prvý buffer `FULL`, ktorý ešte nemá vydaný príkaz, a predčasne vydáva read.

---

### **4. Pipeline buffer**

* `w_pipeline_buffer` slúži ako hlboký pipeline pre zápis.
* Ukazovatele: `w_pipeline_wptr` a `w_pipeline_rptr`.
* Počet slov v pipe: `w_pipeline_level`.
* Logika:

  * Pridávanie: `s_axis_tvalid && s_axis_tready`.
  * Odoberanie: `wdata_valid && wdata_ready`.
* Adaptive write threshold:

  * Burst sa vydáva, keď `w_pipeline_level >= PIPELINE_WRITE_THRESHOLD_WORDS`.

---

### **5. Príkazový arbiter**

* Podmienky pre vydanie príkazu:

  ```systemverilog
  logic can_issue_write = (w_pipeline_level >= PIPELINE_WRITE_THRESHOLD_WORDS) && (buffer_state[write_ptr] == FILLING);
  logic can_issue_read  = (buffer_state[read_ptr] == READING);
  logic can_push_to_cmd_fifo = (cmd_fifo_level_i < CMD_FIFO_DEPTH - 4);
  ```

* Priorita:

  1. **Agresívny lookahead read**.
  2. Bežný read.
  3. Write burst.

* `cmd_fifo_data` využíva **predpočítané adresy** (`BUFFER_BASE_ADDRS`) + offset burstu.

* Automatická precharge logika pre posledný burst segmentu.

---

### **6. AXI-Stream výstupy**

* `wdata_valid`, `wdata` → pipeline buffer.

* `m_axis_tvalid`, `m_axis_tdata`, `m_axis_tlast`:

  * `tlast` je zjednodušený: `is_last_word_of_frame = (read_frame_word_count == FRAME_LEN_WORDS-1)`.

* `resp_ready = m_axis_tready` → spätné tlmenie (handshaking).

---

### **7. Debug porty**

* `dbg_active_reads  = $countones(read_cmd_issued)`
* `dbg_active_writes = $countones(buffer_state == FILLING)`
* Exportované na `active_reads` a `active_writes`.
* Pomáhajú pri ladení DMA scheduleru a vyhodnocovaní pipeline využitia.

---

### **8. Optimalizácie a refaktorácie**

1. **Predpočítané adresy** → odstránené násobenie a priamy prístup.
2. **Simplified tlast** → zrozumiteľnejšia logika.
3. **Burst coalescing** → FIFO kontrola s rezervou (`CMD_FIFO_DEPTH-4`), umožňuje viac burstov naraz.
4. **Modulárnosť**:

   * Sekvenčná logika (`always_ff`) oddelená od kombinácie (`always_comb`).
   * Debug a counting logika integrovaná bez zmätkov.
5. **Robustnosť**:

   * Circular buffer indexovanie s modulo: `(read_ptr + i) % NUM_BUFFERS`.
   * Predchádza pretečeniu čítačov.
6. **Syntéza-ready**:

   * Všetky logické signály explicitne typované (`logic`).
   * Nettype: none → žiadne implicitné nets.

---

### **9. Potenciálne miesta na zlepšenie**

* `$countones(buffer_state == FILLING)` nemusí byť priamo syntézovateľné vo všetkých nástrojoch; môže byť potrebné explicitné prechádzanie po poliach.
* Funkcia `gen_buffer_addrs` je **constant function**, syntéza ju musí podporovať (väčšina moderných nástrojov áno).
* FIFO rezervu (`-4`) možno parametrizovať pre flexibilnejšie ladenie throughputu.

---

### **10. Zhrnutie**

Verzia **1.60** je:

* **Efektívna**, využíva predpočítané adresy.
* **Robustná**, s jednoduchou logikou pre tlast a circular buffer.
* **Flexibilná**, s debug portami pre monitorovanie.
* **Syntéza-ready**, pripravená pre FPGA implementácie s vysokou priepustnosťou.

---

Ak chceš, môžem vytvoriť **vizuálny diagram dátového toku a príkazového arbitra**, ktorý ukáže, ako prebieha pipeline, lookahead a burst coalescing.

Chceš, aby som ho nakreslil?
