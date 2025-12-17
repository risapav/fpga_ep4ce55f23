# Modul `axis_frame_streamer`

## Popis

AXI4-Stream Frame Streamer generujúci súradnice pixelov.

Generuje sekvenčný tok pixelových súradníc (x, y) a riadiace
signály (TVALID, TLAST, TUSER) pre AXI4-Stream Video.

Správanie signálov:
- TVALID: Trvalo log.1 (okrem resetu).
- TUSER[0]: Start of Frame (SOF) - aktívny pri pixeli (0,0).
- TLAST: End of Line (EOL) - aktívny na konci každého riadku.

## Parametre

- `H_RES`: Horizontálne rozlíšenie.
- `V_RES`: Vertikálne rozlíšenie.
- `DATA_WIDTH`: Šírka TDATA.
- `USER_WIDTH`: Šírka TUSER.
- `KEEP_WIDTH`: Šírka TKEEP.
- `ID_WIDTH`: Šírka TID.
- `DEST_WIDTH`: Šírka TDEST.
- `COUNTER_WIDTH`: Šírka čítačov.

