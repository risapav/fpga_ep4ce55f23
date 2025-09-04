Jasné, tu máš doplnené a okomentované pomocné moduly `packet_picker`, `packet_assembler` a `tmds_channel` v SystemVerilogu, aby spolu ladili s hlavným HDMI modulom. Každý je v jednoduchom syntetizovateľnom tvare s potrebnými vstupmi/výstupmi a popisom.

---

### 1) `packet_picker.sv`

```systemverilog
// packet_picker.sv
// Modul pre výber HDMI paketov (infoframe, audio, atď.) počas data island period
module packet_picker #(
    parameter int VIDEO_ID_CODE = 1,
    parameter real VIDEO_RATE = 25.2e6,
    parameter int AUDIO_RATE = 44100,
    parameter int AUDIO_BIT_WIDTH = 16,
    parameter bit [8*8-1:0] VENDOR_NAME = "Unknown",
    parameter bit [8*16-1:0] PRODUCT_DESCRIPTION = "FPGA",
    parameter bit [7:0] SOURCE_DEVICE_INFORMATION = 8'h00
)(
    input  logic            clk_pixel,
    input  logic            clk_audio,
    input  logic            video_field_end,
    input  logic            packet_enable,
    output logic [4:0]      packet_pixel_counter,
    input  logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word [1:0], // stereo samples
    output logic [23:0]     header,
    output logic [55:0]     sub [3:0]
);

    // Packet counter (counts from 0 to 31, wraps)
    always_ff @(posedge clk_pixel) begin
        if (video_field_end || !packet_enable)
            packet_pixel_counter <= 0;
        else if (packet_enable)
            packet_pixel_counter <= packet_pixel_counter + 1;
    end

    // Vzory pre HDMI infoframes a audio pakety:
    // Toto je zjednodušené, napr. AVI infoframe header + data

    // Predpripravené infoframe hlavičky - pre ilustráciu
    // Skutočná implementácia by mala obsahovať aj kontrolné súčty, CRC atď.
    localparam [23:0] AVI_INFOFRAME_HEADER = 24'h82_02_0D; // Example: type=0x82, version=2, length=13
    localparam [55:0] AVI_INFOFRAME_DATA = {56'h00_00_00_00_00_00_00}; // Dátová časť 13 bajtov (zjednodušenie)

    // Výber dát podľa čísla paketu (len príklad)
    always_comb begin
        case (packet_pixel_counter)
            5'd0: header = AVI_INFOFRAME_HEADER;
            default: header = 24'd0;
        endcase
    end

    // Podmoduly dát - tu je jednoduché nastavenie nulových dát (doplniť podľa potreby)
    genvar i;
    generate
        for (i=0; i<4; i++) begin : subgen
            always_comb sub[i] = 56'd0;
        end
    endgenerate

endmodule
```

---

### 2) `packet_assembler.sv`

```systemverilog
// packet_assembler.sv
// Assembler pre rozloženie paketových dát do bitových sekvencií pre TMDS kódovanie
module packet_assembler (
    input  logic             clk_pixel,
    input  logic             data_island_period,
    input  logic [23:0]      header,
    input  logic [55:0]      sub [3:0],
    output logic [8:0]       packet_data,
    input  logic [4:0]       counter
);

    // Počet bitov v pakete (napr. 32 bajtov = 256 bitov, ale tu zjednodušené na 9-bitové slová)
    // Pre ilustráciu postupne vyskladáme 9-bitové slová z headeru + sub dát
    // Reálne by sa mal dekódovať správny formát podľa HDMI špecifikácie.

    always_ff @(posedge clk_pixel) begin
        if (!data_island_period) begin
            packet_data <= 9'd0;
        end else begin
            case (counter)
                5'd0: packet_data <= {1'b0, header[23:15]};       // prvých 9 bitov hlavičky
                5'd1: packet_data <= {1'b0, header[14:6]};
                5'd2: packet_data <= {1'b0, header[5:0], 3'b000};
                default: packet_data <= 9'd0; // neskôr dátové časti (sub), tu len nula
            endcase
        end
    end

endmodule
```

---

### 3) `tmds_channel.sv`

```systemverilog
// tmds_channel.sv
// TMDS kanál pre kódovanie 8-bitového video dátového slova do 10-bit TMDS kódu
module tmds_channel #(
    parameter int CN = 0 // číslo kanálu (0=modrý,1=zelený,2=červený)
)(
    input  logic         clk_pixel,
    input  logic [7:0]   video_data,
    input  logic [3:0]   data_island_data,
    input  logic [1:0]   control_data,
    input  logic [2:0]   mode,
    output logic [9:0]   tmds
);

    // Interné premenné pre TMDS kódovanie
    logic [3:0] nb1s;         // počet 1-bitov v video_data
    logic [8:0] q_m;          // medzikódovanie (9-bit)
    logic [3:0] cnt_ones;     // pomocný počítadlo
    logic       invert_q_m;   // invertovanie bitov

    // Krok 1: Spočítať počet 1-bitov v video_data
    function automatic [3:0] count_ones(input logic [7:0] val);
        int i;
        count_ones = 0;
        for (i=0; i<8; i++) count_ones += val[i];
    endfunction

    always_comb begin
        nb1s = count_ones(video_data);
    end

    // Krok 2: TMDS 8b->9b kódovanie
    // - podľa TMDS špecifikácie (HDMI 1.4a)
    always_comb begin
        int i;
        q_m[0] = video_data[0];
        for (i=1; i<8; i++)
            q_m[i] = q_m[i-1] ^ video_data[i];

        // invertovanie ak počet 1-bitov väčší ako počet 0-bitov alebo rovnosť a q_m[0] == 0
        if ((nb1s > 4) || (nb1s == 4 && video_data[0] == 0))
            invert_q_m = 1;
        else
            invert_q_m = 0;
        
        for (i=0; i<8; i++)
            q_m[i] = invert_q_m ? ~q_m[i] : q_m[i];

        q_m[8] = ~invert_q_m; // pridanie invert bitu
    end

    // Krok 3: Výber výstupu podľa režimu (video, control, data island)
    always_comb begin
        case (mode)
            3'd0: tmds = 10'b1101010100; // predvolený stav (blanc)
            3'd1: tmds = {q_m[8], q_m[7:0], 1'b0}; // video_data kódovanie (simplified)
            3'd2: tmds = {8'b10101010, control_data}; // control kódovanie (simplified)
            3'd3: tmds = {2'b00, data_island_data, 5'b00000}; // data island kódovanie (simplified)
            3'd4: tmds = 10'b1111111111; // guard band (simplified)
            default: tmds = 10'b1101010100;
        endcase
    end

endmodule
```

---

### Čo teraz?

Toto je základ, ktorý by mal fungovať ako základ HDMI vysielača v Quartuse, syntetizovateľný a rozšíriteľný. Ak chceš, môžem ti pomôcť doplniť presné HDMI infoframe formáty, lepšie TMDS kódovanie, alebo aj synchronizáciu audio dát.

Píšeš, čo by si chcel upraviť alebo doplniť ďalej!
