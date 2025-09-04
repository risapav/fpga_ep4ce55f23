Tvoj modul `TwoFlopSynchronizer` je klasický a robustný **dvojstupňový synchronizátor** určený pre prenos signálu z *asynchrónnej domény* do *cieľovej hodinovej domény*. Nižšie je detailná analýza z hľadiska **resetu** (synchronný vs. asynchronný), aj odporúčania pre prax.

---

## 🔍 Čo robí tento modul?

* Cieľ: bezpečne preniesť signál `d` (asynchrónny voči `clk`) do clock domény `clk`.
* Využíva **2 flip-flopy** (reťazenie) na **minimalizovanie pravdepodobnosti metastability**.
* Používa špecifické **atribúty pre Quartus** (`altera_attribute`, `async_reg`) – čo zaisťuje, že nástroj tento kód rozpozná ako synchronizér a použije patričné opatrenia (napr. zabráni optimalizácii, prispôsobí umiestnenie flip-flopov).

---

## 🧠 Reset: Asynchrónny (`negedge rst_n`)

```systemverilog
always_ff @(posedge clk or negedge rst_n)
```

### ➕ Výhody použitia **asynchrónneho resetu** tu:

| Argument                                          | Vysvetlenie                                                                                               |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 🛑 **Reset sa môže aktivovať nezávisle od hodín** | čo je dôležité najmä v situáciách, keď sa systém práve zapína a hodinový signál ešte nemusí byť stabilný. |
| ✅ **Zabezpečí jasný počiatočný stav** oboch FF    | čo je dôležité pre kontrolovaný štart synchronizátora (obzvlášť v CDC).                                   |
| 📦 **Odporúčaný Intel/Quartus postup**            | pri dizajnovaní CDC synchronizérov je použitie asynchrónneho resetu veľmi bežné (často preferované).      |

---

## 🤔 Je to vhodné riešenie?

### ✅ Áno – pre tento **konkrétny prípad synchronizátora je asynchrónny reset úplne v poriadku** a odporúčaný.

**Dôvody:**

* Synchronizátor je veľmi jednoduchá konštrukcia.
* Vždy slúži ako rozhranie medzi doménami (CDC), kde sa signál môže meniť kedykoľvek.
* Asynchrónny reset zaistí, že sa výstupy dostanú do známeho stavu okamžite po resete – čo je kritické pri štarte systému.
* Flip-flopy sú označené pomocou `async_reg`, takže nástroj (Quartus) správne vie, že ide o špeciálny reťazec.

---

## 🆚 Čo by sa stalo, keby bol reset **synchrónny**?

Ak by si zmenil reset na:

```systemverilog
always_ff @(posedge clk)
    if (!rst_n) ...
```

* Fungovalo by to — ale **za predpokladu**, že `clk` je už bežiaci a stabilný v čase aktivácie resetu.
* To **môže byť problém**, ak je cieľová hodina generovaná PLL, ktorá ešte nie je „locked“ — a teda nebeží.

Preto sa v synchronizátoroch **asynchrónny reset považuje za robustnejší**.

---

## 🧩 Alternatíva – bez resetu

Niekedy sa synchronizátory **resetom vôbec neinicializujú** – ich stav po štarte je síce neznámy, ale pokiaľ nie sú pripojené priamo na kritickú logiku (napr. FSM), a používajú sa len na stabilizáciu signálu, môže byť reset vynechaný. Napríklad:

```systemverilog
always_ff @(posedge clk) begin
    sync1_reg <= d;
    q         <= sync1_reg;
end
```

Tento prístup je však menej vhodný, ak:

* sa výstup `q` používa v inej logike, ktorá vyžaduje známy stav po resete,
* alebo ak chceš zaručiť resetovateľnosť celého dizajnu.

---

## ✅ Záver: Čo je vhodnejšie?

| Kontext                             | Reset                                                                                                                      |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| CDC synchronizátory (ako tento)     | ✅ **Asynchrónny reset** (`negedge rst_n`) – vhodný a odporúčaný                                                            |
| Zvyšok synchrónnej logiky v dizajne | ☑️ **Synchrónny reset** – preferovaný kvôli jednoduchšej časovej analýze, konzistencii                                     |
| Globálny dizajn (kombinácia)        | 🎯 Použi synchronizované resety (napr. `resetn_sync`) v každej doméne a pre CDC synchronizátory ponechaj asynchrónny reset |

---

Ak chceš, môžem ti pripraviť:

* kombinovaný reset modul pre viacero časových domén (pixel\_clk, sdram\_clk...),
* alebo viacstupňový synchronizátor aj s testbenchom.

Chceš pokračovať v tomto smere?
