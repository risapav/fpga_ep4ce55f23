Skvelá otázka! Spojenie **AXI4-Stream (AXIS)** do **HDMI výstupu** je veľmi praktické v SoC dizajne (napr. v Xilinx Zynq alebo Intel FPGA + Nios). Povedzme si, **ako prepojiť AXIS video zdroj** do HDMI výstupu cez TMDS.

---

## 🧩 Prepojenie AXI4-Stream → HDMI: koncept

### AXI4-Stream video:

AXI4-Stream pre video prenáša dáta po radoch a pixeloch:

| Signál   | Popis                                 |
| -------- | ------------------------------------- |
| `tdata`  | farebné dáta (napr. RGB888)           |
| `tvalid` | platné dáta                           |
| `tready` | HDMI prijíma dáta                     |
| `tlast`  | koniec riadku (EOL = End Of Line)     |
| `tuser`  | začiatok rámca (SOF = Start Of Frame) |

---

## 🛠️ Krok za krokom: AXIS → HDMI výstup

### 1. 🖼️ AXI-Stream Framebuffer Receiver

Uložíš streamovaný obraz do framebufferu (alebo použiješ **priame passtrough**, ak latencia nevadí).

```systemverilog
module axis_to_rgb (
    input  logic        clk,
    input  logic        rst,

    // AXIS
    input  logic [23:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,
    input  logic        s_axis_tuser,

    // RGB výstup na každý pixel clock
    output logic [7:0]  rgb_r,
    output logic [7:0]  rgb_g,
    output logic [7:0]  rgb_b,
    output logic        rgb_valid,
    input  logic        rgb_ready
);
    assign s_axis_tready = rgb_ready;
    assign rgb_r    = s_axis_tdata[23:16];
    assign rgb_g    = s_axis_tdata[15:8];
    assign rgb_b    = s_axis_tdata[7:0];
    assign rgb_valid = s_axis_tvalid;

endmodule
```

---

### 2. 🎨 RGB → TMDS kódovanie

Použiješ modul, ktorý RGB hodnoty prevedie na 10-bit TMDS výstupy:

```systemverilog
rgb2tmds encoder (
    .clk_pixel(clk_pixel),
    .rst(rst),
    .rgb_r(rgb_r),
    .rgb_g(rgb_g),
    .rgb_b(rgb_b),
    .de(rgb_valid),        // data enable
    .hs(hsync),            // synchronizácia
    .vs(vsync),
    .tmds_r(tmds_red),
    .tmds_g(tmds_green),
    .tmds_b(tmds_blue)
);
```

---

### 3. 📤 TMDS → Serializér

Použiješ 3× `tmds_serializer` ako vyššie, ktoré premenia TMDS slová na sériové výstupy pre HDMI konektor.

---

## 🔄 Celá cesta dát

```
[AXIS Video]
   |
   V
[axis_to_rgb]
   |
   V
[TMDS Encoder (rgb2tmds)]
   |
   V
[TMDS Serializer]
   |
   V
[HDMI výstup (TMDS lines)]
```

---

## 🔌 Voliteľné časovanie a kontrola

HDMI potrebuje:

* správne generované `hsync`, `vsync`, `de` signály
* správne počítanie pixelov a riadkov

Môžeš doplniť generátor synchronizačných signálov (`video_timing_generator`), ktorý ich vytvorí podľa rozlíšenia (napr. 640×480 @60Hz, 800×600, atď.)

---

## 🧪 Čo môžem doplniť?

* Pripraviť celý AXIS-to-HDMI top modul?
* Dopísať konkrétny `rgb2tmds` kódovač?
* Vložiť FIFO medzi AXIS a HDMI pre timing?
* Simuláciu/testbench?

Daj vedieť, čo by si chcel rozpracovať alebo otestovať.
