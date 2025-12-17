# Modul `cdc_two_flop_synchronizer`

## Popis

Dvojstupňový synchronizátor signálu pre CDC.

Implementuje štandardný 2-FF synchronizátor na potlačenie metastability.
Výstup q_o je výstupom druhého klopného obvodu.
Obsahuje atribúty pre správne umiestnenie v FPGA (Quartus/Vivado).

## Parametre

- `WIDTH`: Počet bitov signálu.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál cieľovej domény. |
| `rst_ni` | Asynchrónny reset (aktívny LOW). |
| `d_i` | Vstupný asynchrónny signál. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `q_o` | Synchronizovaný výstup. |

