# Modul `framebuffer_ctrl`

## Popis

Double-Buffered Framebuffer Controller.

Most medzi AXI Stream Video a SDRAM Controllerom.
- Input: AXI Stream Sink (Zápis do SDRAM).
- Output: AXI Stream Source (Čítanie z SDRAM pre displej).
- Podporuje Double Buffering (Ping-Pong) pre elimináciu tearingu.

## Parametre

- `H_RES`: Horizontálne rozlíšenie (pre generovanie TLAST).
- `V_RES`: Vertikálne rozlíšenie.
- `BASE_ADDR_0`: Adresa prvého buffera v SDRAM.
- `BASE_ADDR_1`: Adresa druhého buffera v SDRAM.
- `ASYNC_FIFO_DEPTH`: Hĺbka interných FIFO (musí byť > 2 * BURST_LEN).

