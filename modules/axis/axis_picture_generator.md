# Modul `axis_picture_generator`

## Popis

Generátor testovacích obrazcov pre AXI4-Stream.

Generuje statické a animované obrazce vo formáte RGB565.
Využíva 4-stupňovú pipeline pre dosiahnutie vysokého časovania (timing closure).
Obsahuje optimalizácie pre matematické operácie (fixed-point násobenie).

## Parametre

- `H_RES`: Horizontálne rozlíšenie.
- `V_RES`: Vertikálne rozlíšenie.
- `DATA_WIDTH`: Šírka TDATA (RGB565 = 16).
- `USER_WIDTH`: Šírka TUSER.
- `NUM_MODES`: Počet režimov.

