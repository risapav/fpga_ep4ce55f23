# Modul `rgb565_to_rgb888`

## Popis

Kombinačný modul, ktorý konvertuje 16-bitovú farbu vo formáte RGB565 na 24-bitovú farbu vo formáte RGB888.

Tento modul realizuje prevod medzi dvoma bežnými farebnými formátmi. Vstupom je 16-bitová farba
v štruktúre `vga_data_t`, ktorá definuje farbu pomocou 5 bitov pre červenú, 6 bitov pre zelenú a
5 bitov pre modrú zložku (RGB565). Výstupom sú tri samostatné 8-bitové signály pre každú farebnú
zložku (RGB888).

Konverzia je implementovaná pomocou replikácie najvýznamnejších bitov zo vstupných zložiek
do najmenej významných bitov výstupných zložiek, čo je hardvérovo efektívna metóda
s dobrými vizuálnymi výsledkami.
- R_out[7:0] = { R_in[4:0], R_in[4:2] }
- G_out[7:0] = { G_in[5:0], G_in[5:4] }
- B_out[7:0] = { B_in[4:0], B_in[4:2] }

Modul je čisto kombinačný a nevyžaduje hodinový signál.
Pre správnu funkciu je nutné, aby bol dátový typ `vga_data_t` definovaný v dosahu modulu.

## Parametre

- `[in]`: (žiadne)
- `[out]`: (žiadne)

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `rgb565_i` | Vstupná 16-bitová farba v štruktúre `rgb565_t` (formát RGB565). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `rgb888_o` | Výstupná 24-bitová farba  v štruktúre `rgb888_t` (formát RGB888). |

## Príklady použitia

```systemverilog
// Ukážka použitia v inom module.
// Predpokladá sa, že `vga_data_t` je definovaný.

// Signály pre prepojenie
rgb565_t my_rgb565_color;
rgb888_t my_rgb888_color;

// Priradenie nejakej hodnoty (napr. jasná fialová)
assign my_rgb565_color = '{red: 5'b11100, grn: 5'b001001, blu: 5'b11101};

// Inštancia modulu
rgb565_to_rgb888 u_color_converter (
.rgb565_i(my_rgb565_color),
.rgb888_o(my_rgb888_color)
);
```

