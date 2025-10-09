# Modul `cdc_reset_synchronizer`

## Popis

Synchronizátor asynchrónneho resetu pre cieľovú hodinovú doménu.

Modul zabezpečuje bezpečné prenesenie asynchrónneho reset signálu
do cieľovej hodinovej domény pomocou dvojstupňového synchronizátora.
Výstupný reset je synchronný a aktívny v logickej nule.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál cieľovej domény. |
| `rst_ni` | Asynchrónny reset, aktívny nízky (negatívna logika). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `rst_no` | Synchronný reset, aktívny nízky. |

## Príklady použitia

```systemverilog
cdc_reset_synchronizer u_reset_sync (
.clk_i(clk),
.rst_ni(async_rst_n),
.rst_no(sync_rst_n)
);
```

