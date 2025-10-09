# Modul `vga_timing`

## Popis

VGA generátor časovania

Tento modul zabezpečuje generovanie horizontálneho a vertikálneho časovania pre VGA výstup.
Pracuje s dvoma nezávislými inštanciami `vga_line` – pre horizontálne a vertikálne časovanie.
Každý generátor prijíma štruktúru `line_t` s parametrami časovania (sync, back porch, active, front porch).
Modul vypočítava signály ako hsync, vsync, hde, vde, koniec riadku (eol) a koniec snímky (eof).

## Parametre

- `[in]`: MAX_COUNTER_H   Najvyššia hodnota, ktorú dosiahne čítač počítajúci pozíciu v H smere
- `[in]`: MAX_COUNTER_V   Najvyššia hodnota, ktorú dosiahne čítač počítajúci pozíciu v V smere

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Systémové hodiny (pixel clock) |
| `rst_ni` | Asynchrónny reset, aktívny v L |
| `enable_i` | Povolenie činnosti (napr. z časovača pre refresh) |
| `h_line_i` | Horizontálna štruktúra `line_t` so všetkými parametrami VGA riadku |
| `v_line_i` | Vertikálna štruktúra `line_t` pre riadky a snímky |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `hde_o` | Príznak, že sa nachádzame v aktívnej časti riadku (data enable pre pixely) |
| `vde_o` | Príznak, že sa nachádzame v aktívnej oblasti obrázka (riadky) |
| `hsyn_o` | Horizontálny synchronizačný impulz, upravený podľa polarity |
| `vsyn_o` | Vertikálny synchronizačný impulz, upravený podľa polarity |
| `eol_o` | Jeden pulz na konci každého riadku |
| `eof_o` | Jeden pulz na konci celej snímky (kombinácia eol a koniec vertikálneho počítadla) |

## Príklady použitia

```systemverilog
Názorný príklad použitia:

import vga_pkg::*;

localparam VgaMode = VGA_640x480_60;

// --- Signály pre prepojenie modulov ---
wire       hde, vde;       // Data Enable signály
wire       eol, eof;       // Pulzy konca riadku/snímky
wire       vsync, hsync;   // Synchro pulzy pre grafiku VGA

line_t      h_line;
line_t      v_line;

`ifdef __ICARUS__
// Pre simuláciu (Icarus) zadáme parametre manuálne
h_line = '{640, 16, 96, 48, PulseActiveLow};
v_line = '{480, 10, 2, 33, PulseActiveLow};
`else
// Pre syntézu (Quartus) použijeme funkciu z balíčka vga_pkg
vga_params_t vga_params = get_vga_params(VgaMode);
assign h_line = vga_params.h_line;
assign v_line = vga_params.v_line;
`endif

vga_timing #(
.MAX_COUNTER_H(MaxPosCounterX),
.MAX_COUNTER_V(MaxPosCounterY)
) u_vga_timing (
.clk_i(clk),
.rst_ni(rst_n),
.enable_i(1'b1),
.h_line_i(h_line),
.v_line_i(v_line),
.hde_o(hde),
.vde_o(vde),
.hsyn_o(hsync),
.vsyn_o(vsync),
.eol_o(eol),
.eof_o(eof)
);
```

