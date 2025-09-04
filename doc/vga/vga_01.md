Skvelé! Tu je ukážka, **ako načítať VGA pixely z RAM** tak, aby boli správne **synchronizované s `DE`** (display enable).

---

## 🎯 Cieľ:

* Máme rámikovú pamäť (napr. BRAM) s pixelmi (napr. 640×480)
* Chceme, aby v čase, keď `DE=1`, bol na výstupe platný pixel `rgb_out`
* Pamäť má 1-cyklovú latenciu ⇒ musíme adresovať s predstihom

---

## 🧱 Architektúra

### Pamäť:

* Jednoportová RAM
* Adresovaná lineárne (`addr = y * WIDTH + x`)

### Časovanie:

* Signály `h_counter`, `v_counter` určujú pozíciu
* `de` (display enable) indikuje platný pixel

---

## ✅ Princíp synchronizácie

Aby sme mali **RGB dáta pripravené** v cykle, keď `DE = 1`, musíme:

1. Generovať adresu **o 1 cyklus skôr**
2. Zachovať `de` a `rgb_valid` v súlade

---

## 🔧 Kód: VGA pixel fetch z RAM

```systemverilog
module vga_pixel_fetch #(
  parameter H_SYNC   = 96,
  parameter H_BP     = 48,
  parameter H_ACTIVE = 640,
  parameter H_FP     = 16,
  parameter V_SYNC   = 2,
  parameter V_BP     = 33,
  parameter V_ACTIVE = 480,
  parameter V_FP     = 10
)(
  input  logic clk,
  input  logic rstn,

  input  logic [$clog2(H_SYNC+H_BP+H_ACTIVE+H_FP)-1:0] h_counter,
  input  logic [$clog2(V_SYNC+V_BP+V_ACTIVE+V_FP)-1:0] v_counter,

  output logic [7:0] rgb_r,
  output logic [7:0] rgb_g,
  output logic [7:0] rgb_b,
  output logic       de_out
);

  // Interné signály
  logic h_active, v_active, de;

  assign h_active = (h_counter >= H_SYNC + H_BP) &&
                    (h_counter <  H_SYNC + H_BP + H_ACTIVE);
  assign v_active = (v_counter >= V_SYNC + V_BP) &&
                    (v_counter <  V_SYNC + V_BP + V_ACTIVE);
  assign de = h_active && v_active;

  // Predpočítané x/y pozície
  logic [9:0] pixel_x, pixel_y;
  assign pixel_x = h_counter - (H_SYNC + H_BP);
  assign pixel_y = v_counter - (V_SYNC + V_BP);

  // RAM adresa o 1 cyklus skôr
  logic [18:0] fetch_addr;
  assign fetch_addr = pixel_y * H_ACTIVE + pixel_x;

  logic [23:0] rgb_data;  // R[23:16], G[15:8], B[7:0]
  logic        de_d;

  // --- Video RAM (demo len ako register array) ---
  logic [23:0] framebuffer [0:H_ACTIVE*V_ACTIVE-1];

  initial begin
    // demo: modrá obrazovka
    for (int i = 0; i < H_ACTIVE*V_ACTIVE; i++) begin
      framebuffer[i] = {8'h00, 8'h00, 8'hFF}; // RGB = 0,0,255
    end
  end

  // --- Pipeline 1 cyklus: čítanie a DE oneskorenie ---
  always_ff @(posedge clk) begin
    if (de) begin
      rgb_data <= framebuffer[fetch_addr];
    end else begin
      rgb_data <= 24'h0;
    end

    de_d <= de;  // oneskorený DE
  end

  // Výstupy
  assign rgb_r = rgb_data[23:16];
  assign rgb_g = rgb_data[15:8];
  assign rgb_b = rgb_data[7:0];
  assign de_out = de_d;

endmodule
```

---

## 🧪 Simulácia/Overenie

* Simuluj `h_counter`, `v_counter`, a sleduj, že `rgb_out` je platný **presne počas `de_out = 1`**
* Pridaj `$display` alebo `gtkwave` na signály `de`, `de_out`, `rgb_data`

---

## 🔚 Zhrnutie

➡️ Pri VGA výstupe **je potrebné synchronizovať len pri použití latencie**, ako je BRAM, FIFO, alebo pipeliny.

➡️ **Najčastejšie riešenie**: generovať adresy o 1 cyklus skôr, a `de` oneskoriť cez `de_d`.

---

Ak chceš, môžeme spraviť aj testbench a zobraziť výstup v GTKWave. Chceš pokračovať tým?
