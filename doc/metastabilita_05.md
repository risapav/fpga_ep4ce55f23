Výborná otázka. "Pretekové podmienky" (Race Conditions) je jeden z najdôležitejších konceptov v digitálnom návrhu a programovaní. Je to častá príčina chýb, ktoré sa veľmi ťažko hľadajú, pretože sa prejavujú len niekedy.

### Analógia z reálneho sveta

Predstavte si križovatku bez semaforov. Dve autá prichádzajú z rôznych smerov v približne rovnakom čase. Čo sa stane?
* Ak auto A "vyhrá preteky" a prejde prvé, všetko je v poriadku.
* Ak auto B "vyhrá preteky", všetko je v poriadku.
* Ak dorazia presne naraz, nastane zrážka (chyba systému).

Výsledok (bezpečná jazda alebo zrážka) závisí od presného, často náhodného načasovania príchodu áut. Toto je presne podstata pretekovej podmienky.

### Definícia

**Preteková podmienka** je chyba v systéme (či už hardvérovom alebo softvérovom), kde výsledok operácie nečakane závisí od nekontrolovateľného poradia alebo načasovania paralelných udalostí. Systém sa stáva **nedeterministickým** – pri rovnakých vstupoch môže niekedy fungovať správne a inokedy zlyhať.

V kontexte SystemVerilogu a návrhu hardvéru rozlišujeme dva hlavné typy:

1.  **Pretekové podmienky v SIMULÁCII** (chyba v kóde a simulátore)
2.  **Pretekové podmienky v REÁLNOM HARDVÉRI** (fyzikálny problém, tzv. časovacie hazardy)

---

### 1. Pretekové podmienky v SIMULÁCII

Toto sú chyby, ktoré vznikajú kvôli tomu, ako simulátor vyhodnocuje paralelne bežiace procesy (`always` a `initial` bloky) v tom istom časovom kroku.

**Príčina:** Simulátor musí vykonať všetky príkazy naplánované na čas `t` predtým, ako sa posunie na čas `t+1`. Ak máte dva `always` bloky, ktoré menia tú istú premennú, alebo jeden číta premennú, ktorú druhý v tom istom momente mení, výsledok závisí od poradia, v akom simulátor tieto dva bloky vyhodnotí.

**Riešenie: Blocking (`=`) vs. Non-blocking (`<=`) priradenia**

SystemVerilog má na riešenie tohto problému dva typy priradení:

* **Blocking priradenie (`=`):**
  * **Význam:** "Urob TOTO HNEĎ TERAZ a nepokračuj vo vykonávaní tohto bloku, kým to nie je hotové."
  * **Problém:** Ak ho použijete v sekvenčnej logike (`always_ff`), vytvoríte pretekovú podmienku. Výsledok bude závisieť od poradia `always` blokov v simulátore.

* **Non-blocking priradenie (`<=`):**
  * **Význam:** "Naplánuj, aby sa TOTO STALO na konci aktuálneho časového kroku, ale medzitým pokračuj vo vyhodnocovaní."
  * **Riešenie:** Všetky pravé strany (`a + b`) sa najprv vyhodnotia s použitím "starých" hodnôt a potom sa na konci časového kroku všetky ľavé strany (`c <= ...`) naraz aktualizujú "novými" hodnotami. Poradie `always` blokov už nehrá rolu.

**Zlaté pravidlá na predchádzanie simulačným pretekom:**
1.  Pre **sekvenčnú logiku** (popis registrov v `always_ff`) **VŽDY** používajte **non-blocking (`<=`)** priradenie.
2.  Pre **kombinačnú logiku** (popis hradiel v `always_comb`) **VŽDY** používajte **blocking (`=`)** priradenie.
3.  Pre priraďovanie hodnôt v `assign` **VŽDY** používajte **blocking (`=`)** priradenie.

---

### 2. Pretekové podmienky v REÁLNOM HARDVÉRI (časovacie hazardy)

Toto sú fyzikálne problémy, kde sa signály v čipe "pretekajú" po rôzne dlhých cestách.

**Príčina:** Signál sa šíri z bodu A do bodu B nejaký čas. Ak sa ten istý signál rozdelí a jeho dve vetvy idú k jednému cieľu (napr. k vstupu do registra) po dvoch rôzne dlhých dráhach, jedna príde skôr ako druhá.

**Najčastejší príklad:**
Signál hodín (`clk`) ide do klopného obvodu priamo, ale dáta (`D`) na jeho vstup idú cez zložitú kombinačnú logiku. Ak táto logika trvá príliš dlho, dáta sa nestihnú ustáliť predtým, ako príde hrana hodín (porušenie **setup time**). Alebo ak sa dáta zmenia príliš rýchlo po hrane hodín (porušenie **hold time**).

**Dôsledok:**
* **Glitche:** Krátke, nechcené pulzy na signáloch.
* **Metastabilita:** Výstup klopného obvodu je neistý čas v nedefinovanom stave (niekde medzi 0 a 1).
* **Nesprávna funkcia:** Obvod načíta nesprávne dáta.

**Riešenie:**
* **Striktný synchrónny návrh:** Všetky registre v jednej hodinovej doméne sú taktované tým istým, čistým hodinovým signálom.
* **Statická časovacia analýza (STA):** Nástroje ako Quartus po syntéze analyzujú všetky cesty v návrhu a vypočítajú, či signály stihnú doraziť včas. Ak nie, nahlásia "Timing violation", ktorú musí dizajnér opraviť (napr. zjednodušením logiky alebo pridaním ďalšieho registra – pipelining).

### Zhrnutie

| Kritérium | Preteky v Simulácii | Preteky v Hardvéri |
| :--- | :--- | :--- |
| **Príčina** | Neurčité poradie vyhodnocovania paralelných blokov v simulátore. | Fyzikálne oneskorenie signálu v dráhach s rôznou dĺžkou. |
| **Dôsledok** | Nedeterministické správanie simulácie, výsledok sa môže líšiť. | Metastabilita, hazardy, porušenie časovania (setup/hold). |
| **Riešenie** | Správne používanie **blocking (`=`)** a **non-blocking (`<=`)** priradení. | Striktný **synchrónny návrh** a časovacia analýza (STA). |
| **Kde sa prejaví**| V simulačnom nástroji (Icarus Verilog, ModelSim). | Po syntéze v reálnom čipe (FPGA/ASIC). |

V skratke, pretekové podmienky sú o nepredvídateľnosti spôsobenej zlým načasovaním. V SystemVerilogu im predchádzame hlavne správnym používaním `blocking (=)` a `non-blocking (<=)` priradení, zatiaľ čo v hardvéri im predchádzame striktným synchrónnym návrhom.