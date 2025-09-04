Skvelé – ideme teda **rozšíriť výstup** o TMDS (Transition-Minimized Differential Signaling), aby sme mohli **InfoFrames (AVI alebo SPD)** reálne posielať po HDMI linke. V tomto kroku:

---

## 🎦 Cieľ: HDMI výstup – TMDS kódovanie

Budeme implementovať:

### ✅ Výstupný blok:

* TMDS encoder pre 8-bitové dáta (RGB a kontrolné info)
* Serializácia dát (10-bit TMDS na diferenciálny výstup)
* Prepojenie infoframe výstupu na HDMI kanál (napr. pomocou „data island“)

---

### 🧩 1. TMDS Encoder – modul (SystemVerilog)

Tento modul zakóduje 8-bitové dáta do 10-bitového TMDS formátu:

```systemverilog
// tmds_encoder.sv
module tmds_encoder (
    input  logic         clk,
    input  logic         rst,
    input  logic [7:0]   data_in,
    input  logic         c0,        // control bits for blanking
    input  logic         c1,
    input  logic         de,        // data enable
    output logic [9:0]   tmds_out
);

    logic [3:0] ones_count;
    logic [8:0] q_m;
    logic       disparity;
    logic [9:0] code;

    // Compute number of ones
    always_comb begin
        ones_count = 0;
        for (int i = 0; i < 8; i++) begin
            ones_count += data_in[i];
        end
    end

    // XOR/XNOR encoding for transition minimization
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            q_m       <= 0;
            disparity <= 0;
        end else begin
            q_m[0] = data_in[0];
            for (int i = 1; i < 8; i++) begin
                if (ones_count > 4 || (ones_count == 4 && data_in[0] == 0))
                    q_m[i] = q_m[i-1] ~^ data_in[i];
                else
                    q_m[i] = q_m[i-1] ^ data_in[i];
            end
            q_m[8] = (ones_count > 4 || (ones_count == 4 && data_in[0] == 0)) ? 0 : 1;
        end
    end

    // Balance disparity and output 10-bit TMDS code
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            code <= 10'd0;
        end else begin
            if (!de) begin
                // Control symbols for blanking intervals
                case ({c1, c0})
                    2'b00: code <= 10'b1101010100;
                    2'b01: code <= 10'b0010101011;
                    2'b10: code <= 10'b0101010100;
                    2'b11: code <= 10'b1010101011;
                endcase
            end else begin
                // TMDS-encoded pixel or data byte
                code <= {q_m[8], q_m[7:0], q_m[8] ^ disparity};
            end
        end
    end

    assign tmds_out = code;

endmodule
```

---

### ⚙️ 2. InfoFrame na TMDS výstup

**Prepojenie infoframe\_generator → TMDS\_encoder:**

```systemverilog
module infoframe_tmds_output (
    input  logic        clk,
    input  logic        rst,
    input  logic        select_infoframe, // 0: SPD, 1: AVI
    output logic [9:0]  tmds_channel_0,   // Blue / Control
    output logic [9:0]  tmds_channel_1,   // Green / Data island
    output logic [9:0]  tmds_channel_2    // Red / Not used here
);

    logic        info_valid;
    logic [7:0]  info_data;
    logic        de;     // data enable for TMDS
    logic        c0, c1; // control bits

    // Generate infoframe (e.g., one byte per clk)
    infoframe_top if_top (
        .clk(clk),
        .rst(rst),
        .select_infoframe(select_infoframe),
        .infoframe_data(info_data),
        .infoframe_valid(info_valid)
    );

    // Simplified DE logic (true only when infoframe is being sent)
    assign de = info_valid;
    assign c0 = 0;
    assign c1 = 0;

    // Use TMDS encoder for channel 1 (Green)
    tmds_encoder enc_green (
        .clk(clk),
        .rst(rst),
        .data_in(info_data),
        .c0(c0),
        .c1(c1),
        .de(de),
        .tmds_out(tmds_channel_1)
    );

    // Control channels (simplified blanking)
    assign tmds_channel_0 = (de) ? 10'b0000000000 : 10'b1101010100;
    assign tmds_channel_2 = 10'b0000000000; // not used in this mode

endmodule
```

---

### 🧪 3. Rozšírenie projektu

Do `infoframe.qsf` pridaj nové súbory:

```tcl
set_global_assignment -name VERILOG_FILE tmds_encoder.sv
set_global_assignment -name VERILOG_FILE infoframe_tmds_output.sv
```

A nastav piny pre HDMI:

| Pin | Funkcia           | Poznámka        |
| --- | ----------------- | --------------- |
| 30  | TMDS Channel 0    | Blue or Control |
| 31  | TMDS Channel 1    | Green           |
| 32  | TMDS Channel 2    | Red or Unused   |
| 33  | Clock (TMDS clk+) | 25-165 MHz      |

---

## 🔧 Čo môžeme doplniť ďalej?

* 🧵 Serializáciu (TMDS 10-bit na 250MHz linku)
* ⏱️ TMDS taktovanie – PLL na 250 MHz
* 🧪 Simuláciu HDMI InfoFrame s CRC8 + TMDS
* 🖥️ Výstup pre DVI/HDMI displej (napr. DE10-Lite, MAX10 HDMI shield)

---

Chceš teraz:

* ➕ Pridať **PLL/serializer**?
* 💾 Vytvoriť kompletný Quartus ZIP projekt?
* 🧪 Generovať testbench pre TMDS výstup?
* 📸 Ukázať ako sa InfoFrame prenáša vo „data island“ HDMI linky?

Alebo upraviť niektorý krok?
