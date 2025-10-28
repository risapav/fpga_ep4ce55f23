Výborné – toto je veľmi dobre napísaný **SDRAM kontrolér** (verzia s dôrazom na kompatibilitu s Quartusom a syntézu bez $bits či dynamických výrazov).
Nižšie som ti spravil **kompletnú analýzu architektúry, silných stránok a miest, ktoré stoja za úvahu pri rozširovaní alebo ladení**.

---

## 🧩 **Vysoká úroveň architektúry**

`SdramController` je **plnohodnotný radovo-cyklický FSM kontrolér** pre klasickú SDRAM s:

* automatickou **inicializáciou** (wait → precharge → refresh → MRS),
* **časovacími FSM stavmi** na dodržanie TRP, TRCD, TWR, TRFC, TRAS, TMRD,
* **FIFO rozhraniami** pre čítanie aj zápis (oddeľuje aplikačnú logiku od pamäťového časovania),
* **bank manažmentom** (stav ACTIVE/IDLE na každú banku),
* **burst riadením** a auto-precharge podporou,
* **refresh intervalom** riadeným vnútorným counterom.

---

## ⚙️ **Hlavné časti**

### 1. **Časovače (CountdownTimer)**

Každé SDRAM časovanie má vlastný inštančný modul. Použité sú parametre CTrp, CTrcd, CTwr, CTrfc, CTras, CTmrd.

➡️ Plus:

* Časovače sú **nezávislé a restartovateľné** signálom `load_*`.
* Odpočítavanie na 0 signalizuje "done".

➡️ Poznámka:

* Výhodou je, že FSM sa nemusí starať o presné počítanie cyklov.
* Nevýhodou je mierne väčšia plocha (každý timer má čítač), no pre FPGA to je úplne prijateľné.

---

### 2. **FIFO buffre**

Použité `AsyncFifoGeneric` moduly na oddelenie domén:

* write_fifo pre dáta zapisované do SDRAM,
* read_fifo pre dáta čítané zo SDRAM.

➡️ Plus:

* `level` výstupy umožňujú monitorovanie zaplnenia FIFO (užitočné pre riadenie AXI streamu alebo framebufferu).
* FIFO sú **synchronizované (TWO_STAGE_SYNC=1)** — vhodné pre viacdoménové použitie.

➡️ Potenciálne rozšírenie:

* Možno doplniť **error flag** (overflow/underflow) pre debugovanie.
* Ak FIFO pracujú v rovnakej hod. doméne (čo je tu pravdepodobne), async FIFO je možno "overkill" — možno nahradiť `SyncFifo`.

---

### 3. **FSM a správa bánk**

Každá banka má:

* stav (IDLE/ACTIVE),
* aktívny riadok (row),
* TRAS časovač.

FSM implementuje:

```
INIT → IDLE → (EVAL_BANK → ACTIVATE_CMD / PRECHARGE_CMD / READ_CMD / WRITE_CMD)
            → READ_BURST / WRITE_BURST → IDLE → REFRESH_CMD
```

➡️ Plus:

* Zohľadnené všetky SDRAM pravidlá vrátane TRAS pred PRECHARGE.
* Refresh je samostatný stav, ktorý má prioritu pred novými príkazmi.

➡️ Silné riešenie:

* `refresh_pending` flag sa aktivuje, keď prebehne časový interval, a kontrolér čaká na vhodný moment medzi príkazmi.
* FSM je dobre rozdelený — **jednoducho rozšíriteľný** o ďalšie príkazy (napr. burst terminate, load mode register 2, atď.).

---

### 4. **Riadenie výstupných pinov SDRAM**

Signály `sdram_cs_n`, `ras_n`, `cas_n`, `we_n` sú odvodené funkciou `get_sdram_cmd()`, ktorá vracia štruktúru pinov pre daný typ príkazu.

➡️ Veľmi čisté riešenie — **centrálna definícia mapovania** príkaz → piny.

---

### 5. **Zápis a čítanie dát**

* Pri zápise (`WRITE_BURST`) sa aktivuje `dq_write_enable`, dáta sa čítajú z `wr_fifo`.
* Pri čítaní (`READ_BURST`) sa dáta zapisujú do `read_fifo` po uplynutí CAS latency.

➡️ Logika CAS delay (`cas_cnt`) je korektne zahrnutá.

➡️ Potenciálne zlepšenie:

* Pre čítanie by bolo možné zaviesť **reálne zachytávanie dát zo `sdram_dq`** s oneskorením podľa CAS — aktuálne je to len schematické.

---

## 🧠 **Korektnosť a stabilita**

✅ **Quartus-kompatibilné**:

* žiadne `$bits` v indexoch,
* všetky čítače majú pevné bitové šírky,
* žiadne dynamické výrazy alebo implicitné pretypovania.

✅ **Synchronizácia signálov**: všetky vstupy/výstupy sú synchronizované na `clk`, výnimkou je `sdram_clk` odvodený z `clk_sh`.

✅ **Bezpečné FSM**: každé `case` má `default`.

---

## ⚠️ **Miesta na zváženie / zlepšenie**

1. **Refresh interval**

   ```
   localparam int CRefreshIntervalNs = 64_000_000 / (1 << ROW_ADDR_WIDTH);
   ```

   Toto je aproximácia. V skutočnosti refresh závisí od:

   * počtu riadkov (typicky 8192),
   * požadovaného času 64 ms → 7.8 µs interval.

   🔧 Odporúčanie: urobiť z tohto **parametrizovaný vstup (CRefreshIntervalCycles)**, aby sa dal prispôsobiť konkrétnemu čipu.

2. **`dq_write_enable_d` oneskorenie**
   Momentálne oneskoruje enable o 1 takt. Odporúčam skontrolovať, či je **časovanie s `sdram_dq` vo fáze so signálom `clk_sh`** — inak môžu nastať nesúlady na fyzickom rozhraní.

3. **Nepoužité TRAS timer pre refresh**
   Refresh neoveruje, či niektorá banka práve drží aktívny riadok. V praxi by refresh mal byť možný len keď sú všetky banky v IDLE — možno to FSM implicitne zabezpečuje (v `IDLE` stave).

4. **Error a debug monitorovanie**
   Pre reálne nasadenie by bolo vhodné doplniť:

   * `error_flag` ak sa dostane do neplatného stavu,
   * `init_done_o` výstup po ukončení inicializácie,
   * `busy_o` indikáciu aktivity (pre vonkajšiu arbitráciu).

---

## 🧩 **Integrácia s Framebuffer Controllerom**

Tento modul je **nízkoúrovňový SDRAM driver**, takže:

* Framebuffer controller (napr. `framebuffer_ctrl`) by s ním komunikoval len cez FIFO rozhrania.
* Ak chceš doplniť **validáciu vstupných dát/komandov**, môžeš vytvoriť *kontrolný wrapper* (`sdram_cmd_checker.sv`), ktorý:

  * sleduje prichádzajúce `wr_cmd_valid` / `rd_cmd_valid`,
  * overí, že adresy sú zarovnané a že `auto_precharge` nepôjde mimo rámec burstu,
  * prípadne vygeneruje `error_flag`.

➡️ To presne zapadá do tvojej úvahy o **separátnej kontrolnej logike** — nevplýva to na timing SDRAM FSM, lebo validácia beží paralelne.

---

## 📋 **Zhrnutie**

| Oblasť                | Hodnotenie      | Poznámka                          |
| --------------------- | --------------- | --------------------------------- |
| Časovacia logika      | ✅ výborná       | samostatné countdown moduly       |
| FSM pre riadenie bánk | ✅ robustný      | správne ošetrí všetky kombinácie  |
| FIFO rozhranie        | ✅ flexibilné    | oddelenie aplikačnej logiky       |
| Refresh mechanizmus   | ⚠️ dostatočný   | možno sprísniť podľa čipu         |
| Quartus syntéza       | ✅ bezproblémová | bez nekompatibilných konštrukcií  |
| Debug / kontrola      | ⚠️ chýbajúca    | možno doplniť moduly pre kontrolu |

---

Ak chceš, môžem ti pomôcť navrhnúť **modul „SdramCmdChecker.sv“**, ktorý by sa vložil medzi framebuffer a `SdramController` — s detekciou chybných príkazov, overovaním bank/row/col sekvencií a bez dopadu na časovanie.

Chceš, aby som ti ukázal návrh tejto kontrolnej vrstvy?
