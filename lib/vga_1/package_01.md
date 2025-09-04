Jasné! Tu je ukážka, ako môžeš vyextrahovať typedefy a parametre do samostatného package súboru `VgaPkg.sv` a ako ho potom použiť v module `Vga` a ostatných moduloch.

---

## 1) Vytvor `VgaPkg.sv`

```systemverilog
package VgaPkg;

    // Šírka pre časovacie parametre v bitoch (napr. 11-bit = max 2047)
    parameter int LINE_WIDTH = 11;

    // Typ pre časovacie parametre jedného video riadku
    typedef struct packed {
        logic [LINE_WIDTH-1:0] visible_area;  // počet zobrazovaných pixelov
        logic [LINE_WIDTH-1:0] front_porch;   // predná medzera
        logic [LINE_WIDTH-1:0] sync_pulse;    // šírka synchronizačného impulzu
        logic [LINE_WIDTH-1:0] back_porch;    // zadná medzera
        logic                  polarity;      // polarita sync signálu (nevyužitá)
    } Line_t;

    // Video dátová štruktúra – farebné dáta
    typedef struct packed {
        logic [4:0] red;
        logic [5:0] grn;
        logic [4:0] blu;
    } VGA_data_t;

    // Štruktúra synchronizačných signálov VGA
    typedef struct packed {
        logic hs;
        logic vs;
    } VGA_sync_t;

    // Konštanta pre farbu mimo zobrazovacej oblasti
    parameter VGA_data_t BLANKING_COLOR = '{red: 5'h1F, grn: 6'h3F, blu: 5'h00}; // žltá

endpackage
```

---

## 2) Použitie balíčka v module

Vo všetkých súboroch alebo moduloch, kde chceš použiť tieto typedefy a parametre, stačí pridať na začiatok:

```systemverilog
import VgaPkg::*;
```

Napríklad v `Vga.sv`:

```systemverilog
module Vga #(
    parameter VGA_data_t BLANKING_COLOR = BLANKING_COLOR // z balíčka
)(
    input  logic         clk,
    input  logic         rstn,
    input  logic         enable,
    input  Line_t        h_line,
    input  Line_t        v_line,
    input  VGA_data_t    data_in,
    output logic         de,
    output VGA_data_t    data_out,
    output VGA_sync_t    sync_out
);

    import VgaPkg::*;  // import balíčka

    // ... zvyšok kódu použije Line_t, VGA_data_t, BLANKING_COLOR atď.
endmodule
```

---

## 3) Uprav ostatné moduly rovnako

V každom module, kde používaš `Line_t`, `VGA_data_t`, `VGA_sync_t` alebo konštanty z balíčka, pridaj `import VgaPkg::*;`.

---

## 4) Kompilácia a simulácia

* Pri používaní **Quartus**:

  Pri kompilácii pridaj `VgaPkg.sv` ako prvý súbor, potom ďalšie moduly, aby kompilátor poznal balíček pred modulmi.

* Pri **Icarus Verilog**:

  Uisti sa, že používaš novšiu verziu (verziu 11 alebo novšiu), ktorá podporuje balíčky.
  Ak nie, použiješ dočasne `include` súbory, alebo držíš typedefy priamo v `.sv` súbore.

---

### Chceš, aby som ti pripravil celý tvoj súbor už rozdelený na `.sv` súbory s balíčkom a modulmi pripravenými na import?

Alebo potrebuješ pomoc s ďalším krokom, napr. s kompiláciou v Quartus?
