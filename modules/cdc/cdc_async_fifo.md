# Modul `cdc_async_fifo`

## Popis

Asynchrónny FIFO buffer (CDC) s konfigurovateľnými prahmi.

Implementuje FIFO pre prenos dát medzi rôznymi hodinovými doménami.
Využíva Gray kód pre bezpečný prenos pointerov.
Obsahuje synchronizáciu resetov a detekciu pretečenia/podtečenia.

## Parametre

- `DATA_WIDTH`: Šírka dátového slova.
- `DEPTH`: Hĺbka FIFO (musí byť mocnina 2).
- `ALMOST_FULL_THRESHOLD`: Prah pre signál almost_full.
- `ALMOST_EMPTY_THRESHOLD`: Prah pre signál almost_empty.
- `ADDR_WIDTH`: Šírka adresy (vypočítaná automaticky).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `wr_clk_i,` | wr_rst_ni   Zápisová doména. |
| `rd_clk_i,` | rd_rst_ni   Čítacia doména. |

