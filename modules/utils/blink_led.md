# Modul `blink_led`

## Popis

Jednoduchý modul na blikanie LED s nastaviteľnou frekvenciou.

Modul generuje signál pre LED, ktorá bliká so zadanou frekvenciou.
Počet taktov na jednu polperiódu sa vypočíta z parametrov.

## Parametre

- `CLOCK_FREQ_HZ`: Frekvencia vstupného hodinového signálu v Hz.
- `BLINK_HZ`: Požadovaná frekvencia blikania LED v Hz.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Vstupný hodinový signál. |
| `rst_ni` | Asynchrónny reset (aktívny v nule). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `led_o` | Výstupný signál pre LED (blikajúci). |

