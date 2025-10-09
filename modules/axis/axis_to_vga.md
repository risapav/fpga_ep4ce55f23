# Modul `axis_to_vga`

## Popis

Premosťuje AXI4-Stream dáta na paralelný VGA výstup.

Modul prijíma dáta cez AXI4-Stream rozhranie v jednej hodinovej doméne,
ukladá ich do asynchrónneho FIFO a následne ich vysiela do VGA radiča
v druhej hodinovej doméne (pixel clock). FIFO zabezpečuje plynulý prenos
dát medzi rôznymi hodinovými doménami a minimalizuje stratu dát.

## Parametre

- `[in]`: FIFO_DEPTH          Hĺbka FIFO bufferu (počet uložených slov).
- `[in]`: C_VGA_MODE          Pevne nastavený režim VGA (napr. 640x480@60Hz).

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `axi_clk_i` | Hodinový signál pre AXI4-Stream doménu. |
| `axi_rst_ni` | Asynchrónny reset AXI domény (aktívny v nule). |
| `pix_clk_i` | Hodinový signál pre pixelovú (VGA) doménu. |
| `pix_rst_ni` | Asynchrónny reset pixelovej domény (aktívny v nule). |
| `s_axis` | AXI4-Stream slave rozhranie pre vstupné dáta. |

## Výstupy (output)

| Názov | Popis |
|-------|--------|
| `vga_data_o` | Paralelné VGA dátové výstupy (farby). |
| `vga_sync_o` | Synchronizačné signály VGA (HSYNC, VSYNC). |
| `hde_o` | Signál indikujúci aktívnu horizontálnu oblasť (pixel data enable). |
| `vde_o` | Signál indikujúci aktívnu vertikálnu oblasť (pixel data enable). |

## Príklady použitia

```systemverilog
axis_to_vga #(
.FIFO_DEPTH(4096),
.C_VGA_MODE(VGA_800x600_60)
) u_axis_to_vga (
.axi_clk_i(clk_axi),
.axi_rst_ni(rstn_axi),
.pix_clk_i(clk_pix),
.pix_rst_ni(rstn_pix),
.s_axis(axi_stream_slave_if),
.vga_data_o(vga_rgb),
.vga_sync_o(vga_sync),
.hde_o(hde),
.vde_o(vde)
);
```

