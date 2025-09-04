Výborná otázka. Čiernobiela obrazovka po syntéze, hoci simulácia funguje, je veľmi častý problém pri práci s FPGA. Príčina takmer vždy súvisí s hodinami, resetmi alebo časovaním (timing), čo sú aspekty, ktoré simulácia často zjednodušuje.

Poďme si systematicky prejsť najpravdepodobnejšie príčiny, od najčastejších po menej obvyklé, v kontexte vášho projektu `top.sv`.

-----

### 1\. Problém s hodinami a resetmi (Najpravdepodobnejšia príčina)

Toto je najčastejší dôvod, prečo systém na hardvéri nefunguje. Váš systém má kľúčovú závislosť:

```systemverilog
assign rstn = RESET_N & locked;
```

Celý systém je v resete (aktívny v nízkej úrovni), kým nie sú splnené dve podmienky naraz:

1.  Externý reset `RESET_N` je neaktívny (v log. 1).
2.  PLL modul (`ClkPll`) signalizuje, že jeho výstupné hodiny sú stabilné (`locked` je v log. 1).

**Ak PLL nezamkne, celý váš dizajn zostane trvalo v resete.** Všetky registre budú mať hodnotu `0`, `TVALID` signály sa nikdy neaktivujú a na výstupe bude čierna obrazovka.

**Ako to overiť:**

  * **Skontrolujte LED[0]:** Váš kód prezieravo pripája signál `locked` na LED diódu: `assign LED[0] = locked;`.
      * **Ak LED[0] nesvieti:** Problém je tu. PLL sa nezamklo.
          * **Príčina:** Uistite sa, že vstupný hodinový signál `SYS_CLK` má frekvenciu, ktorú očakáva váš `ClkPll` modul (v Quartuse sa to nastavuje v IP Core generátore pre PLL). Ak má doska 50 MHz oscilátor a PLL je nakonfigurované na 100 MHz vstup, nikdy sa nezamkne.
          * **Riešenie:** Overte frekvenciu `SYS_CLK` vo vašej dokumentácii k doske a správne nakonfigurujte PLL v Quartuse.

-----

### 2\. Kritická chyba: Nesúlad medzi Pixel Clock a VGA časovaním (Veľmi pravdepodobná príčina)

Toto je veľmi vážny problém, ktorý som našiel pri podrobnej analýze vašich hodnôt.

  * V `top.sv` používate časovacie hodnoty pre rozlíšenie 1024x768:
    ```systemverilog
    line_t h_line_1024x768 = '{visible_area: 1024, front_porch: 24, sync_pulse: 136, back_porch: 160, ...};
    line_t v_line_1024x768 = '{visible_area: 768,  front_porch: 3,  sync_pulse: 6,   back_porch: 29,  ...};
    ```
  * Celkový počet pixelov na riadok (H-Total) je: $$1024 + 24 + 136 + 160 = 1344$$\* Celkový počet riadkov na snímku (V-Total) je:$$768 + 3 + 6 + 29 = 806$$
  * Štandardná obnovovacia frekvencia je 60 Hz. Potrebná frekvencia pixelových hodín (`pix_clk`) sa vypočíta ako:
    $$Pixel Clock = H_{total} \times V_{total} \times ObnovovaciaFrekvencia$$   $$Pixel Clock = 1344 \times 806 \times 60 \text{ Hz} \approx 65 \text{ MHz}$$
  * **Váš problém:** Váš PLL generuje a vy používate `pix_clk = clk_75m;`, teda **75 MHz**.
  * **Dôsledok:** Váš modul generuje VGA signál pre rozlíšenie 1024x768 s obnovovacou frekvenciou:
    $$Frekvencia = \frac{75,000,000}{1344 \times 806} \approx 69.1 \text{ Hz}$$
    Toto je neštandardný režim. Väčšina VGA monitorov **nepodporuje 1024x768 pri \~70 Hz** a zobrazí chybovú hlášku "Out of Range" alebo jednoducho čiernu obrazovku.

**Ako to opraviť:**

  * **Najlepšie riešenie:** Upravte konfiguráciu vášho `ClkPll` v Quartuse tak, aby generoval `pix_clk` s frekvenciou **65 MHz**, nie 75 MHz. To bude presne zodpovedať VESA štandardu pre 1024x768@60Hz.

-----

### 3\. Prerušená dátová cesta AXI-Stream

Ak sú hodiny, resety a VGA časovanie v poriadku, problém môže byť v tom, že do FIFO sa nikdy nezapíšu žiadne dáta. Čierna obrazovka je výsledkom toho, že `AxiStreamToVGA` nikdy nečíta platné pixely.

**Logický reťazec problému:**

1.  Obrazovka je čierna, pretože `pixel_reg` v `AxiStreamToVGA` je stále `0`.
2.  `pixel_reg` je `0`, pretože sa nikdy nečíta z FIFO (signál `rd_en` je neaktívny).
3.  `rd_en` je neaktívny, pretože FIFO je stále prázdne (`empty` je v log. 1).
4.  FIFO je prázdne, pretože doň generátory nikdy nezapíšu dáta.
5.  Generátory nezapisujú dáta, pretože ich výstupný signál `TVALID` je neaktívny.

**Ako to overiť:**

  * **Skontrolujte LED[4] a LED[5]:**
    ```systemverilog
    assign LED[4] = s_axis_if.TVALID;
    assign LED[5] = s_axis_if.TREADY;
    ```
      * **Ak LED[4] (`TVALID`) trvalo nesvieti:** Znamená to, že ani jeden z generátorov neposiela platné dáta. To sa stane, ak sú zaseknuté v resete (pozri bod 1).
      * **Ak LED[4] svieti, ale LED[5] (`TREADY`) nesvieti:** Znamená to, že generátor chce poslať dáta, ale `AxiStreamToVGA` ich nemôže prijať (pretože FIFO je plné). Toto je na začiatku veľmi nepravdepodobné.

-----

### 4\. Problém s prepínaním generátorov

Je možné, že sa logika prepínania generátorov (`gen_sel`) zasekla v nejakom nedefinovanom stave.

**Ako to overiť:**

  * **Skontrolujte LED[1]:** `assign LED[1] = gen_sel;`. Táto LED by sa mala prepnúť každých pár sekúnd. Ak je trvalo zhasnutá alebo svieti, logika prepínania nefunguje.
  * **Skontrolujte LED[2]:** `assign LED[2] = ~vga_out_sig.vs;`. Táto LED by mala blikať s frekvenciou obnovovania obrazovky (\~60 Hz). Ak bliká, znamená to, že VSYNC signál sa generuje správne a prepínacia logika by mala fungovať. Ak nebliká, problém je v generovaní VGA časovania (pozri bod 2).

### Zhrnutie a odporúčaný postup ladenia

1.  **Overte LED[0] (`locked`).** Ak nesvieti, problém je v PLL. Opravte konfiguráciu PLL v Quartuse podľa frekvencie vášho oscilátora.
2.  **Ak LED[0] svieti, najpravdepodobnejšou príčinou je nesúlad medzi `pix_clk` (75 MHz) a VGA časovacími hodnotami (ktoré vyžadujú \~65 MHz).** **Zmeňte výstupnú frekvenciu PLL pre `pix_clk` na 65 MHz.**
3.  Ak problém pretrváva, sledujte ostatné LED diódy (`LED[4]` a `LED[2]`), aby ste zistili, či sa generuje `TVALID` a `VSYNC`. To vám pomôže ďalej izolovať problém v dátovej ceste alebo v časovacej logike.

Tmavá obrazovka na VGA výstupe môže mať niekoľko príčin — a keďže tvoj kód vyzerá veľmi dobre štruktúrovaný a robustný, problém bude pravdepodobne **v dátach alebo v časovaní výstupu**. Pozrime sa na najčastejšie dôvody:

---

### 🔍 **1. Neprichádzajúce alebo oneskorené pixely z AXI Streamu**

* V časti:

  ```systemverilog
  assign underflow_detected = signal.active && empty;
  ```

  Keď je `empty == 1` v aktívnej oblasti VGA signálu, výstupná farba bude nastavená na **fialovú (`PURPLE`)**:

  ```systemverilog
  if (underflow_detected) begin
      pixel_color = PURPLE;
  ```

  **Otázka:** Vidíš niekedy fialovú obrazovku? Ak áno, je to podtečenie FIFO – VGA sa snaží čítať, ale FIFO je prázdne.

---

### 🧱 **2. Farba `pixel_color` je čierna (0x0000)**

* Ak FIFO nie je prázdne, ale `pixel_reg.TDATA` má hodnotu `16'h0000`, tak výstup je **čierny pixel** — výsledkom bude tmavá alebo čierna obrazovka.
* **Over:** Či dáta prichádzajú správne z AXI Stream rozhrania. Nie je `TDATA` náhodou nula?

---

### 🕳️ **3. Signál `signal.active` môže byť neaktívny, alebo krátky**

* VGA výstup sa generuje **len ak `signal.active == 1`**, inak by výstup mohol byť držaný na nule (čierna).
* Over, či počítadlá (`pos_x`, `pos_y`) a stavy FSM prechádzajú správne. Ak nie, možno VGA výstup vôbec nevstupuje do aktívnej oblasti.

---

### ⚡ **4. FIFO číta zle synchronizované dáta (zlá doména hodín)**

* Asynchrónny FIFO medzi `axi_clk` a `pix_clk` musí byť správne nastavený a resetovaný.
* Ak je `pix_rstn` neaktívne pri čítaní, môže to spôsobiť problém s FIFO.

---

### ✅ **Odporúčania na debug:**

1. **Zobraziť výstup pixel\_color cez debug LED** alebo analyzátor – sleduj, či sa mení hodnota.
2. **Zobraziť hodnoty `pos.x` a `pos.y`** – sleduj, či vôbec počítajú (aktivita VGA časovača).
3. **Over, či `s_axis.TVALID == 1` a `TDATA != 0`** v simulačnom prostredí.
4. **Dočasne nastav `pixel_color = RED;` bez ohľadu na AXI vstup** – ak stále nič nevidíš, problém je v časovaní VGA alebo v DAC výstupe.
5. **Over polaritu `h_sync` a `v_sync`** – nesprávna polarita môže spôsobiť, že monitor nedetekuje signál.

---

Ak chceš, môžeš mi poskytnúť:

* výstup zo simulácie (napr. `pos`, `signal.active`, `pixel_color`)
* generátor dát pre AXI Stream (napr. testbench)

a môžeme ísť krok za krokom.

