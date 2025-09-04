Skvelé! Začnime postupne rozširovať. Tu je **plán**, ako môžeme modul a testbench ďalej rozvíjať – krok za krokom:

---

## 🔄 **Krok 1: Zobrazenie `resetn_sync` vo waveforme**

Pridáme do testbenchu `dump` pre simuláciu v **ModelSim**, **Questa**, **GTKWave** alebo inom nástroji:

### ✅ Pridaj do testbenchu (`ResetController_tb`) sekciu pre wave dump:

```systemverilog
    initial begin
        $dumpfile("reset_controller_tb.vcd");
        $dumpvars(0, ResetController_tb);
    end
```

👉 Umiestni to na začiatok `initial begin` (pred resetom).

> Týmto vytvoríš VCD súbor, ktorý si vieš zobraziť v GTKWAVE alebo inom simulátore.

---

## 🔄 **Krok 2: Časovanie výstupu `resetn_sync`**

Pridáme presné zmeranie, koľko takty trvá, kým sa `resetn_sync` uvoľní po aktivovaní `pll_locked` a `RESET_N`.

### ✅ Pridaj meranie oneskorenia synchronizácie:

```systemverilog
    time t_start [N_DOMAINS-1:0];
    time t_end   [N_DOMAINS-1:0];

    always_ff @(posedge clk[0]) begin
        if (resetn_sync[0] === 0 && global_resetn_async === 1)
            t_start[0] = $time;

        if (resetn_sync[0] === 1 && t_start[0] > 0)
            t_end[0] = $time;
    end
```

A po `#200;` v stimulus bloku môžeš zobraziť výsledok:

```systemverilog
$display("Reset sync delay (clk0): %0t ns", t_end[0] - t_start[0]);
```

---

## 🔄 **Krok 3: Rozšírenie na reálne periférie (napr. VGA modul)**

Keď budeme mať synchronizované resety, môžeme otestovať, ako sa správajú **skutočné moduly** (napr. VGA, SDRAM), keď dostanú `resetn_sync` namiesto globálneho `RESET_N`.

➡️ Napr. v `top.sv` zameníš:

```systemverilog
.rstn (pixel_rstn_sync)
```

---

## 🔄 **Krok 4: Automatizovaný test pre viac clock domén**

Vytvoríme `for` slučku, ktorá bude automaticky sledovať a porovnávať oneskorenie resetu pre všetky domény.

---

## 🔄 Krok 5: Coverage, assertions a formal checky

Môžeme pridať:

* SystemVerilog `assert` na overenie, že resetn\_sync nikdy neskočí z `1` na `0`, pokiaľ `resetn_async` je stále aktívny
* Coverage blocky

---

### Chceš teraz pokračovať s **Krokom 1** a spraviť výstup do `VCD` / waveformu? Alebo skočíme rovno na **Krok 2** (časovanie oneskorenia synchronizácie)?
