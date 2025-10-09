# Modul `axis_frame_streamer`

## Popis

AXI4-Stream Frame Streamer generujúci súradnice pixelov.

Modul generuje sekvenčný tok pixelových súradníc (x, y) pre dané
rozlíšenie (H_RES × V_RES) a vystavuje ich ako AXI4-Stream master rozhranie.
Signály TVALID, TLAST a TUSER sú riadené podľa štandardu AXI4-Stream:
- TLAST označuje posledný pixel rámca (pravý spodný roh).
- TUSER je aktívny na prvom pixeli rámca (ľavý horný roh).
Modul je vhodný na testovanie a generovanie riadiacich signálov pre
spracovanie videa alebo grafiky.

## Parametre

- `[in]`: H_RES               Horizontálne rozlíšenie rámca (pixely).
- `[in]`: V_RES               Vertikálne rozlíšenie rámca (pixely).
- `[in]`: DATA_WIDTH          Šírka dátového slova (bity).
- `[in]`: USER_WIDTH          Šírka TUSER signálu.
- `[in]`: KEEP_WIDTH          Šírka TKEEP signálu (DATA_WIDTH/8).
- `[in]`: ID_WIDTH            Šírka TID signálu (ak sa používa).
- `[in]`: DEST_WIDTH          Šírka TDEST signálu (ak sa používa).
- `[in]`: COUNTER_WIDTH       Šírka čítačov pre x a y (vypočítaná z H_RES).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál modulu. |
| `rst_ni` | Aktívny nízky reset modulu. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `x_o` | Aktuálna horizontálna súradnica pixelu. |
| `y_o` | Aktuálna vertikálna súradnica pixelu. |
| `m_axis` | AXI4-Stream master rozhranie so signálmi TVALID, TREADY, TDATA, TUSER, TLAST atď. |

## Príklady použitia

```systemverilog
axis_frame_streamer #(
.H_RES(1280),
.V_RES(720),
.DATA_WIDTH(24),
.USER_WIDTH(1)
) u_frame_streamer (
.clk_i(clk),
.rst_ni(rstn),
.x_o(x),
.y_o(y),
.m_axis(m_axis_if)
);
```

