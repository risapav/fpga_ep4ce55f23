Skvelé! Pokračujme teda v **skladaní celého SPD (Source Product Descriptor) InfoFrame-u** pre HDMI.

---

## 🧩 Čo je SPD InfoFrame?

SPD (Source Product Descriptor) InfoFrame poskytuje informácie o zariadení, ktoré HDMI signál vysiela (napr. "PC", "Blu-Ray Player"). Obsahuje:

* Typ rámca (`Type` = `0x83`)
* Verziu (`Version` = `0x01`)
* Dĺžku payloadu (`Length` = `25`)
* EIA/CEA ID (`0x000000`)
* Výrobca (8 znakov ASCII)
* Názov produktu (16 znakov ASCII)
* Info o type zariadenia (napr. 0x01 = DVD Player)
* CRC8

---

## 🧱 Kompletný SPD InfoFrame Modul (SystemVerilog)

```systemverilog
module spd_infoframe_generator (
    input  logic        clk,
    input  logic        reset_n,
    output logic [8*27-1:0] spd_frame, // 27 bajtov vrátane CRC
    output logic        valid
);

    // -----------------------------
    // Konštanty a payload dáta
    // -----------------------------
    localparam [7:0] TYPE    = 8'h83;
    localparam [7:0] VERSION = 8'h01;
    localparam [7:0] LENGTH  = 8'd25;

    // Vendor name: 8 znakov
    logic [7:0] vendor_name [0:7] = {
        "O", "P", "E", "N", "A", "I", " ", " " // Doplnené medzerami
    };

    // Product name: 16 znakov
    logic [7:0] product_name [0:15] = {
        "C","h","a","t","G","P","T"," ","V","i","d","e","o"," "," "," "
    };

    // Source device type: napr. 0x01 = DVD Player, 0x00 = Reserved
    localparam [7:0] DEVICE_TYPE = 8'h00;

    // -----------------------------------
    // CRC8 generátor cez vlastný modul
    // -----------------------------------
    logic        crc_en;
    logic [7:0]  crc_in;
    logic [7:0]  crc_out;

    crc8 crc8_inst (
        .clk(clk),
        .reset_n(reset_n),
        .enable(crc_en),
        .data_in(crc_in),
        .crc_out(crc_out)
    );

    // -----------------------------------
    // FSM na skladanie frame + výpočet CRC
    // -----------------------------------
    typedef enum logic [3:0] {
        IDLE, INIT, SEND_HEADER, SEND_VENDOR,
        SEND_PRODUCT, SEND_DEVTYPE, DONE
    } state_t;

    state_t state;
    int     idx;
    logic [7:0] frame_data [0:26]; // 27 bajtov (header + payload + CRC)

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            idx   <= 0;
            valid <= 0;
            crc_en <= 0;
        end else begin
            case (state)
                IDLE: begin
                    idx <= 0;
                    crc_en <= 0;
                    valid <= 0;
                    state <= INIT;
                end

                INIT: begin
                    // Header
                    frame_data[0] = TYPE;
                    frame_data[1] = VERSION;
                    frame_data[2] = LENGTH;

                    crc_en <= 1;
                    crc_in <= TYPE;
                    state <= SEND_HEADER;
                    idx <= 3;
                end

                SEND_HEADER: begin
                    crc_in <= VERSION;
                    state <= SEND_VENDOR;
                end

                SEND_VENDOR: begin
                    crc_in <= LENGTH;
                    for (int i = 0; i < 8; i++) begin
                        frame_data[idx] = vendor_name[i];
                        crc_in <= vendor_name[i];
                        idx++;
                    end
                    state <= SEND_PRODUCT;
                end

                SEND_PRODUCT: begin
                    for (int i = 0; i < 16; i++) begin
                        frame_data[idx] = product_name[i];
                        crc_in <= product_name[i];
                        idx++;
                    end
                    state <= SEND_DEVTYPE;
                end

                SEND_DEVTYPE: begin
                    frame_data[idx] = DEVICE_TYPE;
                    crc_in <= DEVICE_TYPE;
                    idx++;
                    crc_en <= 0;
                    state <= DONE;
                end

                DONE: begin
                    frame_data[idx] = crc_out; // posledný bajt = CRC8
                    idx++;
                    // Zbaliť výstupný vektor
                    for (int i = 0; i < 27; i++) begin
                        spd_frame[i*8 +: 8] <= frame_data[i];
                    end
                    valid <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
```

---

## ✳️ Poznámky

* Celý SPD rámec je 27 bajtov: 3 bajty hlavička + 25 payload + 1 bajt CRC8
* Všetky bajty sa posielajú ako `spd_frame` (napr. pre ďalšiu konverziu do TMDS)
* FSM spracováva všetko sekvenčne – výpočet CRC8 v reálnom čase

---

## ❓ Prečo sa používa CRC8 a CRC32?

| CRC typ | Použitie                 | Dĺžka  | Účel                       |
| ------- | ------------------------ | ------ | -------------------------- |
| CRC8    | InfoFrames (AVI, SPD...) | 8 bit  | Detekcia chýb v rámcoch    |
| CRC32   | TMDS link integrity      | 32 bit | Kontrola integrity pixelov |

* **CRC8** je rýchly a vhodný pre krátke správy (ako HDMI infoframe).
* **CRC32** sa používa napr. pri TMDS video packets na overenie integrity niekoľkých pixelov (napr. 2D blanking, data islands...).

---

Môžeme teraz pokračovať:

* Pridaním testbenchu pre SPD modul?
* Zaviesť CRC32 pre TMDS video packet kontrolu?
* Skombinovať TMDS kódovač + SPD rámec do HDMI Data Island generatora?

Čo preferuješ?
