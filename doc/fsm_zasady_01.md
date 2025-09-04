Pri písaní **FSM (Finite State Machine – konečný stavový automat)** v **SystemVerilogu** je dôležité dodržiavať určité zásady, ktoré zlepšujú čitateľnosť, udržiavateľnosť a syntézu dizajnu. Tiež je dôležité vedieť, ako správne rozdeliť **ostrovčeky logiky (logic islands)**, čiže rozloženie rôznych častí logiky FSM do samostatných blokov. Tu sú kľúčové zásady:

---

### ✅ **Zásady pri písaní FSM v SystemVerilogu**

#### 1. **Rozdelenie FSM na tri samostatné bloky (Three-process FSM model)**

Veľmi často používaný a odporúčaný prístup:

* **1. Stavový register (state register)**

  ```systemverilog
  always_ff @(posedge clk or posedge reset) begin
      if (reset)
          current_state <= IDLE;
      else
          current_state <= next_state;
  end
  ```

* **2. Kombinačná logika pre výpočet `next_state`**

  ```systemverilog
  always_comb begin
      case (current_state)
          IDLE: if (start) next_state = WORK;
                else next_state = IDLE;
          WORK: if (done) next_state = DONE;
                else next_state = WORK;
          DONE: next_state = IDLE;
          default: next_state = IDLE;
      endcase
  end
  ```

* **3. Výstupná logika (output logic)** – môže byť:

  * **Mooreov automat**: výstupy závisia len od stavu
  * **Mealyho automat**: výstupy závisia od stavu a vstupov

  ```systemverilog
  always_comb begin
      case (current_state)
          IDLE: out_signal = 0;
          WORK: out_signal = 1;
          DONE: out_signal = 0;
          default: out_signal = 0;
      endcase
  end
  ```

---

#### 2. **Používaj `enum logic` pre stavové premenné**

* Zlepšuje čitateľnosť a pomáha nástrojom na syntézu a debugovanie.

  ```systemverilog
  typedef enum logic [1:0] {
      IDLE, WORK, DONE
  } state_t;

  state_t current_state, next_state;
  ```

---

#### 3. **Inicializácia v `reset` vetve**

* Vždy definuj, čo sa má stať pri resete – buď synchronnom alebo asynchrónnom.

---

#### 4. **Neprekrývaj kombinačnú a sekvenčnú logiku**

* Vyhni sa písaniu všetkého v jednom bloku (`always_comb` + `always_ff` by mali byť oddelené).
* Znižuje to šancu na nepredvídateľné správanie alebo latch-e.

---

#### 5. **Používaj `default` prípady vo `case` vetvách**

* Zabezpečíš tým, že `next_state` alebo výstup bude mať vždy definovanú hodnotu.

---

#### 6. **Vyhni sa zložitej logike vo `next_state` bloku**

* Ak je podmienková logika zložitá, extrahuj ju mimo hlavný FSM do samostatného kombinačného bloku (ostrovček logiky).

---

### 🧩 Rozdelenie ostrovčekov logiky

**Ostrovčeky logiky (logic islands)** sú samostatné časti kombinačnej alebo sekvenčnej logiky, ktoré môžu byť napr.:

* Dekodéry vstupov
* Generátory výstupov
* Čítače, časovače, masky
* FSM s jasne oddelenými sekciami (napr. kontrolná a výpočtová časť)

**Zásady pre ich rozdelenie:**

* **Závislosť:** Ostrovčeky by mali byť čo najmenej závislé od seba.
* **Čitateľnosť:** Každý ostrovček by mal mať jasne definovanú zodpovednosť.
* **Znovupoužiteľnosť:** Oddelenie logiky uľahčuje znovupoužitie častí v iných návrhoch.
* **Testovateľnosť:** Uľahčuje testovanie jednotiek v simulácii.
* **Syntéza:** Minimalizuje problém s timingom a zjednodušuje optimalizáciu pre FPGA/ASIC.

---

### ✳️ Príklad dobre rozdeleného FSM modulu:

```systemverilog
module fsm_controller (
    input logic clk, reset, start, done,
    output logic busy
);

    typedef enum logic [1:0] {IDLE, WORK, DONE} state_t;
    state_t current_state, next_state;

    // 1. Stavový register
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // 2. Next-state logic
    always_comb begin
        unique case (current_state)
            IDLE:   next_state = (start) ? WORK : IDLE;
            WORK:   next_state = (done) ? DONE : WORK;
            DONE:   next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // 3. Výstupná logika
    assign busy = (current_state == WORK);

endmodule
```

---

Ak chceš, môžem ti vytvoriť **šablónu FSM** pre tvoj konkrétny projekt – stačí povedať, čo má robiť.
