# Modul `up_down_counter`

## Popis

8-bitový synchrónny reverzibilný (up/down) čítač.

Tento modul implementuje synchrónny čítač s povolením (enable),
asynchrónnym resetom a voľbou smeru čítania.
- Ak je 'rst_ni' aktívny (log. 0), výstup 'count_o' je asynchrónne vynulovaný.
- Ak je 'en_i' neaktívny (log. 0), čítač si drží svoju hodnotu.
- Vstup 'up_down_i' určuje smer: 1 = hore (inc), 0 = dole (dec).

## Parametre

- `WIDTH`: Šírka čítača v bitoch.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál. |
| `rst_ni` | Asynchrónny reset (active-low). |
| `en_i` | Povolenie čítania. |
| `up_down_i` | Smer čítania (1=Up, 0=Down). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `count_o` | Hodnota čítača. |

