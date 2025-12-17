# Modul `CheckerPattern`

## Popis

AXI4-Stream generátor šachovnicového vzoru.

Generuje RGB565 šachovnicu na základe súradníc z axis_frame_streamer.
Slúži ako príklad integrácie modulov.

## Parametre

- `H_RES`: Horizontálne rozlíšenie.
- `V_RES`: Vertikálne rozlíšenie.
- `CELL_W_BITS`: Šírka bunky (log2).
- `CELL_H_BITS`: Výška bunky (log2).
- `DATA_WIDTH`: Šírka TDATA (16).

