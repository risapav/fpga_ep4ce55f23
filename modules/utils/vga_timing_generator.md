# Modul `vga_timing_generator`

## Popis

Generátor časovania pre VGA (HSync, VSync, Blanking).

Generuje synchronizačné signály a súradnice pixelov na základe
parametrov časovania. Podporuje nastaviteľnú polaritu.

## Parametre

- `H_VISIBLE`: Viditeľná šírka (pixely).
- `H_FRONT_PORCH`: Predná veranda (H).
- `H_SYNC_PULSE`: Sync pulz (H).
- `H_BACK_PORCH`: Zadná veranda (H).
- `H_POLARITY`: Polarita HSync (1 = Active High).
- `COORD_WIDTH`: Šírka výstupných súradníc (default 12 pre podporu do 4095).

