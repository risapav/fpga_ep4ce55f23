# Modul `CheckerPattern`

## Popis

AXI4-Stream generátor šachovnicového vzoru (checkerboard pattern)

Modul `axis_checker_generator` generuje statický šachovnicový obrazec s definovateľným rozlíšením,
šírkou a výškou buniek pomocou submodulu `CheckerPattern`. Dáta sú posielané cez AXI4-Stream rozhranie
v štandarde RGB565. Modul generuje obrazce na základe súradníc (X,Y) získaných z modulu
`axis_frame_streamer`, ktorý zabezpečuje správne načasovanie pixelových pozícií.

Vznikajúci obrazec je ideálny na testovanie a overovanie funkčnosti zobrazovacích ciest (napr. VGA, HDMI),
ako aj diagnostiku problémov s časovaním alebo FIFO podtečením.

## Parametre

- `[in]`: DATA_WIDTH         Šírka dátového poľa v AXI4-Stream (bitov) – typicky 16 pre RGB565.
- `[in]`: USER_WIDTH         Šírka TUSER signálu v AXI4-Stream rozhraní.
- `[in]`: ID_WIDTH           Šírka TID signálu (identifikácia) v AXI4-Stream.
- `[in]`: DEST_WIDTH         Šírka TDEST signálu v AXI4-Stream.
- `[in]`: H_RES              Horizontálne rozlíšenie (pixelov na riadok).
- `[in]`: V_RES              Vertikálne rozlíšenie (počet riadkov).
- `[in]`: COUNTER_WIDTH      Šírka počítadiel pre X/Y – odvodená z H_RES ako $clog2(H_RES).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Vstupný hodinový signál (pixel clock). |
| `rst_ni` | Asynchrónny reset, aktívny v L. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `m_axis` | Výstupné AXI4-Stream rozhranie, obsahujúce šachovnicový obrazec.
Polia: TVALID, TDATA (RGB565), TLAST, TUSER, TREADY. |

## Príklady použitia

```systemverilog
Názorný príklad použitia:
axis_checker_generator #(
.H_RES(800),
.V_RES(600),
.DATA_WIDTH(16),
.USER_WIDTH(1)
) u_checker (
.clk_i(clk),
.rst_ni(rst_n),
.m_axis(m_axi_checker)
);
```

