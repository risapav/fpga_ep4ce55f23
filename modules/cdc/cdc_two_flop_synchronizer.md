# Modul `cdc_two_flop_synchronizer`

## Popis

Dvojstupňový synchronizátor signálu pre CDC (Clock Domain Crossing).

Modul slúži na bezpečné prenesenie asynchrónneho signálu do cieľovej hodinovej domény
pomocou dvoch postupných registrov (flip-flopov). Tým sa minimalizuje riziko metastability.
Šírka synchronizovaného signálu je parametrická (`WIDTH`).

## Parametre

- `[in]`: WIDTH       Počet bitov vstupného a výstupného signálu (predvolené 1).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál cieľovej domény. |
| `rst_ni` | Asynchrónny reset, aktívny nízky (negatívna logika). |
| `d_i` | Asynchrónny vstupný signál (z inej hodinovej domény). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `q_o` | Synchronizovaný výstupný signál, bezpečne prenesený do cieľovej domény. |

## Príklady použitia

```systemverilog
cdc_two_flop_synchronizer #(
.WIDTH(8)
) u_sync (
.clk_i(clk_target),
.rst_ni(rst_n),
.d_i(async_signal),
.q_o(sync_signal)
);
```

