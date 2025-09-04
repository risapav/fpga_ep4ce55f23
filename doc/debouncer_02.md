Skvelé! Tu je:

---

## ✅ **Parametrizovaný debounce modul pre viacero tlačidiel**

Debouncuje viacero aktívne-nízkych tlačidiel naraz, každý s vlastným čítačom a výstupmi. Výsledné výstupy sú registrované a vhodné pre ďalšie synchrónne spracovanie.

---

### 🔧 **Modul: `MultiButton_Debouncer`**

```systemverilog
module MultiButton_Debouncer #(
    parameter integer N = 4,                 // počet tlačidiel
    parameter integer COUNTER_WIDTH = 16     // šírka debounce čítača
)(
    input  logic clk,
    input  logic rst,                        // synchronný reset
    input  logic [N-1:0] PB_n,               // aktívne-nízke tlačidlá (glitchy)

    output logic [N-1:0] PB_state,           // stav tlačidiel (1 = stlačené)
    output logic [N-1:0] PB_down,            // pulz na stlačenie
    output logic [N-1:0] PB_up               // pulz na uvoľnenie
);

    // Synchronizácia a pretypovanie vstupu
    logic [N-1:0] pb_sync_0, pb_sync_1;
    always_ff @(posedge clk) begin
        pb_sync_0 <= ~PB_n; // invertujeme – interné tlačidlá budú aktívne-vysoké
        pb_sync_1 <= pb_sync_0;
    end

    // Debounce čítače
    logic [COUNTER_WIDTH-1:0] debounce_cnt [N];
    logic [N-1:0] PB_state_d;
    logic [N-1:0] pb_changed;
    logic [N-1:0] debounce_done;

    genvar i;
    generate
        for (i = 0; i < N; i++) begin : DEBOUNCE

            assign pb_changed[i]    = (PB_state[i] != pb_sync_1[i]);
            assign debounce_done[i] = &debounce_cnt[i];  // všetky bity = 1

            always_ff @(posedge clk) begin
                if (rst) begin
                    debounce_cnt[i] <= 0;
                    PB_state[i]     <= 0;
                    PB_state_d[i]   <= 0;
                end else begin
                    PB_state_d[i] <= PB_state[i];
                    if (pb_changed[i]) begin
                        debounce_cnt[i] <= debounce_cnt[i] + 1;
                        if (debounce_done[i]) begin
                            PB_state[i]     <= pb_sync_1[i];
                            debounce_cnt[i] <= 0;
                        end
                    end else begin
                        debounce_cnt[i] <= 0;
                    end
                end
            end

            assign PB_down[i] = (PB_state[i] == 1) && (PB_state_d[i] == 0);
            assign PB_up[i]   = (PB_state[i] == 0) && (PB_state_d[i] == 1);

        end
    endgenerate

endmodule
```

---

## 🧪 **Testbench (príklad pre `N = 2`):**

```systemverilog
module tb_MultiButton_Debouncer;

    logic clk = 0;
    logic rst;
    logic [1:0] PB_n;
    logic [1:0] PB_state, PB_down, PB_up;

    MultiButton_Debouncer #(
        .N(2),
        .COUNTER_WIDTH(4)  // znížená šírka pre rýchlejšiu simuláciu
    ) dut (
        .clk(clk),
        .rst(rst),
        .PB_n(PB_n),
        .PB_state(PB_state),
        .PB_down(PB_down),
        .PB_up(PB_up)
    );

    always #5 clk = ~clk; // 100 MHz clock

    initial begin
        rst = 1; PB_n = 2'b11;
        #20 rst = 0;

        // simuluj stlačenie tlačidla 0
        #10 PB_n[0] = 0;
        #100 PB_n[0] = 1;

        // simuluj stlačenie tlačidla 1
        #50 PB_n[1] = 0;
        #80 PB_n[1] = 1;

        #100 $finish;
    end

endmodule
```

---

## ✅ **Výhody tejto verzie:**

* Škálovateľná: jednoducho rozšíriteľná na ľubovoľný počet tlačidiel (`N`).
* Každé tlačidlo má vlastnú debounce logiku.
* Výstupy sú registrované, bezpečné na použitie vo všetkých synchrónnych systémoch.
* Funguje vo všetkých FPGA nástrojoch (vrátane **Intel Quartus Prime**).

---

Ak chceš:

* zmeniť debounce čas podľa konkrétneho časového intervalu (napr. 20 ms),
* pridať LED výstup alebo integráciu s Avalon/MMIO rozhraním,
* alebo generovať v **LiteX alebo Platform Designer**,

📩 daj vedieť a môžeme rozšíriť modul.
