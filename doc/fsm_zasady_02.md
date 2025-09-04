Samozrejme, poďme sa detailne pozrieť na konečné stavové automaty (FSM - Finite State Machine) v SystemVerilogu. Je to kľúčový koncept v digitálnom dizajne.

V zásade poznáme dva základné typy FSM, od ktorých sa odvíja všetko ostatné:

1.  **Moore FSM**
2.  **Mealy FSM**

Hlavný a najdôležitejší rozdiel medzi nimi je v **spôsobe generovania výstupných signálov**, čo má priamy vplyv na ich časovanie a oneskorenie (latenciu).

-----

### 1\. Moore FSM

#### Princíp

V Moore automate závisia výstupy **iba od aktuálneho stavu** automatu. Nezávisia od aktuálnych hodnôt vstupných signálov.

**Konceptuálny diagram:**

```
            +----------------------+
Vstupy ---> |  Logika pre ďalší    | ---> |                   |
            |        stav          |      |   Stavový register| --+--> Logika pre výstup --> Výstupy
            | (kombinačná logika)  |      |   (sekvenčná)     |   |
            +----------------------+      +-------------------+   |
                  ^                             |                   |
                  |-----------------------------+-------------------+
                               (aktuálny stav)
```

Kľúčové je, že šípka k "Logike pre výstup" vedie iba zo "Stavového registra".

#### Implementácia v SystemVerilog

Typická implementácia používa 3 procesné bloky:

1.  `always_ff` pre registráciu stavu (prechod medzi stavmi na hrane hodín).
2.  `always_comb` pre logiku ďalšieho stavu.
3.  `always_comb` alebo `assign` pre logiku výstupov, ktorá závisí **iba od aktuálneho stavu**.

**Príklad:** Automat, ktorý deteguje sekvenciu `101` na vstupe `data_in`. Výstup `seq_found` bude `1`, keď je automat v stave `FOUND`.

```systemverilog
typedef enum logic [1:0] { IDLE, S1, S10, FOUND } state_t;

state_t current_state, next_state;

// 1. Blok: Registrácia stavu (sekvenčný)
always_ff @(posedge clk or negedge rstn) begin
    if (!rstn)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// 2. Blok: Logika pre ďalší stav (kombinačný)
always_comb begin
    next_state = current_state; // Štandardne zostáva v aktuálnom stave
    case (current_state)
        IDLE:  if (data_in) next_state = S1;
        S1:    if (!data_in) next_state = S10;
               else          next_state = S1; // Ak príde ďalšia 1, zostáva v S1
        S10:   if (data_in)  next_state = FOUND;
               else          next_state = IDLE;
        FOUND: // Po nájdení sa vráti do IDLE, aby hľadal znova
               if (data_in)  next_state = S1;
               else          next_state = IDLE;
    endcase
end

// 3. Blok: Logika pre výstup (závisí IBA od stavu)
assign seq_found = (current_state == FOUND);
```

#### Oneskorenie a časovanie výstupov (Kľúčový bod)

  * **Oneskorenie (Latencia):** Výstupy Moore automatu majú **vždy oneskorenie o 1 hodinový cyklus**. Keď vstupná podmienka spôsobí prechod do nového stavu (napr. `FOUND`), tento prechod sa udeje na nábežnú hranu hodín. Výstup sa zmení až *po tejto hrane*, pretože je generovaný z nového, už zaregistrovaného stavu.
  * **Stabilita:** Výstupy sú **úplne synchrónne a stabilné** počas celého hodinového cyklu. Zmenia sa iba po aktívnej hrane hodín a zostanú nemenné až do ďalšej hrany. To ich robí veľmi bezpečnými a predvídateľnými. Nehrozia tu žiadne prechodové javy (glitches).

-----

### 2\. Mealy FSM

#### Princíp

V Mealy automate závisia výstupy **od aktuálneho stavu A ZÁROVEŇ od aktuálnych vstupov**.

**Konceptuálny diagram:**

```
            +----------------------+
Vstupy -+-> |  Logika pre ďalší    | ---> |                   |
        |   |        stav          |      |   Stavový register| ---> (aktuálny stav) --+
        |   | (kombinačná logika)  |      |   (sekvenčná)     |                        |
        |   +----------------------+      +-------------------+                        |
        |         ^                             |                                      |
        |         |-----------------------------+--------------------------------------+
        |                                                                              |
        +----------------------------------------------------------------------------> Logika pre výstup --> Výstupy
```

Kľúčové je, že šípky k "Logike pre výstup" vedú zo "Stavového registra" **a aj** priamo zo "Vstupov".

#### Implementácia v SystemVerilog

Štruktúra je podobná, ale tretí blok sa zásadne líši.

**Príklad:** Ten istý detektor sekvencie `101`. Výstup `seq_found` bude `1`, ak je automat v stave `S10` A ZÁROVEŇ `data_in` je `1`.

```systemverilog
typedef enum logic [1:0] { IDLE, S1, S10 } state_t; // Často potrebuje menej stavov

state_t current_state, next_state;

// 1. a 2. Blok: Zostávajú rovnaké ako pri Moore FSM (tu zjednodušené)
always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) current_state <= IDLE;
    else       current_state <= next_state;
end

always_comb begin
    next_state = current_state;
    case (current_state)
        IDLE: if (data_in) next_state = S1;
        S1:   if (!data_in) next_state = S10;
              else          next_state = S1;
        S10:  if (data_in)  next_state = S1; // Po detekcii sa presunie ďalej
              else          next_state = IDLE;
    endcase
end

// 3. Blok: Logika pre výstup (závisí od stavu A VSTUPU)
assign seq_found = (current_state == S10 && data_in);
```

#### Oneskorenie a časovanie výstupov (Kľúčový bod)

  * **Oneskorenie (Latencia):** Mealy automat môže mať **nulové oneskorenie (0-cyklovú latenciu)**. Výstup reaguje na zmenu vstupu v rámci toho istého hodinového cyklu. Ak je automat v stave `S10` a vstup `data_in` sa zmení na `1`, výstup `seq_found` sa zmení na `1` okamžite (po krátkom kombinačnom oneskorení), bez čakania na ďalšiu hranu hodín.
  * **Stabilita:** Toto je hlavná nevýhoda. Keďže výstup je priamou kombinačnou funkciou vstupov, akékoľvek **prechodové javy (glitches) na vstupoch sa môžu priamo preniesť na výstupy**. Výstupy sú asynchrónne voči vstupom. Ak sa vstup zmení viackrát počas jedného cyklu, výstup ho bude kopírovať. To môže spôsobiť problémy v ďalších častiach dizajnu.

-----

### Porovnanie a zhrnutie

| Vlastnosť | Moore FSM | Mealy FSM |
| :--- | :--- | :--- |
| **Generovanie výstupu** | Závisí **iba od aktuálneho stavu**. | Závisí **od aktuálneho stavu a vstupov**. |
| **Latencia výstupu** | **Oneskorenie o 1 cyklus**. Výstup je plne registrovaný a synchrónny. | **Môže byť 0 cyklov**. Výstup je kombinačný a okamžitý. |
| **Stabilita výstupu** | **Vysoká.** Výstupy sú stabilné, bez prechodových javov (glitch-free). | **Nízka.** Výstupy môžu obsahovať prechodové javy, ak sú na vstupoch. |
| **Počet stavov** | Na rovnakú funkciu môže potrebovať viac stavov. | Často si vystačí s menším počtom stavov. |
| **Časovanie (Timing)** | Jednoduchšie na analýzu. Kritická cesta vedie od registra cez kombinačnú logiku späť do registra. | Zložitejšie na analýzu. Kritická cesta môže viesť od vstupu cez kombinačnú logiku až na výstup. |
| **Typické použitie** | Riadiace jednotky, generátory sekvencií, kde je dôležitá stabilita a predvídateľnosť. | Rýchle dátové cesty, detektory vzorov, kde je kľúčová okamžitá reakcia a vstupy sú zaručene stabilné. |

### Kedy ktorý použiť?

  * **Použite Moore FSM (predvolená voľba):**

      * Ak navrhujete riadiacu logiku.
      * Ak výstupy automatu riadia iné synchrónne moduly.
      * Ak potrebujete garantovane čisté a stabilné výstupy.
      * Bezpečnosť a jednoduchosť sú dôležitejšie ako absolútna rýchlosť.

  * **Použite Mealy FSM (špeciálne prípady):**

      * Ak je nulová latencia absolútne kritická.
      * Ak potrebujete reagovať na vstup v tom istom cykle, v ktorom prišiel.
      * Ak ste si istí, že vstupy do automatu sú stabilné a bez prechodových javov.

**Hybridný prístup:** V praxi sa často stretnete s hybridnými automatmi. Môžete mať Mealy automat, ktorého výstup následne zaregistrujete. Tým získate výhodu potenciálne menšieho počtu stavov (ako Mealy), ale vytvoríte bezpečný, synchrônny výstup (ako Moore), avšak s oneskorením 1 cyklu.
