# Modul `sdram_ctrl`

## Popis

SDRAM Core Controller.

Hlavný radič SDRAM pamäte. Obsahuje stavový automat pre inicializáciu,
refresh a read/write operácie. Využíva interné Skid Buffery a FIFO pre
oddelenie časovania a burst prenosy.

## Parametre

- `CFifoAddrWidth`: Šírka adresy interných FIFO.
- `T_*_CYCLES`: Časovanie SDRAM (definované v sdram_pkg).

