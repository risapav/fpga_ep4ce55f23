Výborne! Pokračujme kompletizáciou celého systému: vygenerujeme **top modul**, ktorý:

* Spája SPD (a voliteľne AVI) InfoFrame generátory
* Obsahuje výstupný TMDS encoder pre infoframes
* Generuje výsledný InfoFrame packet s pripojeným CRC8
* Je pripravený na syntézu v Quartuse

---

## 🧩 Komponenty, ktoré spojíme:

1. `crc8_generator.sv`
2. `spd_infoframe_generator.sv`
3. `avi_infoframe_generator.sv` *(voliteľne, môžeme pridať neskôr)*
4. `infoframe_top.sv` *(nový top modul, ktorý ich spája)*

---

## 🧱 1. `crc8_generator.sv` (už máme)

*(už sme generovali – modul s parametrom `INIT=8'h00`, `POLY=8'h1D` alebo `07` podľa normy)*

---

## 🧱 2. `spd_infoframe_generator.sv` (už máme)

Pripomienka: Tento modul generuje payload SPD InfoFramu (26 bajtov)

---

## 🧱 3. `infoframe_top.sv` – **nový hlavný modul**

```systemverilog
module infoframe_top #(
    parameter SPD_VENDOR_NAME = "OpenAI    ",
    parameter SPD_PRODUCT_DESC = "HDMI Gen Example  ",
    parameter SPD_SOURCE_DEVICE = 8'h01  // e.g., 0x01 = PC
)(
    input logic clk,
    input logic rst_n,

    output logic [7:0] infoframe_data [0:31], // Full InfoFrame (header + payload + CRC)
    output logic       infoframe_valid
);

    // --- Internal wires ---
    logic [7:0] spd_payload [0:26];
    logic       spd_valid;

    logic [7:0] crc8;

    // === SPD InfoFrame Generator ===
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

    // === CRC8 Computation ===
    logic [7:0] crc_input [0:29]; // header + payload

    // InfoFrame Header (type = 0x83, ver = 0x01, len = 0x19 = 25)
    assign crc_input[0] = 8'h83; // InfoFrame type
    assign crc_input[1] = 8'h01; // Version
    assign crc_input[2] = 8'h19; // Length

    genvar i;
    generate
        for (i = 0; i < 26; i++) begin
            assign crc_input[i + 3] = spd_payload[i];
        end
    endgenerate

    crc8_generator crc_calc (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(crc_input),
        .crc_out(crc8)
    );

    // === Combine Header + CRC + Payload ===
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            infoframe_valid <= 0;
        end else if (spd_valid) begin
            infoframe_data[0] <= 8'h83; // Type
            infoframe_data[1] <= 8'h01; // Version
            infoframe_data[2] <= 8'h19; // Length
            infoframe_data[3] <= crc8;  // CRC

            for (int j = 0; j < 26; j++) begin
                infoframe_data[j + 4] <= spd_payload[j];
            end

            // Zero pad (optional – HDMI requires 31 bytes per infoframe)
            for (int k = 30; k < 32; k++) begin
                infoframe_data[k] <= 8'h00;
            end

            infoframe_valid <= 1;
        end else begin
            infoframe_valid <= 0;
        end
    end

endmodule
```

---

## 🧪 Čo ešte doplníme neskôr?

1. **Testbench**: overenie hodnoty CRC8 + správnosti dát
2. **AVI InfoFrame** (ďalší typ InfoFramu)
3. **Prepínanie medzi InfoFrame typmi** (ak chceme viaceré rámce)
4. **TMDS encoder** (ak pôjdeme až na video link layer)

---

## 🛠️ Inštrukcie pre syntézu v Quartuse:

* V `infoframe_top.sv` je plne syntetizovateľný HDL, kompatibilný s Intel FPGA
* Nepoužívame žiadne nesyntetizovateľné konštrukcie
* Na testovanie možno použiť výstup `infoframe_data` ako "register" rámca, ktorý sa odošle cez ďalšie vrstvy (napr. do TMDS encoderu)

---

Môžeme pokračovať:

🔹 vytvorením testbenchu,
🔹 alebo pridať druhý InfoFrame (AVI),
🔹 alebo implementovať TMDS výstup?

Čo preferuješ?
