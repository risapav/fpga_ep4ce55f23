# Modul `axis_cdc_fifo`

## Popis

Bezpečný AXI4-Stream Clock Domain Crossing FIFO.

Zabezpečuje prenos AXI Stream dát medzi asynchrónnymi doménami.
Implementuje FWFT (First-Word-Fall-Through) logiku na čítacej strane
pre konverziu latencie RAM na AXI handshake protokol.

Vyžaduje externé moduly:
- cdc_reset_synchronizer
- cdc_async_fifo

## Parametre

- `DATA_WIDTH`: Šírka dát (TDATA).
- `USER_WIDTH`: Šírka užívateľských dát (TUSER).
- `FIFO_DEPTH`: Hĺbka FIFO (musí byť mocnina 2).
- `RAM_STYLE`: Štýl implementácie RAM ("auto", "block", "distributed").

