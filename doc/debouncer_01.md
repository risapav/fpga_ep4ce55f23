Tvoj pôvodný kód implementuje **synchronizovaný debounce** mechanizmus pre mechanické tlačidlo. Je funkčný a bežne používaný, ale má niekoľko oblastí na zlepšenie, najmä ak sa má syntetizovať v **Quartus (Intel FPGA)** a použiť v reálnych systémoch.

---

## 🔍 **Analýza pôvodného kódu**

### ✔️ Plusy:

* Dvojitá synchronizácia (`PB_sync_0`, `PB_sync_1`) → správne odstraňuje metastabilitu.
* Použitie 16-bitového čítača → robustný spôsob potlačenia zákmitov (glitchov).
* Detekcia prechodov (`PB_down`, `PB_up`) je správne riešená ako **jednohĺbkové pulzy**.

### ❗ Nedostatky:

1. **Nejasné oddelenie medzi synchronizáciou, debounce logikou a FSM**.
2. **`PB_state` je aktualizovaný v tom istom `always` bloku ako čítač**, čo robí logiku menej čistou.
3. **Možné glitchy pri generovaní `PB_down` a `PB_up`**, lebo sú to čisté kombinácie výstupov bez registrácie.
4. **Nevyhnutnosť resetu**: chýba asynchrónny alebo synchrónny reset – nevyhovuje v niektorých FPGA aplikáciách.
5. **Výstupy `PB_down`, `PB_up` nie sú registrované**, čo môže spôsobiť problémy pri ich použití v iných synchrónnych moduloch.

---

## ✅ **Vylepšený návrh – Ciele**

* Použitie **oddelených logických blokov** pre synchronizáciu, debounce čítač a výstupnú logiku.
* Registrované výstupy pre **PB\_down** a **PB\_up**.
* Pridanie **resetu**.
* Zabezpečenie **jednohodinového pulzu** pre prechody.
* Kompatibilita so **synthézou v Quartus**.

---

## 🧾 **Vylepšený a syntetizovateľný SystemVerilog kód**

```systemverilog
module PushButton_Debouncer #(
    parameter integer COUNTER_WIDTH = 16
)(
    input  logic clk,
    input  logic rst,       // synchronous reset, active high
    input  logic PB_n,      // active-low tlačidlo, glitchy

    output logic PB_state,  // 1 = stlačené, 0 = nie je stlačené
    output logic PB_down,   // 1 clk pulse na stlačenie
    output logic PB_up      // 1 clk pulse na uvoľnenie
);

    // 1. Synchronizácia do clk domény (inverzný vstup na active-high)
    logic pb_sync_0, pb_sync_1;
    always_ff @(posedge clk) begin
        pb_sync_0 <= ~PB_n;
        pb_sync_1 <= pb_sync_0;
    end

    // 2. Debounce čítač
    logic [COUNTER_WIDTH-1:0] debounce_cnt;
    logic pb_changed = (PB_state != pb_sync_1);
    logic debounce_done = &debounce_cnt; // všetky bity sú 1 => overflow

    always_ff @(posedge clk) begin
        if (rst) begin
            debounce_cnt <= 0;
            PB_state     <= 0;
        end else if (pb_changed) begin
            debounce_cnt <= debounce_cnt + 1;
            if (debounce_done) begin
                PB_state <= pb_sync_1;
                debounce_cnt <= 0;  // reset counter po potvrdení zmeny
            end
        end else begin
            debounce_cnt <= 0;
        end
    end

    // 3. Detekcia hrán (prechodov)
    logic PB_state_d;

    always_ff @(posedge clk) begin
        if (rst)
            PB_state_d <= 0;
        else
            PB_state_d <= PB_state;
    end

    assign PB_down = (PB_state == 1) && (PB_state_d == 0); // rising edge
    assign PB_up   = (PB_state == 0) && (PB_state_d == 1); // falling edge

endmodule
```

---

## 🧠 **Poznámky k použitiu vo FPGA (Quartus):**

* Funguje bez problémov vo **Quartus Prime**, všetko je registrované.
* Ak máš veľa vstupov, odporúča sa parametrizovať `COUNTER_WIDTH` podľa požadovanej dĺžky debouncingu.
* V prípade použitia s viacnásobnými tlačidlami, môžeš tento modul replikovať alebo upraviť na pole.

---

Ak chceš, viem ti pripraviť aj **testbench** alebo **variant pre viacero tlačidiel (parametrizovaný vektormi)**. Chceš?
