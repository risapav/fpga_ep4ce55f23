Toto sú opäť skvelé a pokročilé otázky, ktoré svedčia o tom, že premýšľate nad správnymi vecami – nad štruktúrou projektu, automatizáciou a osvedčenými postupmi. Odpovede na ne sú kľúčové pre profesionálny vývoj.

Poďme si ich rozobrať.

---

### Otázka 1: Pridať súbory do projektu vs. použiť `` `include ``

Toto je zásadný rozdiel v prístupe. Stručná odpoveď znie: **Pre 99% prípadov je správna a robustná metóda pridať súbory do Quartus projektu.** Príkaz `` `include `` je špecializovaný nástroj, ktorého nesprávne použitie môže spôsobiť veľa problémov.

#### Prístup č. 1: Pridanie Súborov do Quartus Projektu (Odporúčaný Spôsob)

* **Ako to funguje:** V Quartuse (cez Project Navigator -> Files alebo priamo v `.qsf` súbore) poviete kompilátoru: "Tu je zoznam všetkých mojich zdrojových súborov (`.sv`, `.vhd`, `.qip`...)." Quartus ich potom spracuje ako samostatné **kompilačné jednotky**. Sám si zistí hierarchiu (ktorý modul je top-level, ktoré sú pod-moduly) a spravuje závislosti.
* **Kedy ho použiť:** Vždy, pre všetky vaše dizajnové súbory, ktoré obsahujú:
    * `module ... endmodule`
    * `package ... endpackage`
    * `interface ... endinterface`
* **Výhody:**
    * ✅ **Robustnosť:** Je to spôsob, akým sú nástroje navrhnuté pracovať. Zabraňuje náhodnému viacnásobnému definovaniu toho istého modulu.
    * ✅ **Prehľadnosť:** V projekte máte jasný zoznam všetkých súborov, ktoré tvoria váš dizajn.
    * ✅ **Efektivita:** Umožňuje nástrojom lepšie analyzovať a optimalizovať dizajn.

#### Prístup č. 2: Použitie Príkazu `` `include ``

* **Ako to funguje:** `` `include "subor.sv" `` funguje ako jednoduché **kopírovanie a vloženie textu**. Pred samotnou kompiláciou preprocesor vezme obsah súboru `subor.sv` a vloží ho presne na miesto, kde sa nachádza príkaz `` `include ``.
* **Kedy ho použiť (Zriedkavé prípady):**
    * Pre súbory, ktoré obsahujú **iba `` `define `` makrá**. Je to bežný spôsob, ako zdieľať globálne definície naprieč projektom (napr. `` `define CLOCK_FREQ 50_000_000 ``).
    * Niekedy sa používa na vloženie `interface` definícií, ako ste mali v komentári v `axi_interfaces.sv`.
* **Kedy ho NIKDY nepoužiť:**
    * **Nikdy ho nepoužívajte na vloženie súboru, ktorý obsahuje `module ... endmodule`!** Ak by ste takýto súbor vložili do dvoch rôznych modulov, výsledkom by bolo, akoby ste ten istý modul definovali dvakrát, čo okamžite vedie k chybe kompilácie "module redefined".

**Záver k otázke 1:** Vždy pridávajte vaše `.sv` súbory s modulmi, balíčkami a rozhraniami priamo do Quartus projektu. Príkaz `` `include `` si nechajte len pre veľmi špecifické prípady, ako sú zdieľané makrá.

---

### Otázka 2: Kompilácia bez Grafického Prostredia (IDE)

Odpoveď je jednoznačná: **Áno, bude to plne funkčné.** A nielen to, je to bežná prax v profesionálnom a automatizovanom prostredí (napr. pri nočných buildoch na serveri, v tzv. Continuous Integration/CI).

* **Ako to funguje:**
    Grafické prostredie Quartus Prime IDE je v skutočnosti len "pekný obal" (front-end) pre sadu veľmi výkonných **príkazových riadkových nástrojov**. Keď kliknete na tlačidlo "Start Compilation", IDE na pozadí postupne spúšťa tieto nástroje:
    * `quartus_map` (Analýza a Syntéza)
    * `quartus_fit` (Fitter - Umiestnenie a Prepojenie)
    * `quartus_asm` (Assembler - Generovanie `.sof` súboru)
    * `quartus_sta` (TimeQuest Timing Analyzer)
    * ...a ďalšie.

* **Čo definuje projekt:**
    Váš projekt nie je definovaný grafickým prostredím. Váš projekt je definovaný **súbormi, ktoré máte uložené v Gite**:
    1.  **`*.qpf`** (Quartus Project File) - Hlavný súbor, ktorý hovorí "toto je môj projekt".
    2.  **`*.qsf`** (Quartus Settings File) - Najdôležitejší súbor. Obsahuje zoznam všetkých súborov, priradenia pinov, výber čipu a všetky nastavenia kompilácie.
    3.  **`*.sdc`** (Synopsys Design Constraints) - Definuje hodiny a časovanie.
    4.  **Všetky vaše `*.sv` súbory.**

* **Ako sa to robí:**
    Môžete otvoriť príkazový riadok (terminál), navigovať sa do priečinku s projektom a spustiť napríklad `quartus_sh --flow compile fpga_prj.qpf`. Týmto jediným príkazom spustíte celý kompilačný proces, presne ako keby ste klikli na tlačidlo v IDE.

**Záver k otázke 2:** Váš projekt je plne prenositeľný a automatizovateľný. Všetko dôležité je uložené v textových súboroch, ktoré spravujete cez Git. GUI je len jedným z možných spôsobov, ako s týmito súbormi pracovať a ako spúšťať kompiláciu.
