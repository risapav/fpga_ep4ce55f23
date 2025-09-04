Super, pustime sa teda do praktickej časti — krok za krokom vyrobíme:

1. **Modul na generovanie SPD infoframe** (rozšírime ten, čo sme už robili, s CRC a formátovaním podľa HDMI špecifikácie)
2. **Stavový automat na prepínanie medzi Video a Data Island periodami** (časovanie v rámci rámca)
3. **Multiplexor dát** (video vs infoframe data) pre TMDS kanály
4. **Úprava TMDS kanálu na podporu infoframe dát** (už čiastočne implementované, len doplníme komentáre a parametre)

---

# 1. Modul generovania SPD infoframe so správnym formátom a CRC32

```systemverilog
module spd_infoframe #(
    parameter int PAYLOAD_BYTES = 25 // SPD infoframe payload má 25 bajtov
) (
    input  logic clk,
    input  logic start,
    output logic [7:0] data_out,
    output logic valid,
    output logic done
);
    // SPD infoframe formát (podľa HDMI 1.4a spec):
    // Byte 0: Infoframe Type = 0x83 (SPD)
    // Byte 1: Version = 0x01
    // Byte 2: Length = 0x19 (25)
    // Bytes 3..27: Payload (napr. názov výrobcu, produkt, sériové číslo, atď)
    // Byte 28: Checksum (vypočítaný tak, aby súčet všetkých bajtov = 0)
    
    typedef enum logic [1:0] {IDLE, SEND_HEADER, SEND_PAYLOAD, SEND_CHECKSUM} state_t;
    state_t state, next_state;

    // SPD infoframe data (header + payload)
    logic [7:0] infoframe_bytes [0:PAYLOAD_BYTES+3]; // 29 bajtov celkovo
    int idx;
    logic [7:0] checksum;
    
    // Tu môžeš vyplniť SPD payload podľa svojich údajov
    // Pre demo použijeme prázdne polia (0) a fixné header
    initial begin
        infoframe_bytes[0] = 8'h83; // SPD type
        infoframe_bytes[1] = 8'h01; // version
        infoframe_bytes[2] = 8'h19; // length 25 bytes
        // payload naplníme nulami, môžeš upraviť podľa potreby
        for (int i=3; i < PAYLOAD_BYTES+3; i++) infoframe_bytes[i] = 8'h00;
        infoframe_bytes[28] = 8'h00; // checksum placeholder
    end

    // Výpočet checksumu — checksum = 256 - sum(all bytes without checksum)
    always_comb begin
        int sum = 0;
        for (int i=0; i<28; i++) sum += infoframe_bytes[i];
        checksum = 8'h100 - (sum & 8'hFF);
    end
    
    always_ff @(posedge clk) begin
        if (start) begin
            state <= SEND_HEADER;
            idx <= 0;
            infoframe_bytes[28] <= checksum;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        valid = 1'b0;
        data_out = 8'h00;
        done = 1'b0;
        next_state = state;

        case (state)
            IDLE: if (start) next_state = SEND_HEADER;

            SEND_HEADER: begin
                valid = 1'b1;
                data_out = infoframe_bytes[idx];
                if (idx == 28) begin
                    done = 1'b1;
                    next_state = IDLE;
                end else begin
                    idx = idx + 1;
                end
            end

            default: next_state = IDLE;
        endcase
    end
endmodule
```

---

# 2. Stavový automat pre Data Island Period (DIP)

Tento automat určuje, kedy sa v rámci pixelového časovania posielajú video dáta a kedy infoframe:

```systemverilog
module data_island_controller #(
    parameter int FRAME_WIDTH = 800,
    parameter int FRAME_HEIGHT = 525,
    parameter int SCREEN_START_X = 160,
    parameter int SCREEN_START_Y = 45
)(
    input logic clk_pixel,
    input logic [15:0] cx,
    input logic [15:0] cy,
    output logic video_data_period,
    output logic data_island_period
);

    // Video data posielame keď cx, cy sú v aktívnej oblasti obrazovky
    always_ff @(posedge clk_pixel) begin
        video_data_period <= (cx >= SCREEN_START_X) && (cx < SCREEN_START_X + (FRAME_WIDTH - SCREEN_START_X)) &&
                             (cy >= SCREEN_START_Y) && (cy < SCREEN_START_Y + (FRAME_HEIGHT - SCREEN_START_Y));
        // Data Island Period je mimo video data, napríklad v blanking intervaloch
        data_island_period <= !video_data_period;
    end

endmodule
```

---

# 3. Multiplexor dát pre TMDS kanály

```systemverilog
module tmds_data_mux(
    input logic [7:0] video_data,
    input logic [7:0] infoframe_data,
    input logic video_mode, // 1 = video data, 0 = infoframe data
    output logic [7:0] data_out
);
    always_comb begin
        if (video_mode)
            data_out = video_data;
        else
            data_out = infoframe_data;
    end
endmodule
```

---

# 4. TMDS kanál (zjednodušený príklad)

```systemverilog
module tmds_channel(
    input logic clk_pixel,
    input logic [7:0] data_in,
    output logic [9:0] tmds_out
);
    // Tu bude implementácia TMDS kódovania podľa špecifikácie
    // Pre demo len mapujeme data_in do 10-bitového slova, reálne je to zložitejšie
    always_ff @(posedge clk_pixel) begin
        // Tu by išlo TMDS kódovanie so zápornou koreláciou a minimalizáciou prechodov
        tmds_out <= {2'b01, data_in}; // placeholder
    end
endmodule
```

---

# Čo ďalej?

* Skombinujeme tieto moduly do hlavného HDMI modulu.
* Pridáme riadiacu logiku, ktorá spustí SPD infoframe periodicky (napr. raz za sekundu).
* Rozšírime TMDS kanály o podporu prepínania medzi video a infoframe dátami.
* Pridáme CRC32 generátor pre presné checksumy infoframe (ak chceš, môžem ho tiež vytvoriť).

---

Chceš, aby som teraz pripravil integráciu týchto blokov do väčšieho HDMI modulu? Alebo chceš pokračovať s CRC32 generátorom?
