# Modul `axis_to_vga`

## Popis

AXI-Stream na VGA prevodník s časovaním a registrovaným výstupom.

Modul číta AXI4-Stream dáta a generuje VGA signály.
Implementuje slave rozhranie s back-pressure riadeným aktívnou oblasťou.
Všetky výstupy sú registrované pre čisté časovanie.

## Parametre

- `H_ACT`: Aktívne pixely horizontálne.
- `H_FP`: Front Porch horizontálne.
- `H_SP`: Sync Pulse horizontálne.
- `H_BP`: Back Porch horizontálne.
- `V_ACT`: Aktívne riadky vertikálne.
- `V_FP`: Front Porch vertikálne.
- `V_SP`: Sync Pulse vertikálne.
- `V_BP`: Back Porch vertikálne.
- `H_SYNC_POLARITY`: Polarita HSync (1=Active High).
- `V_SYNC_POLARITY`: Polarita VSync (1=Active High).
- `OUTPUT_FORMAT`: Formát farby (565 alebo 888).
- `AXI_DATA_WIDTH`: Šírka vstupu (16 alebo 24+).
- `BLANKING_COLOR_888`: Farba pozadia pre 888.
- `BLANKING_COLOR_565`: Farba pozadia pre 565.

