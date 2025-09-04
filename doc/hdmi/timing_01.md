Skvelá otázka! 🧠 Ak chceš pochopiť **časovanie VGA a HDMI**, tu sú **najlepšie overené zdroje** + rýchle vysvetlenie rozdielov a kde čo nájdeš:

---

## 🧭 KDE ZAČAŤ – OSVEDČENÉ ZDROJE:

### 📘 **1. [tinyvga.com/vga-timing](https://tinyvga.com/vga-timing)**

* Najlepšia stránka na pochopenie základov VGA časovania (napr. 640×480 @60Hz)
* Vizualizácia: aktívna oblasť + front porch + sync + back porch
* Zahŕňa:

  * pixely / linie
  * trvanie jedného riadku a rámca
  * polaritu synchronizačných impulzov
* 💡 Ideálne pre dizajnárov modulov ako `Line.sv`

---

### 📄 **2. VESA VGA/HDMI štandardy (oficiálne alebo sumarizované)**

* Pre úplne presné časy podľa rozlíšenia (napr. FullHD, 4K), najpresnejšie sú tzv. **CVT / GTF** normy:

  * CVT (Coordinated Video Timings)
  * GTF (Generalized Timing Formula)
* Výborný zdroj sumarizovaných tabuliek:

  * [https://tomverbeure.github.io/video\_timings\_calculator](https://tomverbeure.github.io/video_timings_calculator)
* Tabuľky obsahujú:

  * horizontal/vertical rozlíšenie
  * sync pulse
  * back/front porch
  * pixel clock

---

### 📘 **3. HDMI Timing Basics (Analog Devices alebo Lattice/Intel App Notes)**

* HDMI využíva **TMDS** a rámce na vyššej vrstve ako VGA, ale časovanie signálov je **veľmi podobné VGA**
* HDMI je **digitálny**, VGA **analógový**, ale obsahuje rovnaké:

  * aktívnu video oblasť
  * H/V sync (len enkódovanú)
  * blanking obdobia
* HDMI má navyše:

  * **Data islands** (napr. pre audio)
  * TMDS linky (3+1)
  * Scrambling a encoding (napr. 8b/10b)

> 🔗 Napr.:
> [https://www.analog.com/en/analog-dialogue/articles/hdmi-made-simple.html](https://www.analog.com/en/analog-dialogue/articles/hdmi-made-simple.html)

---

### 🧪 **4. Kód + projekty na GitHub (VGA alebo HDMI)**

* Hľadaj projekty:
  `site:github.com vga timing verilog`
  `site:github.com hdmi transmitter fpga`

* Napr.:

  * [FPGA Graphics](https://github.com/hamsternz/hamsterworks/tree/master/Projects/Graphics)
  * [Project VGA](https://www.cs.cmu.edu/~fpga/vga.shtml)

---

## ⚖️ Rýchle porovnanie: VGA vs HDMI

|             | **VGA**                           | **HDMI**                                   |
| ----------- | --------------------------------- | ------------------------------------------ |
| Typ signálu | Analógový (R, G, B, HSync, VSync) | Digitálny (TMDS, DDC, CEC)                 |
| Kódovanie   | Žiadne                            | TMDS (Transition Minimized Data Signaling) |
| Časovanie   | Voľné, jednoduché                 | Presné, fixné rozlíšenia, pixel clock      |
| Zvuk        | Nie                               | Áno (v data islands)                       |
| Použitie    | Staršie monitory, projektory      | Moderné monitory, TV, HDMI Rx čipy         |

---

## 🛠️ Ak to chceš použiť v dizajne:

* Na FPGA (VGA):

  * Vytváraš HSync a VSync podľa daného rozlíšenia
  * Používaš state machine ako tvoj modul `Line.sv`
* Na FPGA (HDMI):

  * Pridávaš TMDS enkóder
  * Zvyčajne používaš PLL pre pixel clock ×10
  * Potrebuješ špeciálne výstupné piny alebo HDMI IP core

---

## ➕ Chceš niečo praktické?

Môžem ti:

* vytvoriť **tabuľku časovania** pre VGA 640×480 alebo 1920×1080
* napísať **generátor LineX a LineY** z parametrov rozlíšenia
* alebo spraviť **HDMI video výstup (zjednodušený)** v SystemVerilogu

Povedz, čo by si chcel rozšíriť či otestovať.

Skvelá otázka! HDMI **data islands** sú špeciálne dátové bloky (napr. pre **audio**, **infoframe**, **HDCP**, atď.), ktoré sa **neprenášajú počas aktívnej video oblasti**, ale práve počas tzv. **blanking intervalov** – teda **mimo zobrazovaného obrazu**.

---

## 📦 **Kedy sa prenášajú HDMI data islands?**

➡️ **Počas horizontal a vertical blanking intervalov**:

* **Horizontal blanking** (medzi pixelmi jedného riadku)
* **Vertical blanking** (medzi jednotlivými rámcami)

V týchto intervaloch:

* namiesto video dát sa do HDMI streamu **vloží tzv. control period** alebo **data island**
* HDMI vysielač (TMDS encoder) prepne TMDS kanály do špeciálneho režimu

---

## 🎯 Presne v HDMI rámci:

HDMI video signál je štruktúrovaný takto:

```
Frame (obraz)
├── Active Video (pixel data)
├── Control Periods (medzi riadkami – HBlank)
└── Data Islands (najmä počas VBlank, ale aj niekedy počas HBlank)
```

### 📌 Typická štruktúra:

| Interval               | Obsah TMDS dát                                  |
| ---------------------- | ----------------------------------------------- |
| **Active video**       | Kódované pixely (RGB)                           |
| **Control period**     | TMDS control codes (HSync, VSync, Video Enable) |
| **Data island period** | Napr. Audio, InfoFrame, SPD, Vendor Specific    |

---

## 📺 Príklad:

Pre rozlíšenie 1920×1080\@60Hz s TMDS:

* 148.5 MHz pixel clock
* každý frame má:

  * aktívne video: 1920×1080 pixelov
  * * horizontal blanking (280 pixelov)
  * * vertical blanking (45 riadkov)

➡️ **Data islands sa typicky prenášajú počas tých 45 riadkov vertikálneho blankingu**
(plus v niektorých horizontal blanking oknách – napr. medzi aktívnymi riadkami).

---

## 📎 Typické HDMI data islandy obsahujú:

| Názov                               | Obsahuje napr.                       |
| ----------------------------------- | ------------------------------------ |
| **Audio sample packet**             | PCM audio dáta                       |
| **Audio clock regeneration**        | Na synchronizáciu audio/video        |
| **InfoFrame**                       | Formát obrazu, aspect ratio          |
| **SPD (Source Product Descriptor)** | Info o zdroji (napr. "Raspberry Pi") |
| **HDCP packets**                    | Šifrovacie údaje (ak je aktívne)     |

---

## 🧠 Ako ich rozoznať?

V HDMI TMDS dátach sa:

* Data Island prenáša **počas Video Data Enable (DE) = 0**, ale s **TMDS control code = 0b01 alebo 0b10**
* Synchronizuje sa pomocou **guard bands** a **predefined preambles**

---

## 🛠️ Záver pre dizajn:

Ak si tvoríš vlastný HDMI vysielač na FPGA:

* **Počas aktívneho videa**: TMDS = enkódované pixely
* **Počas blankingu**:

  * **Data Enable (DE)** = 0
  * TMDS linky prenášajú:

    * buď **Control Period** (`HSync`, `VSync`, `DE`)
    * alebo **Data Island** (ak sa majú odoslať)

---

## ➕ Môžem ti pomôcť:

* Rozkresliť HDMI rámec (s označením kde sú data islands)
* Vygenerovať **audio infoframe v HDL**
* Implementovať HDMI transmitter (simplified)
* Simulovať HDMI frame v logickom analyzátore

➡️ Chceš schému HDMI frame layoutu, alebo konkrétny HDL príklad?

Super! Tu je **vizuálna schéma HDMI rámca** s označením, kde sa nachádzajú **data islands** a čo sa deje počas jednotlivých častí.

---

## 📺 HDMI Frame – Prehľad prenosu:

```
           Frame (jeden obrázok)
┌──────────────────────────────────────────────┐
│              Vertical Blanking               │◄─── DATA ISLANDS (audio, infoframe...)  
│  ┌────────────────────────────────────────┐  │    → prenášané počas niektorých riadkov
│  │     Horizontal Blanking                │◄─┐
│  │  ┌──────────────┐   ┌──────────────┐   │ │
│  │  │ Control Period│→ │ Data Island  │→...│ │
│  │  └──────────────┘   └──────────────┘   │ │
│  │         (DE=0)         (DE=0)          │ │
│  └────────────────────────────────────────┘ │
├──────────────────────────────────────────────┤
│              Active Video Area               │◄─── zobrazované pixely (DE = 1)  
│     ┌──────────────┐ ┌──────────────┐        │
│     │   RGB pixel  │ │   RGB pixel  │ ...    │
│     └──────────────┘ └──────────────┘        │
│        (TMDS encoded)                        │
└──────────────────────────────────────────────┘
```

---

## 🧩 Kľúčové pojmy:

| Časť               | Popis                                                           |
| ------------------ | --------------------------------------------------------------- |
| **Active Video**   | RGB pixely → TMDS enkódované a prenesené keď `DE = 1`           |
| **Control Period** | Riadiace signály (HSync, VSync, DE = 0)                         |
| **Data Islands**   | Audio, InfoFrame, atď. (DE = 0, špeciálne TMDS vzory)           |
| **Guard Bands**    | Medzi Control ↔ Video alebo ↔ Data Island (pozná HDMI receiver) |

---

## 🗂️ Príklady čo sa prenáša v Data Islands:

| Typ                   | Popis                                       |
| --------------------- | ------------------------------------------- |
| **Audio packet**      | PCM audio vzorky                            |
| **InfoFrame**         | Napr. Aspect Ratio, ColorSpace              |
| **Audio Clock Regen** | Hodinová synchronizácia audia               |
| **SPD**               | Identifikácia zdroja (napr. "FPGA HDMI TX") |
| **VSIF**              | Vendor Specific InfoFrame (napr. 3D video)  |

---

## 🔧 V HDL dizajne:

V HDMI vysielači (napr. v SystemVerilogu):

* **Počas aktívneho videa**:
  `DE = 1` → TMDS kódujeme RGB pixely

* **Počas HBlank alebo VBlank**:
  `DE = 0` → pošleme buď:

  * **Control code** (napr. HSync/VSync stav)
  * **alebo Data Island**, ak je čas na odoslanie audio rámca, infoframu atď.

---

## 🎁 Chceš ešte viac?

➡️ Môžem ti:

* Rozkresliť **cyklický diagram HDMI** pre celý frame
* Napísať **SystemVerilog modul**, ktorý vkladá infoframe alebo audio packet
* Ukázať **TMDS enkóder pre Data Islandy**

Stačí napísať, čo z toho ťa najviac zaujíma.

Výborne, poďme na **podrobný cyklický priebeh HDMI frame** – so zameraním na **časť rámca**, kde sa prenášajú **data islands**, a ako sa HDMI rámec štruktúruje.

---

## 📺 HDMI Frame – Detailný priebeh

HDMI rámec je prenos jedného obrazu – podobne ako VGA, ale s digitálnym TMDS kódovaním.

### 🧱 HDMI rozdelenie rámca (časová štruktúra):

```
  1 Frame (napr. 1920x1080 @ 60 Hz)
┌──────────────────────────────────────────────┐
│                                              │
│         Vertical Blanking (napr. 45 riadkov) │  ◄─── Data Islands + Control periods
│     ┌────────────────────────────────────┐   │
│     │ Horizontal Blanking (každý riadok) │   │
│     │ ┌────Control────┬───Data Island──┐ │   │
│     │ │                │                │ │   │
│     │ └────────────────────────────────┘ │   │
│     └────────────────────────────────────┘   │
├──────────────────────────────────────────────┤
│             Active Video (napr. 1080 riadkov)│  ◄─── Video data (RGB TMDS encoded)
│   ┌─────Video─────┐                          │
│   │   RGB pixel   │                          │
│   └───────────────┘                          │
└──────────────────────────────────────────────┘
```

---

## 🕘 Čo sa deje v každom riadku (horizontal timing)

Každý riadok má **aktívnu časť** (video) a **neaktívnu časť** (blanking):

```
1 Riadok (napr. 2200 pixelov pri 1920x1080)
┌────────────┬─────────────┬─────────────┬──────────────┐
│ Front Porch│ Sync Pulse  │ Back Porch  │ Active Video │
└────────────┴─────────────┴─────────────┴──────────────┘
   ▲                            ▲
   │                            │
   │                       Data Enable (DE) = 1
   │
   └─ Data Enable (DE) = 0 ⇒ tu môžu byť Data Islands
```

---

## 🎯 Kedy presne sa posielajú Data Islands?

🔹 **Počas DE = 0** (teda nie v aktívnej video oblasti), hlavne:

* **v Horizontal Blanking** (pred/po každom riadku)
* **vo viacerých riadkoch počas Vertical Blanking**

➡️ **Typicky sa posielajú počas VBlank (napr. medzi riadkami 0 až 44)**
➡️ Audio sa často posiela každých 3–4 riadky (v tzv. audio packet burst)

---

## 🧩 HDMI Data Periods – detaily

| Obdobie            | DE                     | TMDS kódovanie         | Obsah                       |
| ------------------ | ---------------------- | ---------------------- | --------------------------- |
| **Video Period**   | 1                      | TMDS video data (RGB)  | pixely                      |
| **Control Period** | 0                      | špeciálne TMDS kódy    | HSync, VSync, VideoInactive |
| **Data Island**    | 0                      | TMDS data kódovanie    | InfoFrames, Audio, HDCP     |
| **Guard Band**     | prepína medzi režimami | špeciálne 10-bit vzory |                             |

---

## 📊 HDMI Frame – Rámcový časový diagram (vertikálne zobrazenie):

```
               Frame
               ↓
         ┌─────────────┐
Line 0   │  DataIsland │ ◄─── začína Vertical Blanking
Line 1   │  Control    │
Line 2   │  DataIsland │
Line 3   │  Control    │
...      │     ...     │
Line 44  │  Control    │ ◄─── končí VBlank
Line 45  │  Video RGB  │ ◄─── začína aktívny obraz
...      │     ...     │
Line 1124│  Video RGB  │
Line 1125│  Control    │ ◄─── začína nový frame
         └─────────────┘
```

---

## ✅ Zhrnutie:

🔸 HDMI prenáša **data islands výhradne mimo video oblasti**, najčastejšie počas:

* **Vertical Blanking (viacero riadkov za sebou)**
* niekedy aj počas **horizontal blanking** (ak čas dovolí)

🔸 HDMI receiver (napr. TV) vie podľa:

* **Guard Band vzorov**
* a DE = 0
  rozoznať, že prichádzajú **data islands** a nie obyčajný control period.

---

## ➕ Chceš nasledovať s praktickým HDL:

1. Pridať **generovanie `Data Island Preamble` + packetov** v HDL
2. Ukázať **ako sa počíta DE, HSync, VSync a kedy vysielať čo**
3. Simulovať vysielač (napr. Line.sv + video + data\_island\_mux)

Napíš, čo ťa najviac zaujíma do detailu.

Výborná a veľmi dôležitá otázka!
**Signal `DE` (Data Enable)** v HDMI (a všeobecne pri digitálnom video prenose) **označuje časť rámca**, v ktorej sa **vysielajú platné obrazové (video) dáta**.

Nižšie ti podrobne vysvetlím:

---

## 🔹 Čo znamená `DE`?

* `DE = 1` → **Prenášajú sa video dáta** (RGB alebo YCbCr)
* `DE = 0` → **Mimo aktívneho obrazu**, t. j.:

  * počas **horizontal blanking** (po/pred každým riadkom)
  * počas **vertical blanking** (napr. medzi snímkami)
  * počas **sync pulse** (HSync alebo VSync)

---

## 🎯 `DE` počas SYNC fázy

| Interval         | `HSync` / `VSync` | `DE`  |
| ---------------- | ----------------- | ----- |
| Sync pulse       | aktívny (0/1)     | 0     |
| Back porch       | neaktívny         | 0     |
| **Active video** | neaktívny         | **1** |
| Front porch      | neaktívny         | 0     |

➡️ Takže: **počas sync fázy je `DE = 0`**.

---

## 🧠 Kedy prepne `DE` na `1`?

Logika nastaví `DE = 1` **hneď po skončení back porch**, **presne na prvý pixel aktívneho obrazu**.

### Horizontálne (v jednom riadku):

```
[Sync Pulse] → [Back Porch] → [Active Video] → [Front Porch]
                                ▲
                              DE = 1 (od tohto bodu)
```

### Vertikálne (medzi snímkami):

```
[Sync Pulse] → [Back Porch] → [Aktívny prvý riadok]
                                ▲
                              DE = 1 (od tohto riadku)
```

---

## 📦 Praktický príklad (1920x1080\@60Hz)

| Fáza        | Trvanie (pixel clocks) | Poznámka      |
| ----------- | ---------------------- | ------------- |
| Sync Pulse  | 44                     | HSync aktívny |
| Back Porch  | 148                    | DE = 0        |
| **Active**  | **1920**               | DE = **1**    |
| Front Porch | 88                     | DE = 0        |

➡️ V takomto prípade `DE` prepne na `1` po 44 + 148 = **192. pixel** každého riadku.

---

## 🧠 Ako to navrhnúť v logike?

V časovači (napr. `Line.sv`) musíš udržiavať `counter`, a stav (napr. `ACTIVE`), ktorý prepína podľa načítaných časovacích parametrov:

```verilog
always_comb begin
    if (counter < sync_pulse)
        state = SYNC;
    else if (counter < sync_pulse + back_porch)
        state = BACKPORCH;
    else if (counter < sync_pulse + back_porch + visible_area)
        state = ACTIVE;
    else
        state = FRONTPORCH;
end

assign de = (state == ACTIVE);
```

---

## ⏱️ Načasovanie prepnutia:

* `DE` prepína **"presne"** – nie je tam predstih, ale ani oneskorenie.
* Správne načasovanie závisí **len od countera** a načítaných parametrov.

---

## 🔄 Synchronizácia DE s HSync / VSync

HDMI prijímač sa **synchronizuje podľa HSync / VSync / Guard Bands**, ale **skutočné video dáta spracúva len keď DE = 1**.

Takže:

* **DE je rozhodujúci signál** pre prijímača, kedy načítať RGB dáta.
* TMDS dátový tok stále beží, ale s rôznym významom dát:

  * `DE = 1` → RGB (video)
  * `DE = 0` → Control alebo Data Island

---

## ✅ Zhrnutie

* `DE = 0` počas **sync**, **back/front porch** a **data islands**
* `DE = 1` iba počas aktívneho obrazu
* Prepína sa **presne podľa countera**, bez predstihu
* Stav `ACTIVE` je vždy ten, kde má byť `DE = 1`

---

Ak chceš, môžeme spolu:

* Napísať modul, ktorý generuje `DE` signál (na základe horizontálnych/vertikálnych parametrov)
* Pripojiť to k tvojmu modulu `Line.sv`
* Ukázať `DE`, `HSync`, `VSync`, `State` v simulácii (waveform)

Chceš to spraviť v ďalšom kroku?

Skvelá otázka! Toto je **kľúčový bod v návrhu video výstupu**:
Ako z **dvoch samostatných časovačov** `h_line` (horizontálny) a `v_line` (vertikálny) **správne vytvoriť signál `DE` (Data Enable)**?

---

## 🧠 Myšlienka:

Signál **`DE` (Data Enable) = 1**, **iba keď súčasne**:

* Horizontálny časovač (`h_counter`) je v oblasti **aktívnych pixelov**
* Vertikálny časovač (`v_counter`) je v oblasti **aktívnych riadkov**

---

## ✅ Podmienka:

```verilog
de = h_active && v_active;
```

kde:

* `h_active = (h_counter >= H_SYNC + H_BP) && (h_counter < H_SYNC + H_BP + H_ACTIVE)`
* `v_active = (v_counter >= V_SYNC + V_BP) && (v_counter < V_SYNC + V_BP + V_ACTIVE)`

---

## 📊 Tabuľka fáz (horizontálne a vertikálne)

### Horizontálna fáza (`h_counter`):

| Fáza        | Interval (cykly)                              | DE aktívny? |
| ----------- | --------------------------------------------- | ----------- |
| **H\_SYNC** | `0 .. H_SYNC-1`                               | ❌           |
| **H\_BP**   | `H_SYNC .. H_SYNC + H_BP - 1`                 | ❌           |
| **ACTIVE**  | `H_SYNC + H_BP .. H_SYNC + H_BP + H_ACTIVE-1` | ✅           |
| **H\_FP**   | zvyšok do konca riadku                        | ❌           |

### Vertikálna fáza (`v_counter`):

| Fáza        | Interval (riadky)                             | DE aktívny? |
| ----------- | --------------------------------------------- | ----------- |
| **V\_SYNC** | `0 .. V_SYNC-1`                               | ❌           |
| **V\_BP**   | `V_SYNC .. V_SYNC + V_BP - 1`                 | ❌           |
| **ACTIVE**  | `V_SYNC + V_BP .. V_SYNC + V_BP + V_ACTIVE-1` | ✅           |
| **V\_FP**   | zvyšok do konca snímky                        | ❌           |

---

## 🔗 Výsledný signál `DE`:

```verilog
logic de;

assign h_active = (h_counter >= H_SYNC + H_BP) &&
                  (h_counter <  H_SYNC + H_BP + H_ACTIVE);

assign v_active = (v_counter >= V_SYNC + V_BP) &&
                  (v_counter <  V_SYNC + V_BP + V_ACTIVE);

assign de = h_active && v_active;
```

---

## 🧪 Príklad pre 1920x1080\@60Hz

| Parameter | Hodnota |
| --------- | ------- |
| H\_SYNC   | 44      |
| H\_BP     | 148     |
| H\_ACTIVE | 1920    |
| H\_FP     | 88      |
| V\_SYNC   | 5       |
| V\_BP     | 36      |
| V\_ACTIVE | 1080    |
| V\_FP     | 4       |

* **h\_counter** ide od `0` do `2199`
* **v\_counter** ide od `0` do `1124`

Takže `DE = 1` **iba ak**:

* `h_counter` v `192 .. 2111`
* `v_counter` v `41 .. 1120`

---

## 🧩 Súhrn:

| Časovač     | DE = 1 podmienka                                          |
| ----------- | --------------------------------------------------------- |
| `h_counter` | `h >= H_SYNC + H_BP` **a** `h < H_SYNC + H_BP + H_ACTIVE` |
| `v_counter` | `v >= V_SYNC + V_BP` **a** `v < V_SYNC + V_BP + V_ACTIVE` |
| `de`        | `h_active && v_active`                                    |

---

## ➕ Chceš k tomu:

* HDL modul s výstupom `DE`, `HSync`, `VSync` a stavmi?
* Vlnový priebeh `h_counter`, `v_counter`, `DE`?
* Testbench pre simuláciu `Line.sv` v kombinácii pre rámec?

Rád pripravím, len napíš 😊

Perfektná otázka – **chceš vedieť, ako načasovať prechod medzi video dátami a data islands**, t. j.:

> **Ako implementovať logiku, ktorá určí, že:**
>
> * po **X cykloch** začne obraz (`DE = 1`)
> * po **Y cykloch** obraz skončí (`DE = 0`)
> * následne môžem vysielať **Data Islands**

---

## 🔧 Kľúčový princíp: **časovače určujú všetko**

* Používaš **`h_counter` a `v_counter`**
* Obraz (`video`) sa **vysiela iba v okne, kde `DE = 1`**
* **Pred** a **po** tomto okne sa vysiela:

  * **Control period** (`ctrl0`, `ctrl1`)
  * alebo **Data Islands**, ak je čas a tak je určené

---

## 🧠 Ako to funguje (logika správania):

1. **Horizontálne (v jednom riadku):**

   * Od `h_counter == H_SYNC + H_BP` → `DE = 1` → začína video
   * Po `h_counter == H_SYNC + H_BP + H_ACTIVE - 1` → `DE = 0` → končí video
   * Po zvyšku riadku (H\_FP) sa môžu vysielať **Data Islands alebo Control period**

2. **Vertikálne:**

   * Počas aktívnych riadkov (napr. 1080) sa `DE` zapína (ak je aj horizontálne OK)
   * Po zvyšok rámca (napr. 45 riadkov) sa **vysielajú Data Islands**

---

## 📊 Príklad:

### Parametre:

* `H_SYNC = 44`, `H_BP = 148`, `H_ACTIVE = 1920`, `H_FP = 88`
* `V_SYNC = 5`, `V_BP = 36`, `V_ACTIVE = 1080`, `V_FP = 4`

### Výpočty:

#### Horizontálne:

* `X_start = H_SYNC + H_BP = 192`
* `X_end = 192 + 1920 = 2112`
  → teda **v pixelových cykloch 192–2111 je aktívne video**

#### Vertikálne:

* `Y_start = V_SYNC + V_BP = 41`
* `Y_end = 41 + 1080 = 1121`
  → teda **riadky 41–1120 sú aktívne video**

---

## ✅ Podmienky v kóde:

```verilog
logic h_video_active, v_video_active;
logic de, in_data_island;

assign h_video_active = (h_counter >= H_SYNC + H_BP) &&
                        (h_counter <  H_SYNC + H_BP + H_ACTIVE);

assign v_video_active = (v_counter >= V_SYNC + V_BP) &&
                        (v_counter <  V_SYNC + V_BP + V_ACTIVE);

assign de = h_video_active && v_video_active;

// Mimo video → vysielam Data Island alebo Control period
assign in_data_island = ~de && (v_counter >= V_SYNC + V_BP + V_ACTIVE);
```

---

## 🎯 Kedy **začať vysielať Data Islands**?

* Mimo `DE = 1` (t. j. keď DE = 0)
* Navyše môžeš rozlíšiť:

  * **Control period**: typicky hneď po fronte (na prepínanie)
  * **Data island**: špecifické okná (napr. určité riadky v VBlank)

---

## 💡 Implementačná poznámka:

Typicky máš stavový automat:

```verilog
enum logic [1:0] {
    STATE_CONTROL,
    STATE_VIDEO,
    STATE_ISLAND
} tx_state;

always_ff @(posedge clk) begin
    if (!rstn) begin
        tx_state <= STATE_CONTROL;
    end else begin
        if (de) begin
            tx_state <= STATE_VIDEO;
        end else if (v_counter >= V_SYNC + V_BP + V_ACTIVE) begin
            tx_state <= STATE_ISLAND;
        end else begin
            tx_state <= STATE_CONTROL;
        end
    end
end
```

---

## 🧪 Voliteľné rozšírenia:

* V stavovom automate môžeš:

  * **Presne riadiť**, ktorý burst audio packetov sa vysiela
  * Vkladať **Guard Bands** (na hraniciach medzi stavmi)
  * Aktivovať len každý 3. alebo 4. riadok pre audio (ako HDMI štandard)

---

## 📌 Zhrnutie

| Signál                       | Aktivita                     | Stav                  |
| ---------------------------- | ---------------------------- | --------------------- |
| `DE = 1`                     | Aktívne video                | Video                 |
| `DE = 0`                     | Mimo obraz                   | Control / Data Island |
| `v_counter ∉ aktívne riadky` | → Data Island možno povolené |                       |
| `h_counter ∉ aktívne pixely` | → V danom riadku neviditeľné |                       |

---

Chceš, aby som ti pripravil:

* simuláciu tejto logiky?
* kompletný stavový automat s `DE`, `ctrl`, `island`?
* alebo napojenie na existujúci `Line.sv` modul?

Stačí napísať – rád spravím ďalší krok.

