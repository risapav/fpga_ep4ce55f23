Perfektne! Poďme si teraz vytvoriť:

---

### ✅ **Testbench pre `vga_pixel_fetch` modul**

* Bude generovať `h_counter`, `v_counter` ako VGA časovač
* Sledujeme, že `rgb_out` sa objaví počas `de_out = 1`
* Použijeme **GTKWave** na vizualizáciu

---

## 📁 Súbory

### 1. `vga_pixel_fetch.sv`

(použi modul z predchádzajúcej odpovede – vlož ho do tohto súboru)

---

### 2. `tb_vga_pixel_fetch.sv` – Testbench

```systemverilog
`timescale 1ns / 1ps

module tb_vga_pixel_fetch;

  // Parametre VGA časovania
  parameter H_SYNC   = 96;
  parameter H_BP     = 48;
  parameter H_ACTIVE = 640;
  parameter H_FP     = 16;
  parameter H_TOTAL  = H_SYNC + H_BP + H_ACTIVE + H_FP;

  parameter V_SYNC   = 2;
  parameter V_BP     = 33;
  parameter V_ACTIVE = 480;
  parameter V_FP     = 10;
  parameter V_TOTAL  = V_SYNC + V_BP + V_ACTIVE + V_FP;

  // Signály
  logic clk = 0;
  logic rstn = 1;
  logic [$clog2(H_TOTAL)-1:0] h_counter = 0;
  logic [$clog2(V_TOTAL)-1:0] v_counter = 0;

  logic [7:0] rgb_r, rgb_g, rgb_b;
  logic de_out;

  // Hodiny
  always #5 clk = ~clk; // 100 MHz

  // Inštancia modulu
  vga_pixel_fetch #(
    .H_SYNC(H_SYNC), .H_BP(H_BP), .H_ACTIVE(H_ACTIVE), .H_FP(H_FP),
    .V_SYNC(V_SYNC), .V_BP(V_BP), .V_ACTIVE(V_ACTIVE), .V_FP(V_FP)
  ) dut (
    .clk(clk),
    .rstn(rstn),
    .h_counter(h_counter),
    .v_counter(v_counter),
    .rgb_r(rgb_r),
    .rgb_g(rgb_g),
    .rgb_b(rgb_b),
    .de_out(de_out)
  );

  // VGA časovač
  always_ff @(posedge clk) begin
    if (h_counter == H_TOTAL - 1) begin
      h_counter <= 0;
      if (v_counter == V_TOTAL - 1)
        v_counter <= 0;
      else
        v_counter <= v_counter + 1;
    end else begin
      h_counter <= h_counter + 1;
    end
  end

  // Inicializácia a VCD dump
  initial begin
    $dumpfile("tb_vga_pixel_fetch.vcd");
    $dumpvars(0, tb_vga_pixel_fetch);

    // Simulácia krátkeho úseku (nie celý rámec)
    #100_000 $finish;
  end

endmodule
```

---

## ▶️ Spustenie simulácie

```bash
iverilog -g2012 -o sim.vvp vga_pixel_fetch.sv tb_vga_pixel_fetch.sv
vvp sim.vvp
```

---

## 📊 Otvorenie v GTKWave

```bash
gtkwave tb_vga_pixel_fetch.vcd
```

### Tipy čo pridať do GTKWave:

* `clk`
* `h_counter`, `v_counter`
* `de_out`
* `rgb_r`, `rgb_g`, `rgb_b`

---

## ✅ Čo uvidíš

* `de_out` bude HIGH len počas aktívnej oblasti (640×480)
* `rgb_*` výstupy budú platné presne pri `de_out = 1`
* Rýchla vizuálna kontrola, že oneskorenie je správne synchronizované

---

Ak chceš, môžeme to ďalej rozšíriť o:

* **farebné gradienty**
* **RAM načítavanú zo súboru**
* **výstup BMP obrázku** zo simulácie

Stačí povedať „pokračuj“ alebo si vybrať smer.
