# Modul `count_down_timer`

## Popis

Generický odpočítavací časovač.

Modul pre odpočítavanie s podporou nahrávania (load) a saturáciou na nule.
Umožňuje voľbu medzi kombinačným a registrovaným výstupom 'done'.

## Parametre

- `COUNT_WIDTH`: Šírka interného počítadla.
- `DONE_REGISTERED`: 1 = registrovaný výstup (latencia 1 takt), 0 = kombinačný.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál. |
| `rst_ni` | Asynchrónny reset (active-low). |
| `load_i` | Signál pre nahranie počiatočnej hodnoty. |
| `load_val_i` | Počiatočná hodnota počítadla. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `done_o` | Indikácia, že počítadlo dosiahlo nulu. |

