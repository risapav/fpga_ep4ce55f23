Super, poďme teda spraviť základný **SystemVerilog modul Packet Picker** — ktorý prepína medzi video paketmi a info/data paketmi na základe časovača (timeru), aby sme simulovali HDMI packet scheduling.

---

### Packet Picker - základný koncept:

* Vstupy:

  * `video_data` — pixelové dáta
  * `audio_data` — audio vzorky (tu pre jednoduchosť ignorujeme, dá sa pridať)
  * `spd_packet`, `avi_packet`, `data_packet` — predgenerované info/data pakety
  * `clk`, `reset`

* Výstup:

  * `packet_out` — vybraný paket na odoslanie TMDS encoderu
  * `packet_valid` — signalizuje platnosť dát na výstupe

* Interný timer: riadi prepínanie medzi video a info/data paketmi (napr. video posielame 90% času, infoframe 10%)

---

### Príklad kódu Packet Picker (SystemVerilog)

```systemverilog
module packet_picker #(
    parameter PACKET_WIDTH = 32,         // šírka paketu (slovo)
    parameter VIDEO_PACKET_COUNT = 90,  // % času video pakety
    parameter INFO_PACKET_COUNT = 10    // % času info/data pakety
)(
    input  logic clk,
    input  logic reset,

    // Vstupy paketov
    input  logic [PACKET_WIDTH-1:0] video_packet,
    input  logic [PACKET_WIDTH-1:0] spd_packet,
    input  logic [PACKET_WIDTH-1:0] avi_packet,
    input  logic [PACKET_WIDTH-1:0] data_packet,

    output logic [PACKET_WIDTH-1:0] packet_out,
    output logic packet_valid
);

    // Interný čítač pre prepínanie paketov (0..99)
    logic [6:0] pkt_counter;

    // Stav pre multiplexer výber paketu
    typedef enum logic [1:0] {
        VIDEO_PKT = 2'd0,
        SPD_PKT   = 2'd1,
        AVI_PKT   = 2'd2,
        DATA_PKT  = 2'd3
    } pkt_state_t;

    pkt_state_t current_pkt = VIDEO_PKT;

    // Rozdelenie času na video / info pakety
    localparam TOTAL_COUNT = VIDEO_PACKET_COUNT + INFO_PACKET_COUNT;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pkt_counter <= 0;
            current_pkt <= VIDEO_PKT;
            packet_out <= 0;
            packet_valid <= 0;
        end else begin
            // Čítač cykluje 0..TOTAL_COUNT-1
            if (pkt_counter == TOTAL_COUNT - 1)
                pkt_counter <= 0;
            else
                pkt_counter <= pkt_counter + 1;

            // Vyber paketu podľa čítača
            if (pkt_counter < VIDEO_PACKET_COUNT) begin
                // Posielame video paket
                current_pkt <= VIDEO_PKT;
                packet_out <= video_packet;
                packet_valid <= 1;
            end else begin
                // Posielame info/data paket podľa rotácie
                case (current_pkt)
                    VIDEO_PKT: begin
                        current_pkt <= SPD_PKT;
                        packet_out <= spd_packet;
                        packet_valid <= 1;
                    end
                    SPD_PKT: begin
                        current_pkt <= AVI_PKT;
                        packet_out <= avi_packet;
                        packet_valid <= 1;
                    end
                    AVI_PKT: begin
                        current_pkt <= DATA_PKT;
                        packet_out <= data_packet;
                        packet_valid <= 1;
                    end
                    DATA_PKT: begin
                        current_pkt <= SPD_PKT; // Cyklus SPD->AVI->DATA->SPD...
                        packet_out <= spd_packet;
                        packet_valid <= 1;
                    end
                    default: begin
                        current_pkt <= SPD_PKT;
                        packet_out <= spd_packet;
                        packet_valid <= 1;
                    end
                endcase
            end
        end
    end

endmodule
```

---

### Komentáre k modulu:

* `pkt_counter` zabezpečuje časové delenie paketov podľa parametrov `VIDEO_PACKET_COUNT` (napr. 90) a `INFO_PACKET_COUNT` (napr. 10).
* Počas 90 cyklov odosiela `video_packet`.
* Počas 10 cyklov rotuje medzi `spd_packet`, `avi_packet` a `data_packet`.
* `packet_valid` indikuje, že výstupný paket je platný.
* Toto je veľmi jednoduchá logika — v praxi môže byť časovanie presnejšie, synchronizované so signálmi HDMI blankingu atď.

---

Ak chceš, môžem pridať:

* Podporu pre audio pakety
* Presné časovanie podľa HDMI blankingu
* Výstup viacslovových paketov (nie len 32b slová)
* Príklad generátorov jednotlivých paketov (SPD, AVI, Data)

Chceš pokračovať? Alebo máš otázky?
