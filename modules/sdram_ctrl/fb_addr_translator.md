# Modul `fb_addr_translator`

## Popis

Prekladá lineárnu 32-bitovú adresu na SDRAM geometriu (Bank, Row, Col).

Mapovanie je sekvenčné (Row-Sequential):
Adresa rastie v poradí: Column -> Row -> Bank.
Toto minimalizuje prepínanie riadkov (Page Miss) pri lineárnom burst prístupe.

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `linear_addr_i` | Lineárna adresa (napr. z Framebuffera). |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `sdram_addr_o` | Fyzická adresa SDRAM (štruktúra). |

