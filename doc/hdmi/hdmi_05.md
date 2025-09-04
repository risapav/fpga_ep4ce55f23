Jasné, poďme na **SPD InfoFrame** — ten slúži na odoslanie textovej informácie o zdroji HDMI (napr. názov zariadenia, výrobca). V HDMI 1.4b špecifikácii má pevne danú štruktúru a dĺžku (27 bajtov payload).

---

## SPD InfoFrame generátor v SystemVerilogu

```systemverilog
// spd_infoframe.sv
// HDMI Source Product Description (SPD) InfoFrame generátor podľa HDMI 1.4b

module spd_infoframe #(
    parameter string VENDOR_NAME = "Unknown ",    // 8 znakov (ASCII)
    parameter string PRODUCT_DESCRIPTION = "FPGA HDMI Source    "  // 16 znakov (ASCII)
)(
    input  logic clk,
    input  logic enable,
    output logic [7:0] header [0:3],  // typ, verzia, dĺžka, CRC
    output logic [7:0] payload [0:26] // 27 bajtov payload
);

    localparam byte INFOFRAME_TYPE = 8'h83;   // SPD InfoFrame type
    localparam byte INFOFRAME_VERSION = 8'h01;
    localparam byte INFOFRAME_LENGTH = 8'd27;

    // Payload štruktúra podľa HDMI 1.4b:
    // Byte 0: Vendor Name (8 ASCII bajtov)
    // Byte 8: Product Description (16 ASCII bajtov)
    // Byte 24: Source Device Information (1 bajt), nastavíme na 0x00
    // Byte 25-26: Rezerva (nastavené na 0)

    byte vendor_name_bytes[0:7];
    byte product_desc_bytes[0:15];

    // Pomocná funkcia na prevod stringu do ASCII bajtov s doplnením nulami
    function automatic void string_to_bytes(input string str, output byte bytes[], int max_len);
        int i;
        for (i=0; i<max_len; i++) begin
            if (i < str.len())
                bytes[i] = str.getc(i);
            else
                bytes[i] = 8'h20; // Nahradiť medzerou ak je menej znakov
        end
    endfunction

    // CRC8 funkcia ako predtým
    function automatic byte crc8(input byte data [], input int length);
        byte crc;
        int i, j;
        crc = 8'h00;
        for (i=0; i<length; i++) begin
            crc ^= data[i];
            for (j=0; j<8; j++) begin
                if (crc[7])
                    crc = (crc << 1) ^ 8'h07;
                else
                    crc <<= 1;
            end
        end
        return crc;
    endfunction

    always_ff @(posedge clk) begin
        if (enable) begin
            string_to_bytes(VENDOR_NAME, vendor_name_bytes, 8);
            string_to_bytes(PRODUCT_DESCRIPTION, product_desc_bytes, 16);

            // Naplnenie payloadu
            for (int i=0; i<8; i++) payload[i] <= vendor_name_bytes[i];
            for (int i=0; i<16; i++) payload[8+i] <= product_desc_bytes[i];
            payload[24] <= 8'h00;    // Source Device Information
            payload[25] <= 8'h00;    // Reserved
            payload[26] <= 8'h00;    // Reserved

            // Naplniť header
            header[0] <= INFOFRAME_TYPE;
            header[1] <= INFOFRAME_VERSION;
            header[2] <= INFOFRAME_LENGTH;

            // Vypočítať CRC cez header + payload
            byte crc_data [0:30];
            crc_data[0] = INFOFRAME_TYPE;
            crc_data[1] = INFOFRAME_VERSION;
            crc_data[2] = INFOFRAME_LENGTH;
            for (int i=0; i<INFOFRAME_LENGTH; i++) crc_data[3+i] = payload[i];

            header[3] <= crc8(crc_data, INFOFRAME_LENGTH + 3);
        end
    end
endmodule
```

---

### Vysvetlenie

* **Typ infoframe** je 0x83 pre SPD.
* **Payload** je 27 bajtov: 8 bajtov vendor name, 16 bajtov product description, 1 bajt device info + 2 bajty rezervy.
* **CRC8** sa počíta cez header + payload.
* Parameterizujeme reťazce, ktoré sa prekonvertujú na ASCII s doplnením medzier na fixnú dĺžku.

---

Ak chceš, môžeme pridať aj:

* Multiplexovanie týchto infoframov spolu s audio, video a inými infoframami.
* Ovládanie vysielania infoframov podľa HDMI špecifikácie (intervaly, reset, atď).
* Testbench pre overenie.

Chceš pokračovať týmto smerom? Alebo máš ďalšie špecifické požiadavky?
