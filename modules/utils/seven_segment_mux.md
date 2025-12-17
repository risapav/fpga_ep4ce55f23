# Modul `seven_segment_mux`

## Popis

Multiplexovaný ovládač 7-segmentového displeja (BCD).

Zobrazuje číslice 0-9. Pre HEX (0-F) použite seven_seg_hex_mux.
Podporuje Common Anode aj Common Cathode.
Výstupy sú registrované pre bezpečné pripojenie na FPGA piny.

## Parametre

- `NUM_DIGITS`: Počet číslic.
- `CLK_FREQ_HZ`: Frekvencia hodín (Hz).
- `DIGIT_REFRESH_RATE_HZ`: Obnovovacia frekvencia celého displeja (Hz).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodiny. |
| `rst_ni` | Asynchrónny reset (active-low). |
| `digits_i` | Pole BCD hodnôt (packed array [N][3:0]). |
| `dp_i` | Desatinné bodky. |
| `common_anode_i` | 1 = Common Anode (Active Low), 0 = Common Cathode. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `segments_o` | Segmenty (a-g). |
| `dp_o` | Desatinná bodka výstup. |
| `digit_en_o` | Povolenie digitu. |

