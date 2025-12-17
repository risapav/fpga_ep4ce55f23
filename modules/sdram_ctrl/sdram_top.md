# Modul `sdram_top`

## Popis

Top-Level SDRAM Interface (Wrapper).

Integruje 'sdram_ctrl' (jadro) a 'sdram_cmd_checker' (ochrana).
Poskytuje jednotné, bezpečné rozhranie pre užívateľa.

Tok dát:
User Cmd  -> [Checker] -> [Controller] -> SDRAM
User Data -> [Controller (Skid+FIFO)]  -> SDRAM

## Parametre

- `CFifoAddrWidth`: Hĺbka interných FIFO bufferov (2^N).
- `T_*_CYCLES`: Časovanie SDRAM.

