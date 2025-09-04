Skvelé, pokračujeme teda s kompletným riešením **SPD InfoFrame** integrovaným do systému, plus návrh, ako ho multiplexovať spolu s inými infoframami (napr. AVI, audio). Navrhnem tiež jednoduchý ovládač pre periodické vysielanie.

---

# 1. SPD InfoFrame modul (už máme, mierne upravím pre lepšiu synthézu a použitie)

```systemverilog
// spd_infoframe.sv
// HDMI Source Product Description (SPD) InfoFrame generátor podľa HDMI 1.4b

module spd_infoframe #(
    parameter string VENDOR_NAME = "Unknown ",          // 8 znakov ASCII, doplnené medzerami
    parameter string PRODUCT_DESCRIPTION = "FPGA HDMI Source    "  // 16 znakov ASCII, doplnené medzerami
)(
    input  logic clk,
    input  logic enable,
    output logic [7:0] header [0:3],   // [type, version, length, CRC]
    output logic [7:0] payload [0:26]  // 27 bajtov payload
);

    localparam byte INFOFRAME_TYPE = 8'h83;
    localparam byte INFOFRAME_VERSION = 8'h01;
    localparam byte INFOFRAME_LENGTH = 8'd27;

    // Pomocná funkcia pre konverziu string->ASCII bytes s paddingom
    function automatic [7:0] get_char(input string str, input int idx);
        if (idx < str.len())
            return str.getc(idx);
        else
            return 8'h20; // medzera
    endfunction

    // CRC8 (polynóm 0x07) pre HDMI infoframe
    function automatic byte crc8(input byte data[], input int length);
        byte crc;
        int i,j;
        crc = 8'h00;
        for (i=0; i<length; i++) begin
            crc ^= data[i];
            for (j=0; j<8; j++) begin
                if (crc[7]) crc = (crc << 1) ^ 8'h07;
                else crc <<= 1;
            end
        end
        return crc;
    endfunction

    byte crc_data [0:30];

    always_ff @(posedge clk) begin
        if (enable) begin
            // Payload: vendor_name (8b)
            for (int i=0; i<8; i++)
                payload[i] <= get_char(VENDOR_NAME, i);

            // Payload: product_description (16b)
            for (int i=0; i<16; i++)
                payload[8+i] <= get_char(PRODUCT_DESCRIPTION, i);

            // Source Device Information + 2 reserved bytes
            payload[24] <= 8'h00;
            payload[25] <= 8'h00;
            payload[26] <= 8'h00;

            // Header fields
            header[0] <= INFOFRAME_TYPE;
            header[1] <= INFOFRAME_VERSION;
            header[2] <= INFOFRAME_LENGTH;

            // Pripravíme data pre CRC (header + payload)
            crc_data[0] = INFOFRAME_TYPE;
            crc_data[1] = INFOFRAME_VERSION;
            crc_data[2] = INFOFRAME_LENGTH;
            for (int i=0; i<INFOFRAME_LENGTH; i++)
                crc_data[3+i] = payload[i];

            header[3] <= crc8(crc_data, INFOFRAME_LENGTH + 3);
        end
    end
endmodule
```

---

# 2. Multiplexor infoframov (SPD + AVI + Audio...)

Predstavme si, že máme iné infoframe moduly (napr. `avi_infoframe`, `audio_infoframe`), ktoré produkujú rovnaký typ výstupu (`header[]` a `payload[]`).

Modul vyberie podľa požiadavky, ktorý infoframe práve vysiela.

```systemverilog
module infoframe_mux (
    input  logic clk,
    input  logic [1:0] select_infoframe, // 0=SPD, 1=AVI, 2=Audio, atď.
    input  logic enable,
    // SPD inputs
    input  logic [7:0] spd_header [0:3],
    input  logic [7:0] spd_payload [0:26],
    // AVI inputs (príklad, dĺžka 13 bajtov)
    input  logic [7:0] avi_header [0:3],
    input  logic [7:0] avi_payload [0:12],
    // Audio inputs (príklad, dĺžka 10 bajtov)
    input  logic [7:0] audio_header [0:3],
    input  logic [7:0] audio_payload [0:9],

    output logic [7:0] out_header [0:3],
    output logic [7:0] out_payload []
);

    // Dĺžka payload pre jednotlivé typy (tu fixne)
    localparam int SPD_LEN = 27;
    localparam int AVI_LEN = 13;
    localparam int AUDIO_LEN = 10;

    // Výstupná dĺžka nech je max 27 (SPD)
    logic [7:0] payload_mux [0:26];

    always_ff @(posedge clk) begin
        if (!enable) begin
            for (int i=0; i<4; i++) out_header[i] <= 8'd0;
            for (int i=0; i<27; i++) payload_mux[i] <= 8'd0;
        end else begin
            case (select_infoframe)
                2'd0: begin // SPD
                    for (int i=0; i<4; i++) out_header[i] <= spd_header[i];
                    for (int i=0; i<SPD_LEN; i++) payload_mux[i] <= spd_payload[i];
                    for (int i=SPD_LEN; i<27; i++) payload_mux[i] <= 8'd0; // clear unused
                end
                2'd1: begin // AVI
                    for (int i=0; i<4; i++) out_header[i] <= avi_header[i];
                    for (int i=0; i<AVI_LEN; i++) payload_mux[i] <= avi_payload[i];
                    for (int i=AVI_LEN; i<27; i++) payload_mux[i] <= 8'd0;
                end
                2'd2: begin // Audio
                    for (int i=0; i<4; i++) out_header[i] <= audio_header[i];
                    for (int i=0; i<AUDIO_LEN; i++) payload_mux[i] <= audio_payload[i];
                    for (int i=AUDIO_LEN; i<27; i++) payload_mux[i] <= 8'd0;
                end
                default: begin
                    for (int i=0; i<4; i++) out_header[i] <= 8'd0;
                    for (int i=0; i<27; i++) payload_mux[i] <= 8'd0;
                end
            endcase
        end
    end

    assign out_payload = payload_mux;
endmodule
```

---

# 3. Ovládač pre periodické vysielanie infoframov (štandard HDMI definuje intervaly, napr. SPD každých cca 1 sekundu)

```systemverilog
module infoframe_controller (
    input logic clk,            // pixel clock alebo iný vhodný hodinový signál
    output logic [1:0] infoframe_select,
    output logic infoframe_enable
);
    localparam int SPD_INTERVAL = 60_000_000;  // príklad pre 60 MHz clock, cca 1 sekunda
    int counter = 0;

    always_ff @(posedge clk) begin
        if (counter == 0) begin
            infoframe_select <= 2'd0;    // SPD infoframe
            infoframe_enable <= 1'b1;
            counter <= SPD_INTERVAL - 1;
        end else begin
            infoframe_enable <= 1'b0;
            counter <= counter - 1;
        end
    end
endmodule
```

---

# Zhrnutie

* `spd_infoframe` vytvorí správne SPD infoframe s CRC a fixnou dĺžkou 27 bajtov.
* `infoframe_mux` vyberá medzi SPD, AVI, Audio infoframami podľa ovládacieho signálu.
* `infoframe_controller` periodicky aktivuje SPD infoframe podľa definovaného intervalu.

---

Ak chceš, môžeme rozpracovať:

* **Implementáciu ďalších infoframov** (AVI, Audio) podľa HDMI špecifikácie.
* **Testbench na simuláciu správnosti SPD a multiplexovania**.
* **Integráciu do existujúceho HDMI modulu** s generovaním TMDS.

Chceš, aby som ti pripravil ďalšie moduly, alebo testbench? Alebo niečo špecifické?
