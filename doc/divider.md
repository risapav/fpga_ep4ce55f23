Tvoj modul `Divider` vytvára výstupný signál s **polovičnou frekvenciou** vstupného signálu `sig_in`, pomocou jednoduchého čítača. Funguje, ale existuje niekoľko aspektov, ktoré môžeš **vylepšiť** pre lepšiu syntetizovateľnosť, čitateľnosť a správne správanie vo **FPGA (napr. Quartus)**.

---

## 🔍 **Analýza pôvodného kódu**

### ✅ Výhody:

* Jednoduchý návrh, ktorý vytvára výstup s nižšou frekvenciou.
* Parametrizovaný pomocou `DIVISOR`, čo je dobre.

### ❗ Nedostatky:

1. **Chýba reset** – čítač má inicializačnú hodnotu, ale bez `reset` signálu to nie je zaručené v skutočnom FPGA.
2. **Podmienka v `always` bloku je neefektívna:** najprv sa čítač zvýši a až potom sa resetuje – čo môže narušiť presné delenie.
3. **Zvláštne správanie pre `DIVISOR = 1` alebo nepárne čísla.**
4. **Výstup `sig_out` je generovaný ako kombinácia** (neregistrovaný), čo môže viesť k glitchom.
5. **Používa sa `sig_in` ako hodinový signál**, čo je veľmi **neštandardné** a **nevhodné** pre syntézu v FPGA. Používať ako hodiny treba signál `clk`.

---

## ✅ **Odporúčané vylepšenia**

* Použi štandardný hodinový vstup (`clk`), nie ľubovoľný signál.
* Pridaj **synchronný reset**.
* Použi registrovaný výstup.
* Vylepši čítač a logiku delenia frekvencie tak, aby presne delila vstupnú frekvenciu a bola bezpečne syntetizovateľná.

---

## 🧾 **Vylepšená verzia v SystemVerilog:**

```systemverilog
module Divider #(
    parameter integer DIVISOR = 50_000_000  // musí byť aspoň 2
)(
    input  logic clk,
    input  logic rst,         // aktívne vysoký synchrónny reset
    output logic sig_out      // výstup: delič frekvencie
);

    // Overenie parametra pri syntéze
    initial begin
        if (DIVISOR < 2)
            $fatal("DIVISOR must be >= 2");
    end

    localparam COUNTER_WIDTH = $clog2(DIVISOR);

    logic [COUNTER_WIDTH-1:0] counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            counter  <= 0;
            sig_out  <= 0;
        end else begin
            if (counter == DIVISOR - 1) begin
                counter <= 0;
                sig_out <= ~sig_out;
            end else begin
                counter <= counter + 1;
            end
        end
    end

endmodule
```

---

## 📘 **Ako funguje:**

* Každý `DIVISOR` počet taktov výstup `sig_out` zmení svoj stav (`toggle`).
* Výsledkom je **výstup s frekvenciou `clk / (2 * DIVISOR)`**.
* Napr. ak `DIVISOR = 50_000_000` a `clk = 100 MHz`, výstup bude mať frekvenciu **1 Hz**.

---

## 🧠 **Dôležité poznámky pre FPGA:**

* Tento spôsob je plne **synchronný** a vhodný pre syntézu v **Intel Quartus**, **Xilinx Vivado**, atď.
* Používanie `sig_in` ako hodinového vstupu (v pôvodnom kóde) sa **neodporúča**, lebo neumožňuje použitie hodín s globálnym routovaním a znižuje spoľahlivosť.

---

Ak chceš:

* generovať viacero výstupov s rôznymi deleniami naraz,
* alebo vytvoriť **generátor PWM**,
* či použiť výstup na **blikajúcu LED**,

📩 povedz a pripravím ti rozšírený modul podľa potreby.
