Výborne! Poďme teda doplniť **serializáciu TMDS dát**. V HDMI/DVI výstupe totiž TMDS kanály prenášajú 10-bitové TMDS slová **serializované** na 10× vyššej frekvencii než pixel clock.

---

## 🧩 Cieľ: TMDS serializácia

### 🔄 TMDS 10-bit → 1-bit serializované dáta

Pre **každý kanál (R, G, B)**:

* vstup: 10-bit TMDS slovo (mení sa raz za pixel clock, napr. 25 MHz)
* výstup: sériový tok bitov (mení sa 10× rýchlejšie, napr. 250 MHz)

---

## 🔧 1. TMDS serializér – `tmds_serializer.sv`

```systemverilog
// tmds_serializer.sv
module tmds_serializer (
    input  logic        pix_clk,       // pixel clock (napr. 25 MHz)
    input  logic        ser_clk,       // serial clock (napr. 250 MHz)
    input  logic        rst,
    input  logic [9:0]  tmds_word,     // 10-bit TMDS kód
    output logic        tmds_serial    // výstupný bit (1-bit)
);

    logic [9:0] shift_reg;
    logic [3:0] bit_cnt;

    always_ff @(posedge pix_clk or posedge rst) begin
        if (rst) begin
            shift_reg <= 10'd0;
        end else begin
            shift_reg <= tmds_word;
        end
    end

    always_ff @(posedge ser_clk or posedge rst) begin
        if (rst) begin
            bit_cnt     <= 4'd0;
            tmds_serial <= 1'b0;
        end else begin
            tmds_serial <= shift_reg[bit_cnt];
            bit_cnt     <= (bit_cnt == 9) ? 4'd0 : bit_cnt + 1;
        end
    end

endmodule
```

---

## ⏱️ 2. PLL (alebo clocking) – generovanie `ser_clk`

V Quartuse:

* **vstupný clock**: 25 MHz (pixel clock)
* **výstupný clock**: 250 MHz (serial clock)

Použi `ALTPLL` alebo `Clocking Wizard` a vygeneruj 10× rýchlejší clock. Modul bude mať:

```systemverilog
module hdmi_pll (
    input  logic inclk,        // 25 MHz
    output logic pix_clk,      // 25 MHz
    output logic ser_clk       // 250 MHz
);
```

Môžem ti rovno vygenerovať .v súbor pre MAX10, ak chceš.

---

## 🔌 3. Kompletný výstupný modul – 3 TMDS kanály + serializér

```systemverilog
module hdmi_output (
    input  logic        clk_pix,     // 25 MHz
    input  logic        clk_ser,     // 250 MHz
    input  logic        rst,
    input  logic [9:0]  tmds_ch0,    // Blue
    input  logic [9:0]  tmds_ch1,    // Green
    input  logic [9:0]  tmds_ch2,    // Red
    output logic        hdmi_out_0,  // serial out
    output logic        hdmi_out_1,
    output logic        hdmi_out_2
);

    // Serializers pre každý kanál
    tmds_serializer ser0 (
        .pix_clk(clk_pix),
        .ser_clk(clk_ser),
        .rst(rst),
        .tmds_word(tmds_ch0),
        .tmds_serial(hdmi_out_0)
    );

    tmds_serializer ser1 (
        .pix_clk(clk_pix),
        .ser_clk(clk_ser),
        .rst(rst),
        .tmds_word(tmds_ch1),
        .tmds_serial(hdmi_out_1)
    );

    tmds_serializer ser2 (
        .pix_clk(clk_pix),
        .ser_clk(clk_ser),
        .rst(rst),
        .tmds_word(tmds_ch2),
        .tmds_serial(hdmi_out_2)
    );

endmodule
```

---

## 🖨️ Výstup z FPGA do HDMI

### 🧷 Typické HDMI výstupy:

| HDMI signál        | Pripoj na FPGA pin |
| ------------------ | ------------------ |
| TMDS Clock+        | clock\_p           |
| TMDS Clock−        | clock\_n           |
| TMDS Data0 (Blue)  | hdmi\_out\_0       |
| TMDS Data1 (Green) | hdmi\_out\_1       |
| TMDS Data2 (Red)   | hdmi\_out\_2       |

🔧 Použi **differential output buffer** (napr. `ALTDDIO` alebo `ALTIOBUF`) pre `+/-` výstupy, ak ideš cez HDMI konektor.

---

## ✅ Pokračovanie

Chceš teraz:

* ⚙️ **Vložiť PLL generátor pre Quartus (MAX10)?**
* 🧪 **Vytvoriť testbench** pre TMDS serializer?
* 📦 Kompletizovať **HDMI top modul** (InfoFrame + TMDS + výstup)?
* 📁 Pripraviť celý projekt pre Quartus (ZIP)?

Alebo si želáš konkrétne rozšírenie iného bloku?
