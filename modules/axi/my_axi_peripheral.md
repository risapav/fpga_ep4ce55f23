# Modul `my_axi_peripheral`

## Popis

Definície AXI rozhraní (AXI4, AXI4-Lite, AXI4-Stream) pre použitie v SoC dizajne.

Tento súbor obsahuje deklarácie troch rozhraní AXI štandardu:
- `axi4lite_if`: jednoduché register-based rozhranie bez burst prenosov
- `axi4_if`: plné AXI rozhranie s podporou burst prenosov, ID a out-of-order komunikácie
- `axi4s_if`: prúdové rozhranie bez adresácie, vhodné na vysokorýchlostný prenos dát

Každé rozhranie obsahuje `modport` definície pre `master` a `slave`, ktoré
uľahčujú správne použitie a smerovanie signálov v dizajne.

## Parametre

- `[in]`: ADDR_WIDTH    Šírka adresy (v bitoch)
- `[in]`: DATA_WIDTH    Šírka dátovej zbernice (v bitoch)
- `[in]`: ID_WIDTH      Šírka identifikátora transakcie (len AXI4/AXI4-Stream)
- `[in]`: LEN_WIDTH     Šírka poľa dĺžky burst prenosu (AXI4)
- `[in]`: STRB_WIDTH    Šírka byte-masky (WSTRB, TKEEP)
- `[in]`: USER_WIDTH    Šírka TUSER signálu (AXI4-Stream)
- `[in]`: DEST_WIDTH    Šírka TDEST signálu (AXI4-Stream)

## Vstupy (input)

| Názov | Popis |
|-------|--------|
| `ACLK` | Hodinový signál (všetky rozhrania) |
| `ARESETn` | Asynchrónny reset, aktívny v nule |

## Príklady použitia

```systemverilog
// Použitie v module:
module my_axi_peripheral (
input  logic clk,
input  logic rstn,
...
);
import axi_pkg::*;
axi4lite_if #(.ADDR_WIDTH(16), .DATA_WIDTH(32)) axi_if (
.ACLK(clk),
.ARESETn(rstn)
);

// Prístup k modportom:
assign axi_if.AWADDR = ...;
...
endmodule
```

