# Modul `cdc_reset_synchronizer`

## Popis

Synchronizátor asynchrónneho resetu (Reset Bridge).

Asynchrónne aktivuje a synchrónne deaktivuje reset signál
v cieľovej hodinovej doméne. Zabraňuje metastabilite pri uvoľnení resetu.

## Parametre

- `STAGES`: Počet synchronizačných stupňov (min. 2).
- `WIDTH`: Šírka resetu (Musí byť 1. Parameter je tu pre kompatibilitu inštancií).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Cieľové hodiny. |
| `rst_ni` | Vstupný asynchrónny reset (active-low). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `rst_no` | Výstupný synchronizovaný reset (active-low). |

