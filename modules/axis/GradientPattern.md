# Modul `GradientPattern`

## Popis

Generuje AXI4-Stream výstup s farebným gradientom.

Modul vytvára diagonálny farebný gradient podľa pozície pixelu (x, y).
Používa vnútorný frame streamer, ktorý generuje súradnice pixelov,
a kombinačný modul `GradientPattern`, ktorý vypočíta farbu podľa súčtu x a y.
Výsledný dátový tok je vystavený ako AXI4-Stream master rozhranie.

## Parametre

- `[in]`: DATA_WIDTH          Šírka dát (počet bitov pre farbu).
- `[in]`: USER_WIDTH          Šírka USER signálu AXI4-Stream.
- `[in]`: ID_WIDTH            Šírka ID signálu AXI4-Stream (ak je využívaný).
- `[in]`: DEST_WIDTH          Šírka DEST signálu AXI4-Stream (ak je využívaný).
- `[in]`: H_RES               Horizontálne rozlíšenie generovaného obrazu (pixely).
- `[in]`: V_RES               Vertikálne rozlíšenie generovaného obrazu (pixely).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `clk_i` | Hodinový signál pre generovanie dát. |
| `rst_ni` | Aktívny nízky asynchrónny reset modulu. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `m_axis` | AXI4-Stream master rozhranie s generovanými dátami. |

## Príklady použitia

```systemverilog
axis_gradient_generator #(
.DATA_WIDTH(16),
.USER_WIDTH(1),
.ID_WIDTH(0),
.DEST_WIDTH(0),
.H_RES(1024),
.V_RES(768)
) u_gradient_gen (
.clk_i(clk),
.rst_ni(rstn),
.m_axis(m_axis_if)
);
```

