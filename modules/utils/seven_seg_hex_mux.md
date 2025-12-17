# Modul `seven_seg_hex_mux`

## Popis

Multiplexovaný 7-segmentový ovládač (HEX dekodér).

Ovláda viacmiestny 7-segmentový displej. Podporuje číslice 0-F
a desatinné bodky. Konfigurovateľný pre Spoločnú Anódu alebo Katódu.

## Parametre

- `NUM_DIGITS`: Počet číslic (digitov).
- `CLOCK_FREQ_HZ`: Frekvencia vstupných hodín.
- `DIGIT_REFRESH_HZ`: Obnovovacia frekvencia na jeden digit.
- `COMMON_ANODE`: 1 = Common Anode (0=ON), 0 = Common Cathode (1=ON).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál. |
| `rst_ni` | Asynchrónny reset (active-low). |
| `digits_i` | Pole hodnôt pre jednotlivé digity (0-F). |
| `dots_i` | Pole pre desatinné bodky. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `digit_sel_o` | Výber digitu (One-Hot). |
| `segment_sel_o` | Výber segmentov (DP,G,F,E,D,C,B,A). |
| `current_digit_o` | Index práve aktívneho digitu (pre debug). |

