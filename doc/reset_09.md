Jasné, ukážem ti oboje — príklady pre synchrónny aktívne nízky reset (`reset_n`) aj aktívne vysoký reset (`reset`), plus krátky pohľad, kedy ktorý typ použiť.

---

## 1️⃣ Synchrónny aktívne nízky reset (`reset_n`)

```systemverilog
module sync_reset_n_example (
    input  logic clk,
    input  logic reset_n,    // aktívne LOW
    output logic [3:0] counter
);

    always_ff @(posedge clk) begin
        if (!reset_n)          // reset aktívny, keď je 0
            counter <= 0;
        else
            counter <= counter + 1;
    end

endmodule
```

---

## 2️⃣ Synchrónny aktívne vysoký reset (`reset`)

```systemverilog
module sync_reset_example (
    input  logic clk,
    input  logic reset,      // aktívne HIGH
    output logic [3:0] counter
);

    always_ff @(posedge clk) begin
        if (reset)            // reset aktívny, keď je 1
            counter <= 0;
        else
            counter <= counter + 1;
    end

endmodule
```

---

## Kedy použiť ktorý?

| Kritérium                    | Aktívne nízky reset (`reset_n`)                                       | Aktívne vysoký reset (`reset`)                                |
| ---------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------- |
| **Hardvérová kompatibilita** | Typicky používaný s tlačidlami, externými resetmi (pull-up rezistory) | Častejšie používaný v softvérových alebo interných resetoch   |
| **Konvencia v dizajne**      | Štandardný v mnohých FPGA/ASIC návrhoch                               | Bežný v moderných dizajnoch, najmä pri softvérovom resetovaní |
| **Čitateľnosť kódu**         | Môže byť o niečo menej intuitívny (negácia v kóde)                    | Priamočiarejší, jednoduchšie čitateľný                        |
| **Synchronizácia**           | Rovnako jednoducho synchronizovateľný ako aktívny HIGH reset          | Rovnako jednoducho synchronizovateľný                         |

---

## Záver

* Obidve formy sa správne používajú, záleží na štýle dizajnu a požiadavkách systému.
* **Dôležité je byť konzistentný** v celom projekte — aby resety mali jednotný význam.
* Ak máš reset z externého tlačidla alebo signálu, často je to **aktívne nízky reset** (`reset_n`).
* Pre softvérové alebo interné resety je jednoduchšie používať **aktívne vysoký reset** (`reset`).

---

Ak chceš, môžem ti ukázať aj praktický príklad, ako to vyzerá pri **synchronizácii resetu** s `reset_n` aj s `reset`. Alebo chceš rovno príklad s asynchrónnym resetom?
