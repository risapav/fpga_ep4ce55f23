Jasné, tu je podrobná analýza funkčnosti a návrh vylepšení pre poskytnutý SystemVerilog SDRAM kontrolér `sdram_ctrl_610.sv`.

-----

# Hĺbková Analýza a Vylepšenia pre SDRAM Kontrolér v6.10

Poskytnutý kód `sdram_ctrl_610.sv` predstavuje funkčný a dobre štruktúrovaný SDRAM kontrolér. Využíva moderné konštrukcie SystemVerilogu, je parametrizovateľný a obsahuje kľúčové prvky pre správne riadenie SDR SDRAM, vrátane inicializačnej sekvencie, obsluhy obnovovacích cyklov (refresh) a riadenia časovacích parametrov. Táto analýza sa zameriava na dekonštrukciu jeho súčasnej funkčnosti a následne navrhuje strategické vylepšenia na zvýšenie výkonu, robustnosti a flexibility.

## Časť 1: Analýza Súčasnej Funkčnosti

Kontrolér je navrhnutý okolo centrálneho konečného stavového automatu (FSM), ktorý riadi všetky operácie. Jeho architektúru môžeme rozdeliť do niekoľkých kľúčových funkčných blokov.

### 1.1 Architektúra a Tok Dát

  * **Rozhranie (Interface):** Kontrolér poskytuje elegantne oddelené rozhrania pre príkazy, zapisované dáta a čítané dáta.
      * **Príkazové FIFO (`cmd_fifo_*`):** Aplikácia posiela požiadavky na čítanie a zápis prostredníctvom tohto rozhrania. Tým sa aplikačná logika oddeľuje od nízkoúrovňového časovania SDRAM príkazov.
      * **Dátové rozhrania (`wdata_*`, `resp_*`):** Samostatné kanály pre zápis a čítanie dát zjednodušujú integráciu. Použitie `valid/ready` handshake signalizácie je štandardným a robustným prístupom.
  * **Interné Read FIFO:** Kontrolér implementuje internú FIFO pamäť pre dáta načítané z SDRAM. Toto je kriticky dôležité, pretože SDRAM poskytuje dáta v burstoch. FIFO slúži ako buffer, ktorý umožňuje aplikačnej logike odoberať dáta vlastným tempom, nezávisle od presného časovania SDRAM zbernice.
  * **Fyzické Rozhranie:** Modul správne definuje všetky potrebné výstupné porty pre riadenie SDRAM (`sdram_addr`, `sdram_ba`, `sdram_cs_n`, atď.). Dôležitým detailom je prítomnosť dvoch hodinových vstupov, `clk` a `clk_sh`. Toto predpokladá použitie fázovo posunutého hodinového signálu (`clk_sh`) pre SDRAM čip, čo je nevyhnutné pre spoľahlivú prevádzku pri vysokých frekvenciách na kompenzáciu oneskorení na PCB.[2, 3]

### 1.2 Riadiaca Logika (FSM)

Srdcom modulu je konečný stavový automat (FSM), ktorý starostlivo sekvencuje príkazy a vynucuje dodržiavanie časovacích obmedzení.

  * **Inicializácia (`INIT_*` stavy):** Po resete kontrolér prechádza sekvenciou stavov, ktorá zahŕňa čakanie na stabilizáciu napájania, vykonanie príkazu PRECHARGE, niekoľko REFRESH cyklov a nakoniec nastavenie Mode Registra (MRS). Tento postup je v súlade so špecifikáciami SDRAM.
  * **Spracovanie Príkazov (`IDLE`, `ACTIVE_*`, `RW_*`, `*_BURST`):** V kľudovom stave (`IDLE`) kontrolér čaká na požiadavku z `cmd_fifo`. Po prijatí príkazu postupne prechádza stavmi na aktiváciu riadku (`ACTIVE_CMD`), čakanie na $t_{RCD}$ (`ACTIVE_WAIT`) a následné vykonanie burstového čítania (`READ_BURST`) alebo zápisu (`WRITE_BURST`).
  * **Časovanie:** Všetky kľúčové časovacie parametre SDRAM (napr. `tRP`, `tRCD`, `tRAS`) sú definované ako parametre modulu. Ich dodržiavanie je zabezpečené pomocou jednoduchých odpočítavacích časovačov (napr. `trp_timer`), ktoré blokujú prechod FSM do ďalšieho stavu, kým neuplynie požadovaný čas.
  * **Refresh a Precharge:** Kontrolér autonómne riadi obnovovacie cykly pomocou `refresh_counter`. Keď je to potrebné, FSM z `IDLE` stavu prejde do `REFRESH_CMD`. Podobne, po dokončení operácie sa nastaví príznak `auto_precharge_pending`, ktorý FSM obslúži v stave `IDLE` prechodom do `PRECHARGE_CMD`.

### 1.3 Silné Stránky Kódu

  * **Parametrizácia:** Kľúčové vlastnosti ako frekvencia, šírka dát a adresy, a najmä časovacie parametre, sú plne parametrizovateľné.
  * **Moderný SystemVerilog:** Použitie `always_ff` a `always_comb`, `typedef enum` pre stavy FSM a importovanie balíčka (`sdram_pkg`) sú znakmi moderného a čistého RTL dizajnu.
  * **Robustnosť:** Zmeny vo verzii 6.10 (zmena `int` na `integer`, explicitné typovanie debug portu) svedčia o zameraní na kompatibilitu medzi rôznymi syntetizačnými nástrojmi.
  * **Simulácia a Ladenie:** Prítomnosť `assert` príkazov pre overenie integrity FIFO a časovania v simulačnom bloku (`ifndef SYNTHESIS`) je vynikajúcou praxou, ktorá urýchľuje vývoj a odhaľovanie chýb.

## Časť 2: Návrh Vylepšení

Napriek tomu, že kontrolér je funkčný, existuje niekoľko oblastí, kde je možné výrazne zvýšiť jeho výkon, flexibilitu a robustnosť.

### Vylepšenie 1: Implementácia Bank Interleaving pre Zvýšenie Priepustnosti

**Problém:** Súčasný FSM spracováva príkazy striktne sekvenčne. Počas čakania na uplynutie časových oneskorení, ako sú $t_{RCD}$ (oneskorenie medzi ACTIVATE a READ/WRITE) alebo $t_{RP}$ (čas na PRECHARGE), je kontrolér nečinný a nevyužíva dátovú zbernicu. Toto je najväčšie obmedzenie výkonu.

**Riešenie:** Využiť viacero bánk, ktoré SDRAM ponúka, na prekrývanie operácií (bank interleaving).[4] Zatiaľ čo jedna banka čaká na dokončenie časovo náročnej operácie (napr. aktivácia riadku), kontrolér môže vydať príkaz inej banke, ktorá je už pripravená.

**Implementácia:**

1.  **Sledovanie Stavu Bánk:** Namiesto jedného globálneho stavu FSM je potrebné udržiavať stav pre každú banku zvlášť. To sa dá realizovať pomocou poľa registrov, kde každý prvok uchováva informáciu o stave (napr. `IDLE`, `ACTIVE`) a adrese otvoreného riadku pre danú banku.
2.  **Inteligentný Plánovač Príkazov:** Logika, ktorá prijíma príkazy z `cmd_fifo`, sa musí stať inteligentnejšou. Musí analyzovať prichádzajúci príkaz (cieľovú banku a adresu) a na základe aktuálneho stavu všetkých bánk rozhodnúť, akú sekvenciu príkazov vygenerovať, aby sa minimalizovali prestoje.
3.  **Prioritizácia Príkazov:** Plánovač by mal uprednostňovať príkazy, ktoré smerujú do už aktívnych riadkov ("row hits"), pretože nevyžadujú cyklus PRECHARGE a ACTIVATE.

**Výhoda:** Dramatické zvýšenie efektívnej dátovej priepustnosti, pretože sa skrývajú latencie spojené s aktiváciou a prednabíjaním bánk.

### Vylepšenie 2: Podpora Skutočného Auto-Precharge

**Problém:** Súčasná implementácia "auto precharge" je riadená softvérovo v kontroléri. Po dokončení burstu sa nastaví príznak `auto_precharge_pending`, a FSM následne v stave `IDLE` explicitne vydá príkaz `PRECHARGE_CMD`. Tým sa spotrebuje jeden príkazový cyklus navyše.

**Riešenie:** Implementovať podporu pre hardvérový auto-precharge, ktorý je súčasťou SDRAM štandardu. Príkazy READ a WRITE môžu byť modifikované na READA (Read with Auto-Precharge) a WRITEA (Write with Auto-Precharge) nastavením adresného bitu A10 na vysokú úroveň počas vydania príkazu.[5]

**Implementácia:**

1.  **Rozšírenie Príkazu:** Štruktúra `sdram_cmd_t` v balíčku `sdram_pkg` by mala byť rozšírená o príznak, napr. `auto_precharge_en`.
2.  **Modifikácia FSM:** V stave `RW_CMD` by logika na základe tohto nového príznaku nastavila `sdram_addr[1] = current_cmd.auto_precharge_en;`.
3.  **Zjednodušenie Logiky:** Po dokončení burstu s auto-precharge už nie je potrebné nastavovať `auto_precharge_pending` a prechádzať stavom `PRECHARGE_CMD`. Banka sa automaticky uzavrie po uplynutí $t_{WR}$ (pre zápis) alebo po dokončení burstu a uplynutí $t_{RP}$ (pre čítanie).

**Výhoda:** Zvýšenie efektivity príkazovej zbernice ušetrením jedného cyklu na každý precharge, čo vedie k nižšej latencii a vyššej priepustnosti.

### Vylepšenie 3: Vylepšená Parametrizácia a Flexibilita

**Problém:** Niektoré kľúčové geometrické parametre pamäte sú v kóde definované napevno alebo implicitne, čo sťažuje adaptáciu pre iné typy SDRAM.

  * `NUM_BANKS` je parameter, ale šírka signálu `sdram_ba` je napevno `[1:0]`.
  * Počet stĺpcov je definovaný ako `localparam integer C_COLS = 9;`.
  * Šírky adries riadkov a stĺpcov sú odvodené z "magických čísel" pri rezoch adresy (napr. `current_cmd.addr[21:9]`).

**Riešenie:** Explicitne definovať všetky geometrické parametre a použiť ich na automatické odvodenie šírok signálov a rezov.

**Implementácia:**

```systemverilog
module SdramController #(
    //... existujúce parametre
    parameter integer ROW_ADDR_WIDTH    = 13,
    parameter integer COL_ADDR_WIDTH    = 9,
    parameter integer BANK_ADDR_WIDTH   = 2, // Alebo $clog2(NUM_BANKS)
    //...
)(
    //...
    output logic   sdram_addr, // Prispôsobiť šírku
    output logic  sdram_ba,
    //...
);

    // Príklad použitia v kóde
    localparam integer BANK_ADDR_HI = ADDR_WIDTH - 1;
    localparam integer BANK_ADDR_LO = BANK_ADDR_HI - BANK_ADDR_WIDTH + 1;
    localparam integer ROW_ADDR_HI  = BANK_ADDR_LO - 1;
    localparam integer ROW_ADDR_LO  = ROW_ADDR_HI - ROW_ADDR_WIDTH + 1;
    localparam integer COL_ADDR_HI  = ROW_ADDR_LO - 1;
    localparam integer COL_ADDR_LO  = COL_ADDR_HI - COL_ADDR_WIDTH + 1;

    //... v always_comb bloku
    ACTIVE_CMD: begin
        sdram_cs_n = 1'b0; sdram_ras_n = 1'b0;
        sdram_ba   = current_cmd.addr;
        sdram_addr = current_cmd.addr;
        //...
    end
```

**Výhoda:** Výrazne lepšia čitateľnosť, udržiavateľnosť a jednoduchá rekonfigurácia kontroléra pre prakticky akýkoľvek SDR SDRAM čip bez zásahov do logiky.

### Vylepšenie 4: Pridanie Write Data FIFO

**Problém:** Kontrolér má stav `PREFETCH_WDATA`, ktorý zastaví FSM, kým nie je k dispozícii prvé slovo zapisovaných dát. Počas burstového zápisu potom vyžaduje, aby aplikačná logika poskytla nové dáta v každom hodinovom cykle (`wdata_ready` je aktívne). Toto vytvára tesnú väzbu a môže zbytočne blokovať aplikačnú logiku.

**Riešenie:** Implementovať malú internú FIFO pamäť pre zapisované dáta, podobne ako je to urobené pre čítané dáta.

**Implementácia:**

1.  Pridať `wdata_fifo` s príslušnými ukazovateľmi a logikou počítadla.
2.  Upraviť `wdata_ready` tak, aby signalizovalo pripravenosť, kým `wdata_fifo` nie je plná.
3.  V stave `WRITE_BURST` odoberať dáta z `wdata_fifo` namiesto priameho použitia vstupného portu `wdata`.
4.  Stav `PREFETCH_WDATA` môže byť upravený tak, aby čakal, kým FIFO neobsahuje dostatok dát pre celý burst, alebo môže byť úplne odstránený, ak sa predpokladá, že dáta budú dostupné včas.

**Výhoda:** Oddelenie (decoupling) aplikačnej logiky od SDRAM zbernice. Aplikácia môže zapísať celý burst dát do FIFO a pokračovať vo svojej činnosti, zatiaľ čo kontrolér sa postará o ich včasné odoslanie do SDRAM.