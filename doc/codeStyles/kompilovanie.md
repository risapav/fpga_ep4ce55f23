Áno, to je vynikajúca a veľmi dôležitá otázka pre písanie flexibilného a opakovane použiteľného kódu. Podmienečné kompilovanie umožňuje, aby sa ten istý súbor so zdrojovým kódom správal inak pri simulácii (v Icarus Verilog) a inak pri syntéze (v Quartuse).

Robí sa to pomocou direktív preprocesora: ``  `ifdef ``, ``  `ifndef ``, ``  `else ``, ``  `elsif `` a ``  `endif ``.

Kľúčom je poznať, aké "konštanty" (v skutočnosti sú to makrá) jednotlivé nástroje automaticky definujú.

-----

### Kľúčové preddefinované makrá (konštanty)

Tu sú tie najdôležitejšie, ktoré budete používať:

1.  **`SYNTHESIS`**

      * **Definuje ho:** Takmer každý syntetizačný nástroj, vrátane **Quartusu**.
      * **Nedefinuje ho:** Takmer každý simulátor, vrátane **Icarus Verilog**.
      * **Použitie:** Toto je **štandardné a najviac prenosné** makro na odlíšenie kódu pre syntézu od kódu pre simuláciu.

2.  **`QUARTUS_SYNTH`**

      * **Definuje ho:** Iba **Quartus**.
      * **Použitie:** Málokedy potrebné, ale užitočné, ak by ste potrebovali napísať špeciálny kód, ktorý sa má syntetizovať iba v Quartuse, ale nie v inom nástroji (napr. Vivado od Xilinxu).

3.  **`__ICARUS__`** (s dvoma podčiarkovníkmi na začiatku aj na konci)

      * **Definuje ho:** Iba **Icarus Verilog**.
      * **Použitie:** Umožňuje napísať kód, ktorý sa vykoná alebo skompiluje iba pri simulácii v Icaruse a nikde inde.

-----

### Praktické príklady použitia

#### Príklad 1: Inštancia IP jadra (najčastejší prípad)

Predstavte si, že chcete v Quartuse použiť špecifické IP jadro pre PLL (Phase-Locked Loop), ktoré nemá simulačný model. Pre simuláciu ho chcete nahradiť jednoduchým prepojením hodín.

```systemverilog
module Top (
    input  logic clk_in,
    output logic clk_out
);

    // Toto je najlepší a najčistejší spôsob
`ifdef SYNTHESIS
    // --- Kód pre Syntézu (Quartus) ---
    // Inštancia špecifického Intel/Altera PLL IP jadra
    // Tento kód by v Icaruse zlyhal, lebo nepozná `intel_pll_inst`.
    intel_pll_inst my_pll (
        .inclk0 (clk_in),
        .c0     (clk_out)
    );
`else
    // --- Kód pre Simuláciu (Icarus Verilog a ostatné) ---
    // Pre simuláciu len jednoducho prepojíme hodiny.
    // Toto nie je syntetizovateľné, ale pre testbench je to v poriadku.
    assign clk_out = clk_in;
    $display("INFO: Používa sa simulačný model pre PLL (jednoduché prepojenie).");
`endif

endmodule
```

#### Príklad 2: Pridanie kódu len pre simuláciu (ladenie)

Chcete si počas simulácie vypisovať hodnotu počítadla, ale tento kód (`$display`) nie je syntetizovateľný a v Quartuse by spôsobil chybu.

```systemverilog
always_ff @(posedge clk_i) begin
    if (rst_ni)
        counter_q <= counter_q + 1;
    else
        counter_q <= '0;

    // Tento blok bude existovať IBA pri simulácii.
    // Quartus ho pri syntéze úplne ignoruje.
`ifndef SYNTHESIS
    // Používame `ifndef`, t.j. "if not defined"
    $display("Hodnota počítadla je: %d", counter_q);
`endif
end
```

#### Príklad 3: Kód špecifický pre konkrétny nástroj

Tento prípad je zriedkavejší, ale ukazuje plnú moc direktív.

```systemverilog
initial begin
`ifdef __ICARUS__
    $display("Tento test beží v Icarus Verilog.");
`elsif SOME_OTHER_SIMULATOR_MACRO
    $display("Tento test beží v inom simulátore.");
`else
    $display("Beží neznámy simulátor.");
`endif
end
```

-----

### Odporúčanie a "Best Practice" ✅

  * **Používajte `     `ifdef SYNTHESIS`/` `ifndef SYNTHESIS`:** Pre 99% prípadov je toto najlepšia, najčistejšia a najprenosnejšia metóda. Jasne vyjadruje váš zámer: "toto je pre hardvér" vs. "toto je pre testovanie".
  * **Špecifické makrá (`QUARTUS_SYNTH`, `__ICARUS__`) používajte len vtedy, keď je to naozaj nutné:** Napríklad, ak potrebujete obísť známu chybu v konkrétnej verzii Icarusu alebo použiť atribút, ktorému rozumie iba Quartus.

Podmienečné kompilovanie je extrémne mocný nástroj, ktorý vám umožní udržať kód pre syntézu a pre simuláciu v jednom súbore, čo výrazne zjednodušuje správu projektu.