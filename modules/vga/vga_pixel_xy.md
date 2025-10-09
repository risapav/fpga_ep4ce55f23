# Modul `vga_pixel_xy`

## Popis

Generátor VGA súradníc pixelov (X, Y)

Modul `vga_pixel_xy` generuje súradnice aktuálneho pixelu na obrazovke (X, Y)
na základe hodín (pixel clock), pulzov konca riadku (eol_i) a snímky (eof_i).
Pozícia bodu (X, Y), ktorý sa nachádza vo viditeľnej časti obrazu.
Inkrementuje X každý takt a resetuje ho na konci riadku. Y sa inkrementuje
na konci každého riadku a resetuje na konci snímky. Vhodné na generovanie
pozície pre grafický výstup v rámci VGA časovania.

## Parametre

- `[in]`: MAX_COUNTER_H   Najvyššia hodnota, ktorú dosiahne čítač počítajúci pozíciu v H smere
- `[in]`: MAX_COUNTER_V   Najvyššia hodnota, ktorú dosiahne čítač počítajúci pozíciu v V smere

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál – pixel clock. |
| `rst_ni` | Asynchrónny reset (aktívny v L). |
| `enable_i` | Povolenie inkrementácie (aktivuje čítanie X/Y). |
| `eol_i` | Pulz konca riadku – resetuje X a inkrementuje Y. |
| `eof_i` | Pulz konca snímky – resetuje Y. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `x_o` | Pozícia X súradnice v aktívnej časti obrazu |
| `y_o` | Pozícia Y súradnice v aktívnej časti obrazu |

## Príklady použitia

```systemverilog
Názorný príklad použitia:

import vga_pkg::*;

vga_pixel_xy #(
.MAX_COUNTER_H(MaxPosCounterX),
.MAX_COUNTER_V(MaxPosCounterY)
) u_pixel_xy (
.clk_i(clk),
.rst_ni(rst_n),
.enable_i(1'b1),
.eol_i(eol),
.eof_i(eof),
.x_o(x),
.y_o(y)
);
```

