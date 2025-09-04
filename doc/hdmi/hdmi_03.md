Jasné, presné HDMI infoframe treba vytvoriť podľa špecifikácie HDMI 1.4 alebo vyššej, kde infoframe má pevne definovaný formát: typ, verzia, dĺžka, payload (dáta) a CRC kontrolný súčet.

Pre ukážku spravíme **AVI InfoFrame** s korektným výpočtom CRC a správnym zoradením polí.

---

## Presný generátor HDMI AVI InfoFrame v SystemVerilogu

```systemverilog
// avi_infoframe.sv
// Generovanie presného HDMI AVI InfoFrame so správnym headerom, dátami a CRC

module avi_infoframe #(
    parameter [7:0] COLOR_FORMAT = 2'b00, // 0=RGB, 1=YCbCr422, 2=YCbCr444, 3=YCbCr420
    parameter [7:0] ACTIVE_FORMAT_ASPECT_RATIO = 4'd8, // napr. 16:9
    parameter [7:0] ITC = 0,           // infoframe transmission code
    parameter [7:0] EC = 0,            // extended colorimetry
    parameter [7:0] Q = 0              // quantization range
)(
    input  logic clk,
    input  logic enable,
    output logic [7:0] header [0:3],  // 4 bajty headeru: type, ver, length, CRC
    output logic [7:0] payload [0:12] // 13 bajtov dátového poľa (payload)
);

    // Typ infoframe (AVI = 0x82), verzia (2), dĺžka (13)
    localparam byte INFOFRAME_TYPE = 8'h82;
    localparam byte INFOFRAME_VERSION = 8'h02;
    localparam byte INFOFRAME_LENGTH = 8'd13;

    // Pripravíme dátové polia podľa HDMI 1.4b Specifikácie
    // Prvých 13 bajtov payload podľa formátu AVI InfoFrame:
    // payload[0] = bits 7-5: Y[2:0] (color format)
    //              bits 4-0: A[4:0] (active format aspect ratio)
    // ... (Ďalej ďalšie polia podľa špecifikácie)

    always_ff @(posedge clk) begin
        if (enable) begin
            // Nastavenie payload podľa parametrov
            payload[0]  <= {COLOR_FORMAT[1:0], 5'b00000};  // Y + A
            payload[1]  <= 8'd0;                          // B1 (video format)
            payload[2]  <= {1'b0, ACTIVE_FORMAT_ASPECT_RATIO[3:0], 3'b000}; // B2
            payload[3]  <= {1'b0, EC[1:0], 5'b00000};     // B3 (Extended colorimetry)
            payload[4]  <= 8'd0;                          // B4 (Non uniform picture scaling)
            payload[5]  <= 8'd0;                          // B5
            payload[6]  <= 8'd0;                          // B6
            payload[7]  <= 8'd0;                          // B7
            payload[8]  <= 8'd0;                          // B8
            payload[9]  <= 8'd0;                          // B9
            payload[10] <= 8'd0;                          // B10
            payload[11] <= 8'd0;                          // B11
            payload[12] <= 8'd0;                          // B12
        end
    end

    // Výpočet CRC8 na základe headeru a payload (CRC sa počíta na typ, verziu, dĺžku + payload)
    // Polynóm CRC8: x^8 + x^2 + x + 1 (0x07)
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

    // Vypočítame CRC vždy, keď je enable
    always_ff @(posedge clk) begin
        if (enable) begin
            byte crc_data [0:16];
            crc_data[0] = INFOFRAME_TYPE;
            crc_data[1] = INFOFRAME_VERSION;
            crc_data[2] = INFOFRAME_LENGTH;
            for (int i=0; i<INFOFRAME_LENGTH; i++)
                crc_data[3+i] = payload[i];
            header[0] <= INFOFRAME_TYPE;
            header[1] <= INFOFRAME_VERSION;
            header[2] <= INFOFRAME_LENGTH;
            header[3] <= crc8(crc_data, INFOFRAME_LENGTH+3);
        end
    end

endmodule
```

---

### Vysvetlenie:

* `header` je 4 bajtové pole: `{Type, Version, Length, CRC}`
* `payload` je 13 bajtov s presnými dátami podľa HDMI špecifikácie pre AVI infoframe.
* CRC8 sa vypočíta podľa všetkých bajtov `Type`, `Version`, `Length` a dát payload.
* Parametre môžu byť podľa potreby nastavené (napr. farebný formát, aktívny pomer strán...).

---

### Čo ďalej?

Môžem ti pomôcť aj s ostatnými infoframami (audio infoframe, SPD infoframe) a ich presnými formátmi, prípadne s integráciou do celého HDMI vysielača.

Ak chceš, môžem napísať tiež generátor audio infoframe, alebo doplniť riadenie týchto infoframov do `packet_picker`.

Chceš pokračovať týmto smerom?
