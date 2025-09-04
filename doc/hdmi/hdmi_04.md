Super, pokračujme teda audio infoframe – je to ďalší dôležitý HDMI infoframe pre audio parametre (formát, počet kanálov, vzorkovanie).

Tu je presný generátor **HDMI Audio InfoFrame** podľa HDMI 1.4b špecifikácie, komplet s headerom, payload a CRC.

---

## Presný generátor HDMI Audio InfoFrame v SystemVerilogu

```systemverilog
// audio_infoframe.sv
// HDMI Audio InfoFrame generátor so správnym formátom a CRC

module audio_infoframe #(
    parameter byte AUDIO_CODING_TYPE = 4'd1,  // 0=PCM, 1=AC-3, 2=MPEG1, ...
    parameter byte CHANNEL_COUNT = 4'd2,      // počet audio kanálov (1-8)
    parameter byte SAMPLE_SIZE = 3'd2,        // 0=16bit, 1=20bit, 2=24bit
    parameter byte SAMPLE_FREQUENCY = 4'd4    // 4=48kHz (iný podľa špecifikácie)
)(
    input  logic clk,
    input  logic enable,
    output logic [7:0] header [0:3],  // typ, ver, dĺžka, CRC
    output logic [7:0] payload [0:9]  // 10 bajtov payload
);

    localparam byte INFOFRAME_TYPE = 8'h84;    // Audio InfoFrame typ
    localparam byte INFOFRAME_VERSION = 8'h01; // verzia 1
    localparam byte INFOFRAME_LENGTH = 8'd10;  // dĺžka payload 10 bajtov

    // Payload polia podľa HDMI 1.4b:
    // Byte0: Audio Format Code (4b), Reserved (4b)
    // Byte1: Channel Count (4b) + Reserved (4b)
    // Byte2: Sampling Frequency (4b) + Sample Size (3b) + Reserved(1b)
    // Ostatné bajty sú rezerva, set na 0

    always_ff @(posedge clk) begin
        if (enable) begin
            payload[0] <= {AUDIO_CODING_TYPE[3:0], 4'b0000};
            payload[1] <= {CHANNEL_COUNT[3:0], 4'b0000};
            payload[2] <= {SAMPLE_FREQUENCY[3:0], SAMPLE_SIZE[2:0], 1'b0};
            payload[3] <= 8'd0;
            payload[4] <= 8'd0;
            payload[5] <= 8'd0;
            payload[6] <= 8'd0;
            payload[7] <= 8'd0;
            payload[8] <= 8'd0;
            payload[9] <= 8'd0;
        end
    end

    // CRC8 funkcia - rovnaká ako v AVI infoframe module
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
            byte crc_data [0:12];
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

### Čo to robí?

* Vytvára 10-bajtový payload s audio formátom, počtom kanálov, vzorkovacou frekvenciou a vzorkovacou hĺbkou.
* Vypočíta CRC pre header + payload.
* Header obsahuje typ (0x84), verziu a dĺžku, plus CRC.

---

Ak chceš, môžem spraviť ešte:

* SPD InfoFrame generátor (informácie o zdroji, názov zariadenia)
* Packet picker, ktorý podľa požiadavky vyberá, ktorý infoframe generovať a vysiela
* Testbench na simuláciu týchto infoframov

Chceš niečo z toho? Alebo chceš rovno modul na multiplexovanie a vysielanie infoframov v rámci HDMI linky?
