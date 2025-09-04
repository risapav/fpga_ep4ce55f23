Výborná otázka, ktorá ide do samotného srdca dizajnu asynchrónnych obvodov.

Odpoveď je jednoznačná: **Áno, tento návrh `AsyncFIFO` je plne univerzálny a symetrický.**

Je úplne jedno, ktorá časť (`wr` alebo `rd`) je pripojená na rýchlejšiu alebo pomalšiu hodinovú doménu. Modul bude fungovať správne a bezpečne pri akomkoľvek pomere frekvencií `wr_clk` a `rd_clk` (vrátane prípadu, keď sú frekvencie rovnaké, ale fázovo posunuté).

---

### Prečo je Návrh Univerzálny?

Robustnosť tohto dizajnu nespočíva v žiadnych predpokladoch o rýchlosti, ale v troch kľúčových princípoch, ktoré sú správne implementované:

#### 1. Kompletné Oddelenie Hodinových Domén
* **Zápisová logika** (inkrementácia `wr_ptr_bin`, zápis do `mem`) beží **výlučne** v doméne `wr_clk`.
* **Čítacia logika** (inkrementácia `rd_ptr_bin`, čítanie z `mem`) beží **výlučne** v doméne `rd_clk`.
* Spoločná pamäť `mem` je implementovaná ako "true dual-port RAM", kde je jeden port určený pre zápis a druhý pre čítanie, a každý z nich má svoj vlastný hodinový signál. Medzi týmito dvoma logikami neexistuje žiadna priama kombinačná cesta.

#### 2. Bezpečný Prenos Informácií Medzi Doménami
Jediné informácie, ktoré musia prejsť z jednej domény do druhej, sú hodnoty ukazovateľov (pointrov). Tento prenos je zabezpečený dvoma mechanizmami:
* **Grayov Kód:** Pred prenosom sa binárny pointer prevedie na Grayov kód. Kľúčová vlastnosť Grayovho kódu je, že pri každom inkremente sa mení **vždy len jeden bit**. Tým sa eliminuje riziko, že by cieľová doména zachytila nejakú neplatnú "prechodovú" hodnotu, kde by sa zmenilo viacero bitov naraz.
* **Dvojstupňový Synchronizátor:** Tento jediný meniaci sa bit (a aj tie ostatné, nemeniace sa) je následne bezpečne prenesený cez hranicu domén pomocou `TwoFlopSynchronizer`. Ten rieši problém metastability a zaručuje, že na druhej strane bude vždy stabilná (aj keď o 2 cykly oneskorená) hodnota.

#### 3. Nezávislý Výpočet Stavov (`full` / `empty`)
Toto je najdôležitejšia časť:
* **Stav `full`** sa vyhodnocuje **iba v zápisovej doméne (`wr_clk`)**. Porovnáva lokálny `wr_ptr_gray` s hodnotou `rd_ptr_gray`, ktorá bola bezpečne synchronizovaná *do* tejto domény. Zápisová strana sa teda rozhoduje na základe svojej aktuálnej pozície a mierne oneskorenej informácie o tom, kde bola čítacia strana.
* **Stav `empty`** sa vyhodnocuje **iba v čítacej doméne (`rd_clk`)**. Porovnáva lokálny `rd_ptr_gray` s hodnotou `wr_ptr_gray`, ktorá bola bezpečne synchronizovaná *do* tejto domény. Čítacia strana sa rozhoduje na základe svojej aktuálnej pozície a mierne oneskorenej informácie o tom, kde bola zápisová strana.

---

### Dôsledky pre Rýchlejšiu vs. Pomalšiu Doménu

To, ako sa bude FIFO správať (či sa bude plniť alebo vyprázdňovať), závisí od pomeru frekvencií a aktivity `wr_en` a `rd_en`, ale jeho **korektnosť a bezpečnosť zostáva zachovaná**:

* **Ak je `wr_clk` rýchlejší ako `rd_clk`:** FIFO bude mať tendenciu sa plniť. Kľúčovou sa stáva logika pre `full` a `almost_full`, ktorá zabráni zápisu do už plného buffera a predíde tak strate dát (overflow). Váš dizajn to zvláda.
* **Ak je `rd_clk` rýchlejší ako `wr_clk`:** FIFO bude mať tendenciu byť prázdne. Kľúčovou sa stáva logika pre `empty` a `almost_empty`, ktorá zabráni čítaniu z prázdneho buffera a predíde tak čítaniu neplatných dát (underflow). Váš dizajn to taktiež zvláda.

**Záver:**
Váš `AsyncFIFO` modul je skutočne univerzálny. Jeho robustnosť nespočíva v žiadnom predpoklade o vzájomných frekvenciách, ale v matematickej istote Grayovho kódu a v osvedčených metódach pre prekonávanie metastability a synchronizáciu resetu. Je to ukážkový príklad správneho a bezpečného CDC (Clock Domain Crossing) dizajnu.
