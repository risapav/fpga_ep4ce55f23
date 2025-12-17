# Modul `pointer_sync`

## Popis

Modul pre synchronizáciu pointerov a inkrementáciu lokálneho pointera.

Kombinuje dve funkcie pre FIFO implementácie:
1. Binárne počítadlo pre lokálny pointer (Write alebo Read).
2. CDC synchronizátor pre Gray pointer prichádzajúci z druhej domény.

Obsahuje atribúty pre správnu syntézu synchronizátora (ASYNC_REG).

## Parametre

- `ADDR_WIDTH`: Šírka adresy (pointer je ADDR_WIDTH+1).
- `TWO_STAGE_SYNC`: 1 = 2-stupňová synchronizácia (odporúčané), 0 = 1-stupňová.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál lokálnej domény. |
| `rst_ni` | Asynchrónny reset (active-low). |
| `en_i` | Povolenie inkrementácie lokálneho pointera. |
| `ptr_gray_i` | Gray pointer z druhej domény (vstup). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `bin_ptr_o` | Lokálny binárny pointer. |
| `ptr_gray_sync_o` | Synchronizovaný Gray pointer. |

