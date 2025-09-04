Super! Pokračujme teda v **rozšírení** systému. Navrhujem nasledovné kroky:

---

## ✅ CIEĽ: KOMPLEXNÝ GENERÁTOR HDMI INFOFRAMES

Budeme postupovať v týchto krokoch:

### 1. ✅ Už máme:

* `spd_infoframe_generator.sv`
* `crc8_generator.sv`
* `infoframe_top.sv` (ktorý generuje kompletný SPD infoframe)

---

### 2. 🆕 Teraz pridáme:

#### ✅ `avi_infoframe_generator.sv`

→ Generuje payload pre AVI InfoFrame (typ 0x82)

#### ✅ Rozšírený `infoframe_top.sv`

→ Umožní výber typu InfoFramu (AVI alebo SPD)

---

### 3. 🛠️ **Rozšírený `infoframe_top.sv`** s výberom medzi AVI a SPD

Pridáme vstup `select_infoframe`, ktorý určí, ktorý InfoFrame sa má generovať.

```systemverilog
module infoframe_top #(
    parameter SPD_VENDOR_NAME = "OpenAI    ",
    parameter SPD_PRODUCT_DESC = "HDMI Gen Example  ",
    parameter SPD_SOURCE_DEVICE = 8'h01
)(
    input logic clk,
    input logic rst_n,
    input logic select_infoframe, // 0 = SPD, 1 = AVI

    output logic [7:0] infoframe_data [0:31],
    output logic       infoframe_valid
);

    // --- SPD wires ---
    logic [7:0] spd_payload [0:26];
    logic       spd_valid;

    // --- AVI wires ---
    logic [7:0] avi_payload [0:13];
    logic       avi_valid;

    // --- CRC input ---
    logic [7:0] crc_input [0:29];
    logic [7:0] crc8;

    // === SPD Generator ===
    spd_infoframe_generator #(
        .VENDOR_NAME(SPD_VENDOR_NAME),
        .PRODUCT_DESC(SPD_PRODUCT_DESC),
        .SOURCE_DEVICE(SPD_SOURCE_DEVICE)
    ) spd_gen (
        .clk(clk),
        .rst_n(rst_n),
        .payload(spd_payload),
        .valid(spd_valid)
    );

    // === AVI Generator ===
    avi_infoframe_generator avi_gen (
        .clk(clk),
        .rst_n(rst_n),
        .payload(avi_payload),
        .valid(avi_valid)
    );

    // === CRC8 Calculation ===
    always_comb begin
        // HEADER
        crc_input[0] = select_infoframe ? 8'h82 : 8'h83; // AVI : SPD
        crc_input[1] = 8'h02; // version
        crc_input[2] = select_infoframe ? 8'h0D : 8'h19;

        if (select_infoframe) begin
            for (int i = 0; i < 13; i++)
                crc_input[i + 3] = avi_payload[i];
            for (int i = 16; i < 30; i++) // pad unused
                crc_input[i] = 8'h00;
        end else begin
            for (int i = 0; i < 26; i++)
                crc_input[i + 3] = spd_payload[i];
            for (int i = 29; i < 30; i++)
                crc_input[i] = 8'h00;
        end
    end

    crc8_generator crc_calc (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(crc_input),
        .crc_out(crc8)
    );

    // === Final output ===
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            infoframe_valid <= 0;
        end else if ((select_infoframe && avi_valid) || (!select_infoframe && spd_valid)) begin
            infoframe_data[0] <= crc_input[0]; // Type
            infoframe_data[1] <= crc_input[1]; // Version
            infoframe_data[2] <= crc_input[2]; // Length
            infoframe_data[3] <= crc8;

            if (select_infoframe) begin
                for (int i = 0; i < 13; i++)
                    infoframe_data[i + 4] <= avi_payload[i];
                for (int i = 17; i < 32; i++)
                    infoframe_data[i] <= 8'h00;
            end else begin
                for (int i = 0; i < 26; i++)
                    infoframe_data[i + 4] <= spd_payload[i];
                for (int i = 30; i < 32; i++)
                    infoframe_data[i] <= 8'h00;
            end

            infoframe_valid <= 1;
        end else begin
            infoframe_valid <= 0;
        end
    end

endmodule
```

---

## 📦 `avi_infoframe_generator.sv`

Tu je príklad základného AVI InfoFrame generatora (typ 0x82):

```systemverilog
module avi_infoframe_generator (
    input  logic clk,
    input  logic rst_n,
    output logic [7:0] payload [0:13],
    output logic       valid
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid <= 0;
        end else begin
            // Minimal AVI payload
            payload[0]  <= 8'h10; // Color space (RGB), scan info
            payload[1]  <= 8'h00;
            payload[2]  <= 8'h00; // Aspect ratio
            payload[3]  <= 8'h00;
            payload[4]  <= 8'h00; // VIC
            payload[5]  <= 8'h00;
            payload[6]  <= 8'h00;
            payload[7]  <= 8'h00;
            payload[8]  <= 8'h00;
            payload[9]  <= 8'h00;
            payload[10] <= 8'h00;
            payload[11] <= 8'h00;
            payload[12] <= 8'h00;
            payload[13] <= 8'h00;

            valid <= 1;
        end
    end

endmodule
```

---

## ➕ Ďalšie možnosti:

* 🧪 Testbench: môžeme napísať simuláciu pre overenie CRC8 a dát.
* 📦 Pridať ďalšie typy InfoFrames (Audio, Vendor Specific).
* 🎦 Pripojiť k TMDS video pipeline (ak smerujeme k reálnemu HDMI)

---

Chceš teraz:

🔸 A) Doplniť testbench a simuláciu CRC8?
🔸 B) Pokračovať s TMDS kódovaním HDMI výstupu?
🔸 C) Pridať ďalší InfoFrame typ (napr. Audio)?
🔸 D) Generovať Quartus-ready projekt (.qsf, pinmap atď)?

Vyber, čo je ďalší cieľ a ideme na to.
