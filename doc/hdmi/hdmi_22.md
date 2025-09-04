Super! Pokračujme teda kompletizáciou **AXI4-Stream to HDMI** cesty v SystemVerilogu.

Zložíme to do funkčného celku v štyroch hlavných blokoch:

---

### 🧱 **1. Modul: `axis_to_rgb`**

Zabezpečuje prijatie pixelov z AXIS rozhrania a ich konverziu do RGB formátu.

```systemverilog
module axis_to_rgb #(
    parameter DATA_WIDTH = 24  // RGB888
)(
    input  logic                  clk,
    input  logic                  rst,

    // AXI4-Stream interface
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,
    input  logic                  s_axis_tlast,
    input  logic                  s_axis_tuser,

    // Output RGB
    output logic [7:0]            rgb_r,
    output logic [7:0]            rgb_g,
    output logic [7:0]            rgb_b,
    output logic                  rgb_valid
);

    assign s_axis_tready = 1'b1;  // Always ready to accept
    assign rgb_r = s_axis_tdata[23:16];
    assign rgb_g = s_axis_tdata[15:8];
    assign rgb_b = s_axis_tdata[7:0];
    assign rgb_valid = s_axis_tvalid;

endmodule
```

---

### 🎨 **2. Modul: `rgb2tmds`**

Kodér RGB + sync signálov do TMDS kódu.

*(Základná verzia, iba pre 1 kanál – rozšírime podľa potreby)*

```systemverilog
module rgb2tmds (
    input  logic         clk,
    input  logic         rst,
    input  logic [7:0]   data,
    input  logic         c0,     // hsync
    input  logic         c1,     // vsync
    input  logic         de,     // data enable (aktívne pixelové dáta)
    output logic [9:0]   tmds_out
);
    // Implementácia TMDS kódovania (zjednodušená pre prezentáciu)
    // Skutočný TMDS obsahuje rovnováhu jedničiek a núl, invertovanie atď.

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            tmds_out <= 10'b0;
        else if (!de) begin
            // Control data (sync pulses)
            case ({c1, c0})
                2'b00: tmds_out <= 10'b1101010100;
                2'b01: tmds_out <= 10'b0010101011;
                2'b10: tmds_out <= 10'b0101010100;
                2'b11: tmds_out <= 10'b1010101011;
            endcase
        end else begin
            // Simple 8b/10b passthrough (real impl. requires balance)
            tmds_out <= {2'b01, data}; // simplifikovaný TMDS
        end
    end

endmodule
```

---

### 🌀 **3. Modul: `tmds_serializer`**

Serializuje 10-bit TMDS dáta do 1-bitového toku (na vysokom takte, napr. 10× pixel\_clk).

```systemverilog
module tmds_serializer (
    input  logic         clk_serial,  // 10x pixel_clk
    input  logic         clk_pixel,
    input  logic [9:0]   tmds_data,
    output logic         tmds_out
);

    logic [9:0] shift_reg;
    logic [3:0] bit_cnt;

    always_ff @(posedge clk_pixel) begin
        shift_reg <= tmds_data;
        bit_cnt   <= 4'd0;
    end

    always_ff @(posedge clk_serial) begin
        tmds_out <= shift_reg[0];
        shift_reg <= {1'b0, shift_reg[9:1]};
        bit_cnt <= bit_cnt + 1;
    end

endmodule
```

---

### 🧩 **4. Modul: `axis_to_hdmi_top`**

Spája všetky časti – prijíma AXIS a vysiela TMDS na HDMI.

```systemverilog
module axis_to_hdmi_top (
    input  logic         clk_pixel,    // pixel clock
    input  logic         clk_serial,   // 10x pixel clock
    input  logic         rst,

    // AXI-Stream video
    input  logic [23:0]  s_axis_tdata,
    input  logic         s_axis_tvalid,
    input  logic         s_axis_tlast,
    input  logic         s_axis_tuser,

    output logic         tmds_clk_p,
    output logic         tmds_clk_n,
    output logic [2:0]   tmds_data_p,
    output logic [2:0]   tmds_data_n
);

    logic [7:0] r, g, b;
    logic       rgb_valid;

    axis_to_rgb axis_rgb (
        .clk(clk_pixel),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .rgb_r(r),
        .rgb_g(g),
        .rgb_b(b),
        .rgb_valid(rgb_valid)
    );

    logic [9:0] tmds_red, tmds_green, tmds_blue;

    rgb2tmds enc_r (.clk(clk_pixel), .rst(rst), .data(r), .c0(1'b0), .c1(1'b0), .de(rgb_valid), .tmds_out(tmds_red));
    rgb2tmds enc_g (.clk(clk_pixel), .rst(rst), .data(g), .c0(1'b0), .c1(1'b0), .de(rgb_valid), .tmds_out(tmds_green));
    rgb2tmds enc_b (.clk(clk_pixel), .rst(rst), .data(b), .c0(1'b0), .c1(1'b0), .de(rgb_valid), .tmds_out(tmds_blue));

    tmds_serializer ser_r (.clk_serial(clk_serial), .clk_pixel(clk_pixel), .tmds_data(tmds_red), .tmds_out(tmds_data_p[2]));
    tmds_serializer ser_g (.clk_serial(clk_serial), .clk_pixel(clk_pixel), .tmds_data(tmds_green), .tmds_out(tmds_data_p[1]));
    tmds_serializer ser_b (.clk_serial(clk_serial), .clk_pixel(clk_pixel), .tmds_data(tmds_blue), .tmds_out(tmds_data_p[0]));

    assign tmds_clk_p = clk_pixel;
    assign tmds_clk_n = ~clk_pixel;
    assign tmds_data_n = ~tmds_data_p;

endmodule
```

---

## 📌 Zhrnutie

Týmto si dostal:

* kompletný základ pre **prevod AXI-Stream videa do HDMI výstupu** cez TMDS
* môžeš ho rozšíriť o:

  * **video timing generátor (hsync, vsync)**
  * **správne TMDS vyváženie (differential coding)**
  * **PLL na 10× frekvenciu pre serializáciu**
  * **EDID/I2C komunikáciu s monitorom**

---

## 🔧 Môžeme pokračovať:

* Pridať **video timing generator**
* Vložiť FIFO medzi AXIS a RGB
* Doplniť testbench pre simuláciu HDMI
* Rozšíriť na **720p alebo 1080p**

Chceš rozšíriť niektorú z týchto častí?
