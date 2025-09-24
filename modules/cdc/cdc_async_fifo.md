# Modul `cdc_async_fifo`

## Popis

Asynchrónny FIFO buffer s oddelenými hodinovými doménami pre zápis a čítanie.

Modul implementuje FIFO s nezávislými hodinovými doménami zápisu a čítania,
ktorý zabezpečuje správnu synchronizáciu medzi doménami pomocou gray kódu a
dvojstupňových synchronizátorov. Podporuje signály almost_full a almost_empty
s nastaviteľnými prahmi, vrátane detekcie pretečenia a podtečenia.

## Parametre

- `[in]`: DATA_WIDTH                Šírka dátového slova vo FIFO (bity).
- `[in]`: DEPTH                     Hĺbka FIFO, počet uložených prvkov.
- `[in]`: ALMOST_FULL_THRESHOLD     Prah pre signál almost_full (počet voľných miest).
- `[in]`: ALMOST_EMPTY_THRESHOLD    Prah pre signál almost_empty (počet obsadených miest).
- `[in]`: ADDR_WIDTH                Počet bitov na adresovanie FIFO (vypočítané z DEPTH).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `wr_clk_i` | Hodinový signál zápisovej domény. |
| `wr_rst_ni` | Asynchrónny reset zápisovej domény, aktívny v log.0. |
| `wr_en_i` | Povolenie zápisu dát do FIFO. |
| `wr_data_i` | Dáta pre zápis do FIFO. |
| `rd_clk_i` | Hodinový signál čítacej domény. |
| `rd_rst_ni` | Asynchrónny reset čítacej domény, aktívny v log.0. |
| `rd_en_i` | Povolenie čítania dát z FIFO. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `full_o` | Indikácia plného FIFO v zápisovej doméne. |
| `almost_full_o` | Indikácia takmer plného FIFO. |
| `overflow_o` | Indikácia pretečenia FIFO pri zápise. |
| `rd_data_o` | Dáta čítané z FIFO. |
| `empty_o` | Indikácia prázdneho FIFO v čítacej doméne. |
| `almost_empty_o` | Indikácia takmer prázdneho FIFO. |
| `underflow_o` | Indikácia podtečenia FIFO pri čítaní. |

## Príklady použitia

```systemverilog
cdc_async_fifo #(
.DATA_WIDTH(32),
.DEPTH(512),
.ALMOST_FULL_THRESHOLD(32),
.ALMOST_EMPTY_THRESHOLD(32)
) u_async_fifo (
.wr_clk_i(wr_clk),
.wr_rst_ni(wr_rst_n),
.wr_en_i(wr_en),
.wr_data_i(wr_data),
.full_o(full),
.almost_full_o(almost_full),
.overflow_o(overflow),
.rd_clk_i(rd_clk),
.rd_rst_ni(rd_rst_n),
.rd_en_i(rd_en),
.rd_data_o(rd_data),
.empty_o(empty),
.almost_empty_o(almost_empty),
.underflow_o(underflow)
);
```

