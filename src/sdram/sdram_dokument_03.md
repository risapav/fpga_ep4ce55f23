# 📄 Refaktorovaný SDRAM Kontrolér v7.11: Whitepaper

## Úvod

Tento dokument predstavuje podrobnú analýzu refaktorovaného SDRAM kontroléra v7.11, ktorý implementuje pokročilé architektonické vylepšenia a zlepšenia kvality RTL kódu. Cieľom je poskytnúť hlboký pohľad na zmeny v návrhu a ich dopad na výkon, flexibilitu a integráciu do komplexných systémov.

---

## Časť 1: Kľúčové Architektonické Zmeny a Ich Dopad

### 1.1 Implementácia Bank Interleaving: Skok vo Výkone

Kontrolér prešiel od jednoduchého lineárneho FSM k sofistikovanému plánovaču príkazov (EVAL_CMD), ktorý inteligentne riadi zdroje pamäte.

* **Sledovanie Stavu Bánk**: Každá banka má svoj vlastný stav (`bank_state`) a aktívny riadok (`active_row`), čo umožňuje efektívne riadenie prístupu.

* **Inteligentný Plánovač**: Stav EVAL_CMD vyhodnocuje cieľovú banku a rozhoduje o nasledujúcom príkaze na základe aktuálneho stavu banky.

* **Dopad na Výkon**: Tento prístup umožňuje prekrývanie operácií, čo zvyšuje využitie dátovej zbernice a celkovú priepustnosť systému.

### 1.2 Integrácia Hardvérového Auto-Precharge

Kontrolér teraz plne podporuje hardvérový auto-precharge, čo znižuje latenciu a zjednodušuje riadenie.

* **Implementácia**: V stavoch READ_CMD a WRITE_CMD sa adresný bit `sdram_addr[1]` nastavuje na základe príznaku `current_cmd.auto_precharge`.

* **Výhoda**: SDRAM čip automaticky uzavrie riadok po dokončení burstu, čím sa eliminuje potreba explicitného príkazu PRECHARGE_CMD.

### 1.3 Pridanie Write Data FIFO: Oddelenie (Decoupling) Systému

Implementácia `write_fifo` umožňuje aplikačnej logike zapisovať dáta nezávisle na stave SDRAM.

* **Funkčnosť**: Dáta sa ukladajú do FIFO pamäte, čo umožňuje aplikačnej logike pokračovať v práci bez čakania na dokončenie predchádzajúcej operácie.

* **Výhoda**: Tento prístup zvyšuje flexibilitu a robustnosť systému, odstraňuje potrebu stavu PREFETCH_WDATA a zjednodušuje FSM.

### 1.4 Vylepšená Parametrizácia a Štruktúra Kódu

Kód bol refaktorovaný na maximalizáciu flexibility a čitateľnosti.

* **Geometrické Parametre**: Kľúčové rozmery pamäte sú definované ako parametre, čo umožňuje jednoduchú rekonfiguráciu.

* **Automatické Odvodzovanie**: Z týchto parametrov sa automaticky vypočítavajú konštanty pre presné rezanie adries, čím sa eliminujú "magické čísla" a riziko chýb pri rekonfigurácii.

---

## Časť 2: Analýza Kvality Kódu a RTL Metodiky

### 2.1 Robustná Metodika _reg / _next

Celý kontrolér bol prepísaný s použitím _reg a _next signálov pre všetky stavové prvky, čo zlepšuje čitateľnosť a údržbu kódu.

* **Štruktúra**: Kombinačná logika je sústredená v jednom always_comb bloku, zatiaľ čo sekvenčný always_ff blok slúži len na priradenie _next hodnôt do _reg registrov na hrane hodinového signálu.

* **Výhody**: Tento prístup eliminuje riziko latchov, zlepšuje čitateľnosť a umožňuje lepšiu optimalizáciu syntetizačnými nástrojmi.

### 2.2 Efektívna Logika pre FIFO Počítadlá

Zmena v logike pre `fifo_r_count_next` a `fifo_w_count_next` zjednodušuje aritmetiku a zvyšuje efektivitu.

* **Pôvodná Logika**: Používala podmienky `if` a `else` na aktualizáciu počítadiel.

* **Nová Logika**: Používa aritmetický výraz `count_next = count + wr_en - rd_en`, čo je efektívnejšie a jasnejšie pre syntetizátor.

---

## Záverečné Hodnotenie a Potenciálne Ďalšie Kroky

### Hodnotenie

Refaktorovaný kód `sdram_controller_final.sv` predstavuje významný pokrok v kvalite aj výkone. Implementuje kľúčové techniky na maximalizáciu priepustnosti, znižuje latenciu a zvyšuje systémovú robustnosť. Štýl kódovania je na profesionálnej úrovni a modul je vďaka vynikajúcej parametrizácii ľahko adaptovateľný.

### Potenciálne Ďalšie Kroky

* **Power-Down Režim**: Implementácia riadenia signálu `sdram_cke` na vstup do Power-Down režimu pre aplikácie s nízkou spotrebou.

* **Quality of Service (QoS)**: Pridanie logiky QoS pre systémy s viacerými mastermi, ktorá by prioritizovala príkazy na základe ich dôležitosti.

* **Optimalizácia Časovačov**: Zlúčenie samostatných časovačov do jedného alebo dvoch zdieľaných časovačov pre extrémne optimalizácie z hľadiska plochy čipu.

---

## Záver

Refaktorovaný SDRAM kontrolér v7.11 predstavuje moderný a efektívny prístup k návrhu pamäťového riadiaceho modulu. Implementované vylepšenia zvyšujú výkon, flexibilitu a robustnosť systému, čo ho robí vhodným pre integráciu do komplexných aplikácií a systémov.

---
