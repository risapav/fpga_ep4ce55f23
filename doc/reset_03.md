Výborne! To je už skutočný návrhový scenár.

Keď máš viacero **clock domén** (napr. `pixel_clk`, `axi_clk`, `sdram_clk`) a **asynchrónny globálny reset (napr. tlačidlo)** spolu s výstupom z **PLL (`pll_locked`)**, je veľmi dôležité správne synchronizovať reset pre **každú doménu osobitne**.

---

## ✅ **Cieľ:**

Pre každú clock doménu vytvoriť spoľahlivý a **synchrónny aktívny LOW reset** (`*_rstn_sync`) kombináciou:

* **externého resetu (`RESET_N`)** – aktívny LOW, globálny,
* **signálu `pll_locked`** – aktívny HIGH, od PLL, tiež globálny,
* a synchronizovať výsledok **do každej clock domény osobitne**.

---

## 🧠 **Zhrnutie stratégie**

Pre každú doménu:

```text
resetn_async = RESET_N && pll_locked;
→ synchronizuj cez ResetSync do každej domény zvlášť
→ výstup: pixel_rstn_sync, axi_rstn_sync, sdram_rstn_sync
```

---

## 🧩 Príklad implementácie (v `top.sv` alebo `reset_ctrl.sv`)

```systemverilog
// Výsledný kombinovaný asynchrónny reset, aktívny LOW
logic global_resetn_async;
assign global_resetn_async = RESET_N & pll_locked;

// Výstupy pre každú clock doménu (aktívne LOW, synchronizované)
logic pixel_rstn_sync;
logic axi_rstn_sync;
logic sdram_rstn_sync;

// Synchronizátor pre pixel_clk
ResetSync #(.N_STAGES(2)) pixel_reset_sync_inst (
    .clk           (pixel_clk),
    .resetn_async  (global_resetn_async),
    .resetn_sync   (pixel_rstn_sync)
);

// Synchronizátor pre axi_clk
ResetSync #(.N_STAGES(2)) axi_reset_sync_inst (
    .clk           (axi_clk),
    .resetn_async  (global_resetn_async),
    .resetn_sync   (axi_rstn_sync)
);

// Synchronizátor pre sdram_clk
ResetSync #(.N_STAGES(2)) sdram_reset_sync_inst (
    .clk           (sdram_clk),
    .resetn_async  (global_resetn_async),
    .resetn_sync   (sdram_rstn_sync)
);
```

---

## 📊 **Vizualizácia**

```
                 +-------------+
 RESET_N ------> |             |
                 |             |
 pll_locked ---->+  AND gate   +--> global_resetn_async
                 |             |
                 +-------------+
                         |
                         +--------------------------+
                         |                          |
                 +---------------+         +----------------+
                 | ResetSync     |         | ResetSync      |
                 | clk=pixel_clk |         | clk=axi_clk    |
                 +---------------+         +----------------+
                         |                          |
             pixel_rstn_sync           axi_rstn_sync (aktívne LOW)
```

---

## 🛡️ **Prečo to funguje spoľahlivo?**

* Asynchrónny globálny reset sa najprv vytvorí kombináciou signálov.
* Potom sa **každý reset synchronizuje osobitne** pre každú doménu.
* Vylúči sa metastabilita a dosiahne sa **deterministické resetovanie systému**.

---

## ✍️ Použitie v každej clock doméne

```systemverilog
always_ff @(posedge pixel_clk) begin
    if (!pixel_rstn_sync) begin
        // pixel_clk doména - reset stavov
    end else begin
        // normálna činnosť
    end
end
```

---

Ak chceš, môžem ti vytvoriť:

* modul `ResetController.sv`, ktorý spraví všetky 3 synchronizácie naraz,
* alebo aj jednotný testbench na overenie funkcie pre všetky domény.

Zaujíma ťa takýto `ResetController` modul?
