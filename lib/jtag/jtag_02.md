Jasné, tu je podrobná analýza poskytnutého SystemVerilog kódu pre logiku USB Blaster II programátora.

Tento kód implementuje logiku pre FPGA, ktorá funguje ako most medzi USB rozhraním (prostredníctvom externého čipu FTDI FT245BM) a programovacím rozhraním cieľového zariadenia (napríklad iného FPGA alebo CPLD) pomocou protokolov ako JTAG, Active Serial (AS) alebo Passive Serial (PS).

---

### ## Hlavný účel a architektúra

Kód definuje modul `jtag_logic`, ktorého hlavnou úlohou je prijímať príkazy z hostiteľského počítača cez USB a prevádzať ich na nízkoúrovňové signály pre programovanie a ladenie (`TCK`, `TMS`, `TDI` atď.). Zároveň číta stavové signály z cieľového zariadenia (`TDO`, `ASDO`) a posiela ich späť do počítača.

Jadro modulu tvorí **stavový automat (State Machine)**, ktorý riadi celú komunikáciu. Komunikácia s PC prebieha cez externý čip FTDI, ktorý prevádza USB na paralelné 8-bitové dáta.

---

### ## Kľúčové komponenty

#### **1. Rozhranie (Vstupy/Výstupy)**

* **Signály pre FTDI čip:**
    * `nRXF`, `nTXE`: Riadacie signály z FTDI. `nRXF` (active-low) indikuje, že FTDI má dáta pre FPGA. `nTXE` (active-low) indikuje, že FPGA môže posielať dáta do FTDI.
    * `nRD`, `WR`: Riadacie signály do FTDI. `nRD` (čítanie) a `WR` (zápis) slúžia na prenos dát.
    * `D [7:0]`: Obojsmerná 8-bitová dátová zbernica na komunikáciu s FTDI čipom.

* **Signály pre cieľové zariadenie (JTAG/AS/PS):**
    * `B_TCK`, `B_TMS`, `B_TDI`: Štandardné JTAG výstupy (Test Clock, Test Mode Select, Test Data In).
    * `B_TDO`, `B_ASDO`: Štandardné JTAG/AS vstupy (Test Data Out, Active Serial Data Out).
    * `B_NCE`, `B_NCS`, `B_OE`: Špecifické riadiace signály, napr. pre AS režim alebo ovládanie výstupných budičov.

#### **2. Stavový automat (State Machine)**

Je to mozog celého zariadenia. Riadi sekvenciu operácií na základe príkazov z PC a stavu FTDI čipu. Používa štandardnú dvojblokovú štruktúru:
* `always_comb` blok: Vypočítava **nasledujúci stav** (`next_state`) na základe **aktuálneho stavu** (`state`) a vstupov.
* `always_ff` blok: Pri nábežnej hrane hodinového signálu (`CLK`) aktualizuje stav (`state <= next_state`) a riadi výstupné signály.

#### **3. Hlavné registre a signály**

* `ioshifter [7:0]`: 8-bitový register, ktorý slúži ako univerzálny posuvný register a zároveň ako držiak dát. Používa sa na:
    * Uloženie bajtu prijatého z PC.
    * Priame riadenie výstupných pinov.
    * Sériové posúvanie dát do a z cieľového zariadenia.
* `bitcount [8:0]`: 9-bitový čítač, ktorý sleduje počet bitov, ktoré sa majú sériovo posunúť.
* `drive_data`: Signál, ktorý riadi smer dátovej zbernice `D`. Ak je `1`, FPGA posiela dáta do FTDI. Ak je `0`, zbernica je v stave vysokej impedancie (`8'bz`) a FPGA môže prijímať dáta.

---

### ## Princíp fungovania

Logika pracuje v dvoch hlavných režimoch, ktoré sa prepínajú na základe príkazu (bajtu) prijatého z PC.

#### **Režim 1: Priame riadenie pinov (Bit-Banging)**

Tento režim sa aktivuje, keď prijatý bajt má najvyšší bit (`ioshifter[7]`) nastavený na `0`. Používa sa na pomalé, individuálne zmeny stavu JTAG pinov, napríklad pri prechode medzi stavmi JTAG TAP kontroléra.

**Priebeh:**
1.  FPGA čaká v stave `wait_for_nRXF_low`, kým FTDI signalizuje dostupné dáta (`nRXF=0`).
2.  Prečíta 8-bitový príkaz z FTDI zbernice `D` a uloží ho do `ioshifter` (stavy `set_nRD_low` až `latch_data_from_host`).
3.  V stave `bits_set_pins_from_data` sa jednotlivé bity z registra `ioshifter` priamo priradia na výstupné piny:
    * `B_TCK <= ioshifter[0];`
    * `B_TMS <= ioshifter[1];`
    * ... a tak ďalej.
4.  Bit `ioshifter[6]` určuje, či sa má vykonať aj čítanie zo vstupných pinov (`B_TDO`, `B_ASDO`). Ak áno, stavový automat prejde do stavu `bits_read_from_pins_and_wait_for_nTXE_low`, načíta vstupy a pošle ich späť do PC.

#### **Režim 2: Sériové posúvanie bajtov (Byte-Shifting)** 🚀

Tento režim je oveľa rýchlejší a používa sa na prenos dlhých sekvencií dát, ako sú JTAG scan reťazce. Aktivuje sa príkazom, kde najvyšší bit (`ioshifter[7]`) je `1`.

**Priebeh:**
1.  **Inicializácia:** Hostiteľ pošle špeciálny príkazový bajt. V stave `bytes_set_bitcount` sa z tohto bajtu nastaví:
    * `bitcount`: Počet bitov na prenos (až 64 bitov naraz, určených bitmi `ioshifter[5:0]`).
    * `do_output`: Príznak (`ioshifter[6]`), ktorý určuje, či sa po dokončení posúvania majú dáta prečítané z cieľa poslať späť do PC.
2.  **Posúvanie dát:** Hostiteľ následne pošle dáta, ktoré sa majú sériovo vyslať. FPGA vstúpi do rýchlej slučky stavov (`bytes_get_tdo_set_tdi` -> `bytes_clock_high_and_shift` -> `bytes_keep_clock_high` -> `bytes_clock_finish`). V každom cykle tejto slučky:
    * Nastaví sa výstupný bit `B_TDI` z `ioshifter[0]`.
    * Načíta sa vstupný bit z `B_TDO` (alebo `B_ASDO`).
    * Vygeneruje sa jeden pulz na hodinovom signáli `B_TCK`.
    * Register `ioshifter` sa posunie o jeden bit doprava a na najvyššiu pozíciu sa vloží prečítaný vstupný bit.
    * Čítač `bitcount` sa dekrementuje.
3.  **Ukončenie:** Po odvysielaní všetkých bitov (keď `bitcount` dosiahne nulu), slučka končí. Ak bol nastavený príznak `do_output`, obsah registra `ioshifter` (ktorý teraz obsahuje dáta prijaté z cieľového zariadenia) sa odošle späť do PC.

---

### ## Zhrnutie

Ide o efektívny a flexibilný dizajn, ktorý slúži ako inteligentný prekladač medzi vysokourovňovými príkazmi z PC a nízkoúrovňovým hardvérovým rozhraním. Využitie dvoch režimov (pomalé bit-banging pre riadenie a rýchle sériové posúvanie pre dáta) je kľúčové pre dosiahnutie vysokého výkonu, ktorým sú programátory typu USB Blaster II známe. Kód je dobre štruktúrovaný a využíva osvedčené postupy pre návrh stavových automatov v SystemVerilogu.
